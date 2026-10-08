import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "../alteringux.kit" as Kit

// Bottom Bar service: a persistent layer-shell strip on the bottom edge of
// every monitor (same PanelWindow contract as alteringux.newsbar — themed,
// per-screen, reserves space with an exclusion zone). Its job is to host bar
// widgets the top bar has run out of horizontal room for.
//
// It loads the real BarWidget.qml of each hosted plugin straight from that
// plugin's own directory and hands it a BarShim in place of the shell's Bar.
// The widget's label, wheel/click handlers, IpcHandler and its KeyboardPanel
// popup all work unchanged — the popup is its own Overlay-layer surface that
// positions itself off `bar.position` ("bottom" here).
//
// Because these widgets are instantiated HERE, they must NOT also appear in
// shell.json's top-bar layout, or their IpcHandlers double-register.
Item {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  // Injected by the omarchy-shell host for service plugins.
  property string omarchyPath: ""
  property var shell: null
  property var pluginRegistry: null

  readonly property string home: Quickshell.env("HOME")
  readonly property int barSize: Math.max(20, Style.bar.sizeHorizontal)
  readonly property real surfaceWidth: Quickshell.screens.length ? Quickshell.screens[0].width : 2048
  readonly property real surfaceHeight: Quickshell.screens.length ? Quickshell.screens[0].height : 1280

  // Hosted widgets. The candidate arrays preserve the bar's intentional
  // left/right order; the registry-backed properties below decide which
  // candidates are actually instantiated.
  //
  // `src` is resolved from each manifest rather than trusted from this
  // service's static list. That keeps loading in the plugin's own directory
  // (so relative imports still work) while rejecting removed or unregistered
  // plugins.
  readonly property var leftCandidates: [
    { id: "alteringux.pomodoro" },
    { id: "alteringux.stopwatch" },
    { id: "alteringux.timers" },
    { id: "alteringux.grip" },
    { id: "alteringux.countdown" },
    { id: "alteringux.devcast" },
    { id: "alteringux.pulse" },
    { id: "alteringux.reposwatch" },
    { id: "alteringux.nanogpt" },
    { id: "alteringux.recall" }
  ]
  readonly property var rightCandidates: [
    { id: "alteringux.score" },
    { id: "alteringux.conductor" },
    { id: "alteringux.phone" },
    { id: "alteringux.deskpet" },
    { id: "alteringux.glimpse" }
  ]
  readonly property var overflowCandidates: [
    { id: "alteringux.flow" },
    { id: "alteringux.cliamp" },
    { id: "alteringux.stocks" },
    { id: "alteringux.sports" },
    { id: "alteringux.breathe" },
    { id: "alteringux.ttsplayer" }
  ]
  readonly property var sideLeftCandidates: [
    { id: "omarchy.menu" },
    { id: "alteringux.dashboard" }
  ]
  readonly property var sideRightCandidates: [
    { id: "alteringux.skilldashboard" },
    { id: "io.github.kristoferlund.webcam" }
  ]

  function enabledSpecs(candidates, section) {
    var registry = root.pluginRegistry
    // The revision is a binding dependency: a rescan/config mutation can
    // change installedPlugins or enabled state without replacing the object.
    var registryRevision = registry ? registry.registryRevision : -1
    if (registryRevision < 0 || !registry || !registry.installedPlugins
        || typeof registry.isEnabled !== "function"
        || typeof registry.entryPointUrl !== "function") return []

    var result = []
    var seen = ({})
    for (var i = 0; i < candidates.length; i++) {
      var candidate = candidates[i]
      var id = String(candidate.id || "")
      if (!id || seen[id]) continue
      seen[id] = true

      var manifest = registry.installedPlugins[id]
      if (!manifest || !registry.isEnabled(id)) continue
      // A widget already present in the top-bar layout owns its one shell
      // instance there; hosting it again would duplicate its IPC handlers.
      if (typeof registry.inBar === "function" && registry.inBar(id)) continue

      var src = registry.entryPointUrl(manifest, "barWidget")
      if (!src) continue
      result.push({ id: id, src: src, section: section })
    }
    return result
  }

  readonly property var leftSpecs: root.enabledSpecs(root.leftCandidates, "left")
  readonly property var rightSpecs: root.enabledSpecs(root.rightCandidates, "right")
  readonly property var overflowSpecs: root.enabledSpecs(root.overflowCandidates, "overflow")
  readonly property var sideLeftSpecs: root.enabledSpecs(root.sideLeftCandidates, "side-left")
  readonly property var sideRightSpecs: root.enabledSpecs(root.sideRightCandidates, "side-right")
  // Placement rule: vertical rails are reserved for click-only icon affordances.
  // Text and changing values stay readable on the horizontal bar.
  readonly property var widgetSpecs: root.leftSpecs.concat(root.rightSpecs, root.overflowSpecs,
                                                           root.sideLeftSpecs, root.sideRightSpecs)

  // Keep the edge rows useful at ordinary laptop widths. Long labels still
  // open their existing popups; the slot only bounds their inline preview.
  // ponytail: fixed caps are the smallest safe seam until the bar gains a
  // first-class overflow menu.
  readonly property var inlineWidthCaps: ({
    "alteringux.flow": 170,
    "alteringux.cliamp": 130,
    "alteringux.countdown": 190,
    "alteringux.stocks": 140,
    "alteringux.sports": 190,
    "alteringux.breathe": 90
  })

  readonly property var overflowWidthCaps: ({
    "alteringux.flow": 282,
    "alteringux.cliamp": 178,
    "alteringux.countdown": 300,
    "alteringux.stocks": 192,
    "alteringux.sports": 499,
    "alteringux.breathe": 122,
    "alteringux.ttsplayer": 160
  })

  function inlineWidth(id, natural) {
    var width = Math.max(0, Number(natural) || 0)
    var cap = root.inlineWidthCaps[id]
    return cap === undefined ? width : Math.min(width, cap)
  }

  function slotNaturalWidth(slot) {
    return slot.failed
      ? Style.space(20)
      : Math.max(0, Number(slot.hostItem ? slot.hostItem.implicitWidth : 0) || 0)
  }

  function slotWidth(slot) {
    var natural = root.slotNaturalWidth(slot)
    if (String(slot.modelData.section) === "overflow") {
      var fixed = root.overflowWidthCaps[slot.modelData.id]
      return fixed === undefined ? Math.max(80, natural) : Math.min(fixed, natural)
    }
    return root.inlineWidth(slot.modelData.id, natural)
  }

  function naturalInlineTotal() {
    var total = 0
    for (var id in root.widgetSlots) {
      var slot = root.widgetSlots[id]
      if (!slot || !slot.ownsHostedWidgets || !slot.visible) continue
      if (String(slot.modelData.section) !== "left" && String(slot.modelData.section) !== "right") continue
      total += root.slotWidth(slot)
    }
    return total
  }

  function inlineScale(surfaceWidth) {
    var available = Math.max(1, Number(surfaceWidth) - Style.space(16))
    var total = root.naturalInlineTotal()
    return total > available ? available / total : 1
  }

  function overflowTotal() {
    var total = 0
    for (var id in root.widgetSlots) {
      var slot = root.widgetSlots[id]
      if (!slot || !slot.ownsHostedWidgets || !slot.visible
          || String(slot.modelData.section) !== "overflow") continue
      total += root.slotWidth(slot)
    }
    return total
  }

  function overflowScale(surfaceWidth) {
    var available = Math.max(1, Number(surfaceWidth) - Style.space(16))
    var total = root.overflowTotal()
    return total > available ? available / total : 1
  }

  function layoutBudget(surfaceWidth) {
    var width = Math.max(1, Number(surfaceWidth) || 1)
    var scale = root.inlineScale(width)
    var left = 0
    var right = 0
    for (var id in root.widgetSlots) {
      var slot = root.widgetSlots[id]
      if (!slot || !slot.ownsHostedWidgets || !slot.visible) continue
      if (String(slot.modelData.section) !== "left" && String(slot.modelData.section) !== "right") continue
      var compact = Math.floor(root.slotWidth(slot) * scale)
      if (String(slot.modelData.section) === "left") left += compact
      else right += compact
    }
    var available = Math.max(1, width - Style.space(16))
    var overflow = Math.floor(root.overflowTotal() * root.overflowScale(width))
    return { width: width, available: available, scale: scale,
      left: left, right: right, total: left + right,
      overflow: overflow, overflowScale: root.overflowScale(width),
      fits: left + right <= available && overflow <= available }
  }

  property var widgetStates: ({})
  property var widgetSlots: ({})

  function noteWidget(id, loaded) {
    var next = {}
    for (var k in root.widgetStates) next[k] = root.widgetStates[k]
    next[id] = loaded
    root.widgetStates = next
  }

  function noteWidgetSlot(id, slot) {
    var next = {}
    for (var key in root.widgetSlots) next[key] = root.widgetSlots[key]
    next[id] = slot
    root.widgetSlots = next
  }

  function forgetWidgetSlot(id, slot) {
    if (root.widgetSlots[id] !== slot) return
    var next = {}
    for (var key in root.widgetSlots) {
      if (key !== id) next[key] = root.widgetSlots[key]
    }
    root.widgetSlots = next
  }

  function debugGeometry() {
    var out = []
    for (var id in root.widgetSlots) {
      var slot = root.widgetSlots[id]
      if (!slot || !slot.ownsHostedWidgets || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      var point = { x: slot.x, y: slot.y }
      try { point = slot.mapToItem(null, 0, 0) } catch (e) {}
      var section = String(slot.modelData.section || "")
      var leftWidth = leftSideBar.expanded ? leftSideBar.expandedWidth : leftSideBar.sideWidth
      var rightWidth = rightSideBar.expanded ? rightSideBar.expandedWidth : rightSideBar.sideWidth
      if (section === "side-right") point.x += root.surfaceWidth - rightWidth
      else if (section !== "side-left") point.x += leftWidth
      point.y += section === "left" || section === "right"
        ? root.surfaceHeight - root.barSize * 2 : root.barSize
      out.push({
        id: id,
        section: section,
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: true,
        itemVisible: !!slot.hostItem,
        itemWidth: Math.round(slot.hostItem ? slot.hostItem.implicitWidth || 0 : 0),
        itemHeight: Math.round(slot.hostItem ? slot.hostItem.implicitHeight || 0 : 0)
      })
    }
    return out
  }

  readonly property var guard: Kit.BugGuard.create("alteringux.bottombar", function (argv) { Quickshell.execDetached(argv) })

  // ---- hide flags ------------------------------------------------------
  // Presence of a flag file = hidden. We track our own (`bottombar-off`) and
  // the top bar's (`bar-off`, flipped by `omarchy toggle bar`) so hiding the
  // top bar hides this one too. FileView can't watch a not-yet-existing
  // file, so watch the parent toggles directory + a slow re-probe (same
  // caveat the stock Bar.qml and alteringux.newsbar document).
  readonly property string togglesDir: home + "/.local/state/omarchy/toggles"
  readonly property string ownFlagPath: togglesDir + "/bottombar-off"
  readonly property string topBarFlagPath: togglesDir + "/bar-off"
  property bool ownHidden: false
  // Stay hidden until the first probe has read persisted flags; otherwise
  // startup can paint one visible frame before a saved hide choice arrives.
  property bool hiddenProbeReady: false
  property bool topBarHidden: false
  readonly property bool hidden: ownHidden || topBarHidden

  function setHidden(value) {
    var next = value === true
    root.ownHidden = next
    Quickshell.execDetached(["bash", "-c", next
      ? "mkdir -p " + togglesDir + " && touch " + ownFlagPath
      : "rm -f " + ownFlagPath])
  }

  // A recheck request that lands while hiddenProbe is already in flight used
  // to be dropped silently (setting `running = true` on an already-running
  // Process is a no-op), leaving `hidden` stale until the next 10s tick. Track
  // the request instead of the raw flag so nothing gets lost.
  property bool hiddenProbeDirty: false

  function requestHiddenProbe() {
    if (hiddenProbe.running) { root.hiddenProbeDirty = true; return }
    hiddenProbe.running = true
  }

  Process {
    id: hiddenProbe
    running: false
    command: ["bash", "-c",
      "own=no; top=no; " +
      "[[ -f " + root.ownFlagPath + " ]] && own=yes; " +
      "[[ -f " + root.topBarFlagPath + " ]] && top=yes; " +
      "echo \"$own $top\""]
    stdout: SplitParser { onRead: function (line) {
      var p = String(line).trim().split(/\s+/)
      root.ownHidden = p[0] === "yes"
      root.topBarHidden = p[1] === "yes"
      root.hiddenProbeReady = true
    } }
    onExited: {
      if (root.hiddenProbeDirty) {
        root.hiddenProbeDirty = false
        hiddenProbe.running = true
      }
    }
  }

  FileView {
    path: root.togglesDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.requestHiddenProbe()
  }

  Timer {
    interval: 10000
    repeat: true
    running: true
    onTriggered: root.requestHiddenProbe()
  }

  // Probe before the first frame so a persisted hide choice never flashes
  // the bar while the slower periodic check is still pending.
  Component.onCompleted: root.requestHiddenProbe()
  IpcHandler {
    target: "alteringux.bottombar"

    function ping(): string { return "ok" }
    function show(): void { root.setHidden(false) }
    function hide(): void { root.setHidden(true) }
    function toggle(): void { root.setHidden(!root.ownHidden) }
    // Force an immediate re-check of both hide flags instead of waiting up
    // to 10s for the next poll tick — useful right after a script flips
    // bar-off/bottombar-off and wants the change to show without delay.
    function reload(): void { root.requestHiddenProbe() }
    function status(): string {
      return root.guard.call("ipc.status", function () {
        return JSON.stringify({
          hidden: root.hidden,
          ownHidden: root.ownHidden,
          topBarHidden: root.topBarHidden,
          widgets: root.widgetSpecs.map(function (w) {
            var s = root.widgetStates[w.id]
            if (s === true) return w.id
            if (s === false) return w.id + " (failed)"
            return w.id + " (pending)"
          })
        })
      }, "{}")
    }
    function geometry(): string {
      return root.guard.call("ipc.geometry", function () {
        return JSON.stringify(root.debugGeometry())
      }, "[]")
    }
    function budget(): string {
      return root.guard.call("ipc.budget", function () {
        return JSON.stringify({
          current: root.layoutBudget(root.surfaceWidth - leftSideBar.sideWidth - rightSideBar.sideWidth),
          minimum: root.layoutBudget(1280 - leftSideBar.sideWidth - rightSideBar.sideWidth)
        })
      }, "{}")
    }
  }

  // ------------------------------------------------------------- the bar(s)
  Variants {
    // One bottom-bar window per connected monitor, matching the documented
    // every-monitor service behavior. Widget implementations already guard
    // shared polling/refresh work when they are hosted on multiple screens.
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: win
        required property var modelData
        // The surface remains on every monitor, but hosted widgets are
        // singleton shell components: loading them per screen duplicates
        // IpcHandlers, timers, and Kit.Usage writes. Keep ownership on the
        // first connected screen while leaving the other bar surfaces visible.
        readonly property bool ownsHostedWidgets: modelData === Quickshell.screens[0]

        screen: modelData
        visible: root.hiddenProbeReady && !root.hidden
        exclusionMode: ExclusionMode.Auto
        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "alteringux-bottombar"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors { bottom: true; left: true; right: true }
        implicitHeight: root.barSize

        BarShim {
          id: shim
          barSize: root.barSize
        }

        Rectangle {
          anchors.fill: parent
          color: _webPalette.barBackground

          // Hairline along the top edge, echoing the top bar's weight.
          Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1
            color: Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, 0.12)
          }

          // One hosted bar widget. The Loader gives the widget its height
          // (full bar) and takes its width from the widget's own
          // implicitWidth, exactly as a top-bar ModuleSlot would. Shared by
          // both zones — it reads `shim` from this file's scope.
          Component {
            id: widgetSlot

            Item {
              id: slot
              required property var modelData
              readonly property bool ownsHostedWidgets: win.ownsHostedWidgets
              readonly property bool failed: hostLoader.status === Loader.Error
              readonly property var hostItem: hostLoader.item
              height: parent ? parent.height : root.barSize
              // A failed widget used to collapse to a 1px sliver with no
              // visual trace — indistinguishable from "not configured" and
              // only discoverable via the status() IPC call. Give it a
              // small, tappable marker instead so a crashed hosted widget is
              // visible right in the bar.
              width: slot.failed ? errorMark.width : Math.floor(root.slotWidth(slot)
                * (String(slot.modelData.section) === "overflow"
                  ? root.overflowScale(win.width) : root.inlineScale(win.width)))
              clip: true

              Component.onCompleted: root.noteWidgetSlot(slot.modelData.id, slot)
              Component.onDestruction: root.forgetWidgetSlot(slot.modelData.id, slot)

              Loader {
                active: win.ownsHostedWidgets
                id: hostLoader
                anchors.fill: parent
                asynchronous: false
                source: slot.modelData.src

                onLoaded: {
                  if (!item) return
                  if ("bar" in item) item.bar = shim
                  root.noteWidget(slot.modelData.id, true)
                }
                // Loader has no dedicated "load failed" signal — Loader.Error
                // is one of the four Loader.status values, so watch for it
                // via onStatusChanged instead (an onLoadingFailed handler
                // doesn't exist on this type and is a hard QML load-time
                // error).
                onStatusChanged: if (status === Loader.Error) root.noteWidget(slot.modelData.id, false)
              }

              Rectangle {
                id: errorMark
                visible: slot.failed
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(20)
                height: Style.space(20)
                radius: width / 2
                Accessible.role: Accessible.StaticText
                Accessible.name: slot.modelData.id + " failed to load"
                color: "transparent"
                border.width: 1
                border.color: _webPalette.barNegative

                Text {
                  anchors.centerIn: parent
                  text: "!"
                  Accessible.ignored: true
                  color: _webPalette.barNegative
                  font.family: Style.font.family
                  font.bold: true
                  font.pixelSize: Style.space(10)
                }

                ToolTip.visible: errorMarkArea.containsMouse
                ToolTip.text: slot.modelData.id + " failed to load"

                MouseArea {
                  id: errorMarkArea
                  anchors.fill: parent
                  hoverEnabled: true
                }
              }
            }
          }

          // Left zone: pack from the left edge.
          Row {
            id: hostRow
            anchors {
              left: parent.left; bottom: parent.bottom
              leftMargin: Style.space(8)
            }
            height: root.barSize
            spacing: 0

            Repeater {
              model: root.leftSpecs
              delegate: widgetSlot
            }
          }

          // Right zone: pack against the right edge.
          Row {
            id: tailRow
            anchors {
              right: parent.right; bottom: parent.bottom
              rightMargin: Style.space(8)
            }
            height: root.barSize
            spacing: 0

            Repeater {
              model: root.rightSpecs
              delegate: widgetSlot
            }
          }

        }
      }
    }
  }

  OverflowBar {
    barSize: root.barSize
    barVisible: root.hiddenProbeReady && !root.hidden
    specs: root.overflowSpecs
    host: root
    onWidgetLoaded: function(id, loaded) { root.noteWidget(id, loaded) }
    onSlotAdded: function(id, slot) { root.noteWidgetSlot(id, slot) }
    onSlotRemoved: function(id, slot) { root.forgetWidgetSlot(id, slot) }
  }

  SideBar {
    id: leftSideBar
    side: "left"
    barSize: root.barSize
    barVisible: root.hiddenProbeReady && !root.hidden
    pluginRegistry: root.pluginRegistry
    specs: root.sideLeftSpecs
    onWidgetLoaded: function(id, loaded) { root.noteWidget(id, loaded) }
    onSlotAdded: function(id, slot) { root.noteWidgetSlot(id, slot) }
    onSlotRemoved: function(id, slot) { root.forgetWidgetSlot(id, slot) }
  }

  SideBar {
    id: rightSideBar
    side: "right"
    barSize: root.barSize
    barVisible: root.hiddenProbeReady && !root.hidden
    pluginRegistry: root.pluginRegistry
    specs: root.sideRightSpecs
    onWidgetLoaded: function(id, loaded) { root.noteWidget(id, loaded) }
    onSlotAdded: function(id, slot) { root.noteWidgetSlot(id, slot) }
    onSlotRemoved: function(id, slot) { root.forgetWidgetSlot(id, slot) }
  }
}
