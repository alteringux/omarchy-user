import QtQuick
import QtQuick.Window
import "../shared"
import "RecoveryTrigger.js" as Trigger

// PanelKeyCatcher signal API with a native control path. F6 enters/leaves
// controls; section-driven panels retain Tab navigation while this owns focus.
Item {
  id: root
  property bool blocked: false
  property bool initialFocusHandled: false
  property bool sectionNavigation: false
  // Owner eligibility and user enrollment are separate gates.
  property bool recoveryPilot: false
  property bool recoveryPilotVerified: false
  property bool recoveryActivationBinding: false
  property string shortcutSource: "panel"
  property string shortcutContext: "Current panel · shortcut focus"
  property string escapeShortcutDescription: "Close the panel"
  property string escapeShortcutContext: shortcutContext
  property string tabShortcutDescription: sectionNavigation
    ? "Switch between panels in shortcut focus; move between controls in control focus"
    : "Move between controls"
  property string tabShortcutContext: shortcutContext
  property var additionalShortcutDescriptions: []
  readonly property var shortcutDescriptions: ([
    { keys: "F1", description: "Show recovery and general shortcut help", context: shortcutContext },
    { keys: "F6", description: "Switch between panel shortcuts and controls", context: shortcutContext },
    { keys: "Esc", description: escapeShortcutDescription, context: escapeShortcutContext },
    { keys: "Tab / Shift + Tab", description: tabShortcutDescription, context: tabShortcutContext }
  ]).concat(additionalShortcutDescriptions)
  signal moveRequested(int dx, int dy)
  signal activateRequested()
  signal returnRequested()
  signal closeRequested()
  signal deleteRequested()
  signal tabRequested(int direction)
  signal textKey(string text)
  focus: true
  property var recoveryState: Trigger.createState()
  property var heldPresses: ({})
  property int pressSerial: 0
  readonly property bool recoveryEnabled: recoveryPilot && recoveryPilotVerified && TextPreferences.suggestRecoveryShortcuts
  readonly property bool recoverySuggestionVisible: suggestions.visible
  readonly property bool recoveryCatalogReady: suggestions.ready
  signal recoveryRevealed()
  RecoveryClock { id: clock }
  RecoverySuggestions {
    id: suggestions
    owner: root
    localBindings: root.shortcutDescriptions
    onDismissed: root.dismissRecovery()
    onHelpRequested: root.openHelp()
  }
  RecoveryHelp { id: fallbackHelp; returnFocusItem: root }
  function dismissRecovery() {
    if (recoveryState.visible) Trigger.dismiss(recoveryState, clock.nowMs())
    else Trigger.clear(recoveryState)
    suggestions.shown = false
    heldPresses = ({})
  }
  function clearRecovery() {
    if (suggestions.shown) dismissRecovery()
    else { Trigger.clear(recoveryState); heldPresses = ({}) }
  }
  function preloadRecovery() {
    if (recoveryEnabled && visible && Window.window && Window.window.visible) suggestions.refresh()
  }
  function openHelp() {
    dismissRecovery()
    const help = findHelp(root)
    if (help) help.openRecoveryHelp()
    else fallbackHelp.show()
  }
  function observeDispatch(event, outcome) {
    if (!recoveryEnabled) return
    const key = String(event.key)
    if (!heldPresses[key] && !event.isAutoRepeat) heldPresses[key] = ++pressSerial
    const commandModifier = !!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
    const modifierOnly = event.key === Qt.Key_Control || event.key === Qt.Key_Alt
      || event.key === Qt.Key_Meta || event.key === Qt.Key_Shift || event.key === Qt.Key_AltGr
    const revealed = Trigger.observe(recoveryState, {
      enabled: recoveryEnabled, owned: activeFocus && visible && Window.window && Window.window.visible && Window.window.active,
      editor: blocked, composing: blocked, outcome: outcome, commandModifier: commandModifier,
      typing: !commandModifier && !!event.text, modifierOnly: modifierOnly, autoRepeat: event.isAutoRepeat,
      chord: String(event.modifiers) + ":" + key, pressId: heldPresses[key], context: shortcutSource
    }, clock.nowMs())
    if (revealed) { suggestions.reveal(); recoveryRevealed() }
  }
  onRecoveryEnabledChanged: {
    clearRecovery()
    if (!recoveryEnabled) recoveryState = Trigger.createState()
    else preloadRecovery()
  }
  onBlockedChanged: if (blocked) clearRecovery()
  onActiveFocusChanged: if (!activeFocus) clearRecovery()
  onVisibleChanged: { if (!visible) clearRecovery(); else preloadRecovery() }
  Component.onCompleted: preloadRecovery()
  function findHelp(item) {
    if (!item.visible || !item.enabled) return null
    if (typeof item.openRecoveryHelp === "function") return item
    for (let i = 0; i < item.children.length; i++) {
      const match = findHelp(item.children[i])
      if (match) return match
    }
    return null
  }
  function enterControls() {
    const target = nextItemInFocusChain(true)
    if (target && target !== root) target.forceActiveFocus(Qt.TabFocusReason)
  }
  function revealFocusedControl() {
    const item = root.Window.window ? root.Window.window.activeFocusItem : null
    if (!item || !item.visible) return
    let owner = item
    while (owner && owner !== root) owner = owner.parent
    if (!owner) return
    // Native tab navigation must not leave the focus ring behind a clipped
    // scroll viewport. Walk from the innermost viewport out so nested panel
    // sections reveal the same control without changing selection or actions.
    let viewport = item.parent
    while (viewport && viewport !== root) {
      if (typeof viewport.contentY === "number" && viewport.contentItem
          && typeof viewport.contentHeight === "number") {
        const point = item.mapToItem(viewport.contentItem, 0, 0)
        const lower = point.y + item.height
        const maximum = Math.max(0, viewport.contentHeight - viewport.height)
        if (point.y < viewport.contentY)
          viewport.contentY = Math.max(0, Math.min(maximum, point.y))
        else if (lower > viewport.contentY + viewport.height)
          viewport.contentY = Math.max(0, Math.min(maximum, lower - viewport.height))
      }
      viewport = viewport.parent
    }
  }
  Connections {
    target: root.Window.window
    function onActiveFocusItemChanged() { Qt.callLater(root.revealFocusedControl) }
    function onVisibleChanged() {
      if (!root.Window.window.visible) root.clearRecovery()
      else root.preloadRecovery()
    }
    function onActiveChanged() {
      if (!root.Window.window.active) root.clearRecovery()
    }
  }
  Keys.onReleased: function(event) { delete heldPresses[String(event.key)] }
  Keys.onPressed: function(event) {
    initialFocusHandled = true
    // Dedicated help/focus keys remain reachable from editors. Editing,
    // composition and Escape still retain the owner's blocked contract.
    if (event.key === Qt.Key_F1) {
      observeDispatch(event, "handled")
      openHelp()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_F6) {
      observeDispatch(event, "handled")
      if (root.activeFocus) enterControls()
      else root.forceActiveFocus()
      event.accepted = true
      return
    }
    if (blocked) { clearRecovery(); return }
    if (event.key === Qt.Key_Escape) {
      observeDispatch(event, "handled")
      if (suggestions.shown) dismissRecovery()
      else closeRequested()
      event.accepted = true
      return
    }
    // Child controls own activation. Their Enter must not also activate a
    // panel cursor. Editors retain the caller's existing blocked contract.
    if (!root.activeFocus) return
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      observeDispatch(event, "handled")
      const direction = (event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1
      if (sectionNavigation) tabRequested(direction)
      else {
        const target = nextItemInFocusChain(direction > 0)
        if (target && target !== root) target.forceActiveFocus(direction > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason)
      }
      event.accepted = true
      return
    }
    if (recoveryPilot) {
      // These owners declare actual activation bindings. Focused children
      // retain native input; neither pilot has another modified-key layer.
      if (recoveryActivationBinding && (event.key === Qt.Key_Return
          || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
        observeDispatch(event, "handled")
        if (event.key !== Qt.Key_Space) returnRequested()
        activateRequested()
        event.accepted = true
        return
      }
      observeDispatch(event, "unhandled")
      // Modified unknown keys cannot invoke legacy text-key aliases.
      if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    }
    if (event.key === Qt.Key_Down || event.text === "j") { moveRequested(0, 1); event.accepted = true; return }
    if (event.key === Qt.Key_Up || event.text === "k") { moveRequested(0, -1); event.accepted = true; return }
    if (event.key === Qt.Key_Right || event.text === "l") { moveRequested(1, 0); event.accepted = true; return }
    if (event.key === Qt.Key_Left || event.text === "h") { moveRequested(-1, 0); event.accepted = true; return }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { returnRequested(); activateRequested(); event.accepted = true; return }
    if (event.key === Qt.Key_Space) { activateRequested(); event.accepted = true; return }
    if (event.text === "x" || event.text === "X") { deleteRequested(); event.accepted = true; return }
    if (event.text && event.text.length === 1) textKey(event.text)
  }
}
