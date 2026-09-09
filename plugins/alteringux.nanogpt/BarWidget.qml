import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

BarWidget {
  id: root
  moduleName: "alteringux.nanogpt"

  readonly property var guard: Kit.BugGuard.create("alteringux.nanogpt", function(argv) { Quickshell.execDetached(argv) })

  readonly property string home: Quickshell.env("HOME")
  readonly property string collectorScript: home + "/.local/bin/omarchy-nanogpt-usage"

  Kit.Store {
    id: stateStore
    fileName: "nanogpt-usage.json"
    watch: true
    pollMs: 5000
    parse: function(raw) { return Model.parseState(raw) }
  }

  property alias state: stateStore.value
  readonly property bool stateLoaded: stateStore.loaded
  property bool refreshing: false

  readonly property bool ready: state.ready === true
  readonly property var plan: state.plan || {}
  readonly property var today: state.today || {}
  readonly property var week: state.week || []
  readonly property var allTime: state.allTime || {}
  readonly property var models: state.models || []
  readonly property var tokenComposition: state.tokenComposition || {}

  readonly property int todayTokens: Number(today.totalTokens || 0)
  readonly property real todayCost: Number(today.estimatedCost || 0)
  readonly property int allTimeTokens: Number(allTime.totalTokens || 0)
  readonly property real allTimeCost: Number(allTime.estimatedCost || 0)

  readonly property bool subActive: plan.active === true
  readonly property real quotaRatio: Model.quotaRatio(plan)

  readonly property string barText: {
    if (!root.ready) return "  —"
    if (root.subActive) return "  " + Model.quotaPctLabel(root.plan)
    if (root.todayCost > 0) return "  " + Model.formatCost(root.todayCost)
    return "  " + Model.formatTokens(root.todayTokens)
  }

  readonly property color barColor: {
    if (!root.ready) return Kit.Palette.faint
    if (root.subActive && root.quotaRatio >= 0.9) return Kit.Palette.negative
    if (root.subActive && root.quotaRatio >= 0.75) return Kit.Palette.warning
    // WidgetButton's own default reads bar.barForeground (the live,
    // transparency-adaptive color every other widget tracks for free) --
    // this widget overrides `foreground` explicitly, so it has to read the
    // same live property itself instead of the static theme constant.
    return root.bar ? root.bar.barForeground : Color.foreground
  }

  Process {
    id: refreshProc
    running: false
    onRunningChanged: root.refreshing = running
    onExited: stateStore.reload()
  }

  function runRefresh() {
    if (refreshProc.running) return
    refreshProc.command = ["python3", root.collectorScript]
    refreshProc.running = true
  }

  Component.onCompleted: root.runRefresh()

  readonly property int refreshIntervalMs: Math.max(60, setting("refreshSeconds", 900)) * 1000

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalMs
    repeat: true
    running: true
    onTriggered: root.runRefresh()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  IpcHandler {
    target: "alteringux.nanogpt"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.runRefresh() }
    function status(): string {
      return guard.call("ipc.status", function() {
        return JSON.stringify({
          ready: root.ready,
          refreshing: root.refreshing,
          subActive: root.subActive,
          quotaRatio: root.quotaRatio,
          todayTokens: root.todayTokens,
          todayCost: root.todayCost,
          allTimeCost: root.allTimeCost,
          plan: root.plan
        })
      }, "{}")
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    foreground: root.barColor
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: {
      if (!root.ready) return "NanoGPT — loading usage data"
      var parts = []
      if (root.subActive) {
        parts.push("weekly quota " + Model.quotaPctLabel(root.plan) + " used")
        var r = Model.formatResetIn(root.plan.resetAt)
        if (r) parts.push(r)
      }
      parts.push(Model.formatTokens(root.todayTokens) + " tokens today")
      if (root.todayCost > 0) parts.push(Model.formatCost(root.todayCost))
      return "NanoGPT — " + parts.join(", ")
    }

    onPressed: function(b) { root.togglePanel() }

    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.spaceReal(3)
      anchors.rightMargin: Style.spaceReal(2)
      active: root.refreshing
      level: "info"
    }
  }
}
