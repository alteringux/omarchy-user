import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui as ShellUi
import "PanelFocus.js" as Focus

// The shell briefly primes compositor focus on open. Its initial target can
// lose focus during that transition; restore the caller's declared target once
// priming finishes. Subsequent user navigation and refreshes keep their focus.
ShellUi.KeyboardPanel {
  id: root
  gap: Style.gapsOut + (bar && "popupExtraGap" in bar ? bar.popupExtraGap : 0)
  function focusOwner() {
    let item = root.focusTarget
    while (item) {
      if (typeof item.initialFocusHandled === "boolean") return item
      item = item.parent
    }
    return null
  }
  function focusInitialTarget() {
    const owner = focusOwner()
    const window = root.focusTarget ? root.focusTarget.Window.window : null
    if (Focus.shouldRestore(root.open, root.focusPrimed, root.focusTarget,
        window ? window.activeFocusItem : null, owner && owner.initialFocusHandled))
      root.focusTarget.forceActiveFocus()
  }
  onOpenChanged: if (root.open) {
    const owner = focusOwner()
    if (owner) owner.initialFocusHandled = false
  }
  onFocusPrimedChanged: if (root.open && root.focusPrimed)
    Qt.callLater(root.focusInitialTarget)
}
