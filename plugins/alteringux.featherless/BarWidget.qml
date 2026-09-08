import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

BarWidget {
  id: root
  moduleName: "alteringux.featherless"

  readonly property var guard: Kit.BugGuard.create("alteringux.featherless", function(argv) { Quickshell.execDetached(argv) })

  readonly property string home: Quickshell.env("HOME")
  readonly property string collectorScript: home + "/.local/bin/omarchy-featherless-usage"

  Kit.Store {
    id: stateStore
    fileName: "featherless-usage.json"
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

  readonly property string barText: {
    if (!root.ready) return "\uf0d0  —"
    return "\uf0d0  " + Model.formatTokens(root.todayTokens)
  }

  readonly property color barColor: {
    if (!root.ready) return Kit.Palette.faint
    return root.bar ? Color.bar.text : Color.foreground
  }

  Process {
    id: refreshProc
    running: false
    onRunningChanged: root.refreshing = running
    onExited: stateStore.reload()
  }

  function runRefresh() {
    if (refreshProc.running) return
    refreshProc.command = ["bash", root.collectorScript]
    refreshProc.running = true
  }

  Component.onCompleted: root.runRefresh()

  readonly property int refreshIntervalMs: Math.max(60, setting("refreshSeconds", 300)) * 1000

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
    target: "alteringux.featherless"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.runRefresh() }
    function status(): string {
      return guard.call("ipc.status", function() {
        return JSON.stringify({
          ready: root.ready,
          refreshing: root.refreshing,
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
    tooltipText: root.ready
      ? ("Featherless — " + Model.formatTokens(root.todayTokens) + " tokens today, " + Model.formatCost(root.todayCost))
      : "Featherless — loading usage data"

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