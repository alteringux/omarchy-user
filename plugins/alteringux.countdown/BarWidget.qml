import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit
import "Model.js" as Model

// Bar widget: a horizontal marquee of every countdown — "21d · Disneyland
//   •   90d · Move house" — soonest first, scrolling left-to-right as a live
// ticker. Click opens the add/list panel. State is a
// flat JSON list of { label, targetEpoch } under ~/.local/state/omarchy/;
// days-remaining is always derived from the stored target so a countdown
// keeps ticking across restarts and rolls over on its own at local midnight.
// Same bar-widget + click-panel shape as alteringux.timers.
BarWidget {
  id: root
  moduleName: "alteringux.countdown"

  // State + history are two JSON files under ~/.local/state/omarchy/, each
  // managed by a Kit.Store (FileView + atomic write + `mkdir -p` + the 200 ms
  // save debounce — written once in alteringux.kit instead of copied in here).
  // The Store instances are defined further down; `state` / `history` read and
  // write straight through them.
  property alias state: stateStore.value
  property alias history: historyStore.value
  readonly property bool stateLoaded: stateStore.loaded
  readonly property bool historyLoaded: historyStore.loaded
  readonly property var added: history && history.added ? history.added : []

  readonly property var entries: state && state.entries ? state.entries : []
  readonly property bool hasEntries: entries.length > 0

  // Bumped by the slow tick and on panel open so every daysRemaining binding
  // re-evaluates. Day granularity — no need to spin faster.
  property double nowMs: Date.now()

  readonly property string marqueeContent: stateLoaded ? Model.marqueeText(root.entries, root.nowMs) : ""
  readonly property string emptyText: "  Countdown"
  // Marquee viewport width in raw px (comparable to the other widgets' label
  // widths). The widget stays this wide whenever countdowns exist; a single
  // short countdown fits without scrolling, longer/multiple ones scroll.
  readonly property real marqueeViewport: 300

  readonly property var guard: Kit.BugGuard.create("alteringux.countdown", function(argv) { Quickshell.execDetached(argv) })

  // ---- persistence: two JSON files, each via the shared Kit.Store -------
  // Store owns the FileView, atomic writes, the ~/.local/state/omarchy/ path,
  // `mkdir -p`, and the save debounce. We hand it a file name and the matching
  // tolerant parser from Model.js; it gives back `value` (aliased above to
  // `state` / `history`) and `loaded`. Mutations go: assign a fresh object to
  // `state` / `history`, then call `<store>.save()`.
  Kit.Store {
    id: stateStore
    fileName: "countdowns.json"
    parse: function (raw) { return Model.parseState(raw) }
    onLoadedChanged: if (loaded) root.nowMs = Date.now()
  }

  // A SEPARATE rolling log of added countdowns (label + day count, capped in
  // Model.js) — feeds the panel's most-used-label chips. The active list
  // itself stays history-free.
  Kit.Store {
    id: historyStore
    fileName: "countdown-history.json"
    parse: function (raw) { return Model.parseHistory(raw) }
  }

  function entryById(id) {
    var list = root.entries
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }

  // ---- actions ------------------------------------------------------
  function addEntry(label, days) {
    guard.run("addEntry", function() {
      var before = root.entries.length
      root.state = Model.addEntry(root.state, label, days)
      if (root.entries.length !== before) {
        root.nowMs = Date.now()
        stateStore.save()
        if (root.historyLoaded) {
          root.history = Model.recordAdd(root.history, label, days)
          historyStore.save()
        }
      }
    })
  }

  // Add by an absolute target epoch (the panel's date picker). History still
  // records a day count so the label chips keep working.
  function addEntryAt(label, targetEpoch) {
    guard.run("addEntryAt", function() {
      var before = root.entries.length
      root.state = Model.addEntryAt(root.state, label, targetEpoch)
      if (root.entries.length !== before) {
        root.nowMs = Date.now()
        stateStore.save()
        if (root.historyLoaded) {
          root.history = Model.recordAdd(root.history, label, Model.daysRemaining(targetEpoch, root.nowMs))
          historyStore.save()
        }
      }
    })
  }

  function removeEntry(id) {
    guard.run("removeEntry", function() {
      root.state = Model.removeEntry(root.state, id)
      stateStore.save()
    })
  }

  // Edit-in-place: rename one countdown from its card. Same persist path as
  // add/remove. See docs/adr/0003.
  function renameEntry(id, label) {
    guard.run("renameEntry", function() {
      root.state = Model.renameEntry(root.state, id, label)
      stateStore.save()
    })
  }

  function clearEntries() {
    guard.run("clearEntries", function() {
      root.state = Model.defaultState()
      stateStore.save()
    })
  }

  // Forget one remembered "usual label" — the × on that chip in the panel.
  // Other remembered labels and the active countdown list are left untouched.
  function forgetLabel(label) {
    guard.run("forgetLabel", function() {
      if (!root.historyLoaded) return
      root.history = Model.forgetLabel(root.history, label)
      historyStore.save()
    })
  }

  // ---- tick -------------------------------------------------------
  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  onOpenedChanged: if (opened) nowMs = Date.now()

  // ---- IPC ------------------------------------------------------
  IpcHandler {
    target: "alteringux.countdown"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function add(days: int, label: string): void { root.addEntry(label, days) }
    function addDate(date: string, label: string): void { root.addEntryAt(label, Model.epochForKey(date)) }
    function removeEntry(id: string): void { root.removeEntry(id) }
    function rename(id: string, label: string): void { root.renameEntry(id, label) }
    function clear(): void { root.clearEntries() }
    function forgetLabel(label: string): void { root.forgetLabel(label) }
    function status(): string {
      return guard.call("ipc.status", function() {
        return JSON.stringify({
          count: root.entries.length,
          soonestDays: Model.soonestDays(root.entries, Date.now())
        })
      }, "{}")
    }
  }

  // ---- Popup panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.emptyText
    labelVisible: !root.hasEntries
    hasVisualContent: true
    fixedWidth: root.hasEntries ? root.marqueeViewport : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.hasEntries ? Model.listText(root.entries, root.nowMs) : ""

    onPressed: function(b) {
      root.togglePanel()
    }

    // ---- marquee overlay -------------------------------------------
    // Two identical copies of the text in a Row; the Row's x animates one
    // full copy-width right (from -copyWidth to 0) on an infinite loop, so
    // copy 1 slides into the gap copy 2 leaves — a seamless scroll.
    // When it fits, the Binding parks it centred and the animation is off.
    Item {
      id: marquee
      anchors.fill: parent
      clip: true
      visible: root.hasEntries

      readonly property color fg: root.bar ? root.bar.barForeground : Color.foreground
      readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      readonly property real gap: 56
      readonly property real copyWidth: seg1.implicitWidth + gap
      // Always run the left-to-right scroll whenever there are countdowns, so
      // the widget reads as a live ticker instead of parking centred when the
      // text happens to fit. Restore `seg1.implicitWidth > marquee.width` here
      // to only scroll on overflow.
      readonly property bool scrolling: root.hasEntries && seg1.implicitWidth > 0 && marquee.width > 0

      Row {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        spacing: marquee.gap

        Text {
          id: seg1
          text: "  " + root.marqueeContent
          color: marquee.fg
          font.family: marquee.fontFamily
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
          verticalAlignment: Text.AlignVCenter
        }
        Text {
          id: seg2
          visible: marquee.scrolling
          text: seg1.text
          color: marquee.fg
          font.family: marquee.fontFamily
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
          verticalAlignment: Text.AlignVCenter
        }
      }

      // Parked position when it fits (animation is not running then).
      Binding {
        target: track
        property: "x"
        value: Math.max(0, (marquee.width - seg1.implicitWidth) / 2)
        when: !marquee.scrolling
      }

      // ~45 px/sec, min 4s per lap, restarts cleanly when the content width
      // changes (a day rolled over, or an entry was added/removed).
      NumberAnimation {
        id: scrollAnim
        target: track
        property: "x"
        running: marquee.visible && marquee.scrolling
        from: -marquee.copyWidth
        to: 0
        duration: Math.max(4000, Math.round(marquee.copyWidth * 22))
        loops: Animation.Infinite
        easing.type: Easing.Linear
      }
    }
  }
}
