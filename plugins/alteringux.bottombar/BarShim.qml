import QtQuick
import Quickshell
import qs.Commons
import "../alteringux.kit" as Kit

// Minimal stand-in for the omarchy shell's `Bar` object, handed to every
// widget this bottom bar hosts (as `widget.bar`) and, through the widget's
// injectPanel(), to that widget's popup as well.
//
// It implements only the slice of the Bar contract that alteringux.stocks /
// alteringux.score / alteringux.conductor and their KeyboardPanel popups
// actually read:
//
//   geometry / theme  — position, barSize, vertical, fontFamily,
//                        barForeground, foreground, urgent,
//                        foregroundAnimationEnabled
//   tooltips          — showTooltip / hideTooltip  (no-ops; the real bar's
//                        tooltip host is a top-bar surface we don't have)
//   click registry    — registerClickTarget / unregisterClickTarget /
//                        clickTargets / targetBelongsToWindow, used by
//                        KeyboardPanel to forward a click on another widget
//                        in this bar to that widget while a popup is open
//   popout coordinator — activePopout / requestPopout / releasePopout, the
//                        single-open-popup-per-bar model
//
// Deliberately omitted (each caller guards with `typeof … === "function"` or
// a `bar && …` check): switchPanelFrom, moduleWidgets, hideTooltip-on-scroll,
// summon routing. `position: "bottom"` makes KeyboardPanel.cardOrigin place
// popups above this bar instead of below the top one.
QtObject {
  property QtObject _webPalette: Kit.Palette {}
  id: shim

  property string position: "bottom"
  property int barSize: Math.max(20, Style.bar.sizeHorizontal)
  property bool vertical: false
  property int popupExtraGap: 0

  property string fontFamily: Style.font.family
  property color barForeground: _webPalette.barForeground
  property color foreground: _webPalette.barForeground
  property color urgent: _webPalette.barActive
  property bool foregroundAnimationEnabled: false

  // ---- click-target registry (WidgetButton registers itself here) --------
  property var clickTargets: []

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    clickTargets = clickTargets.filter(function (item) { return item !== target })
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && !!target.QsWindow && target.QsWindow.window === window
  }

  // ---- tooltips: no host surface on this bar, so swallow the calls -------
  function showTooltip(item, text) {}
  function hideTooltip(item) {}
  function run(command) { if (command) Quickshell.execDetached(["bash", "-lc", String(command)]) }

  // ---- single-popout-per-bar coordinator --------------------------------
  property var activePopout: null
  function requestPopout(key) { activePopout = key }
  function releasePopout(key) { if (activePopout === key) activePopout = null }
}
