import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Disk-usage slice of the system-monitor family (sole writer:
// ~/.local/bin/omarchy-diskmon, docs/adr/0006). A thin view: Kit.Store
// watches diskmon-state.json; this widget's own Timer ticks the sampler,
// same shape as cpumon/memmon/tempmon.
BarWidget {
  id: root
  moduleName: "alteringux.diskmon"

  property alias state: stateStore.value
  readonly property bool stateLoaded: stateStore.loaded

  readonly property var guard: Kit.BugGuard.create("alteringux.diskmon", function (argv) { Quickshell.execDetached(argv) })

  readonly property var stat: stateLoaded ? root.state : Model.defaultState()
  readonly property string glyph: "" // nf-fa-hdd_o

  readonly property string displayText: stateLoaded
    ? glyph + "  " + Model.formatPct(root.stat.primary.pct)
    : glyph + "  …"

  readonly property string level: root.stat.primary.level
  readonly property bool warn: level === "warning"
  readonly property bool crit: level === "critical"

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-diskmon"
  // Disk usage moves slowly; sampling every 30s is plenty and keeps df calls
  // (and the resulting flash-storage wear) low compared to cpumon's 2s.
  readonly property int sampleIntervalMs: 30000

  Kit.Store {
    id: stateStore
    fileName: "diskmon-state.json"
    watch: true
    pollMs: 5000
    parse: function (raw) { return Model.parseState(raw) }
  }

  Process { id: sampleProc; running: false; onExited: stateStore.reload() }

  function sampleNow() {
    guard.run("sampleNow", function () {
      if (sampleProc.running) return
      sampleProc.command = [root.scriptPath, "sample"]
      sampleProc.running = true
    })
  }

  Timer {
    interval: root.sampleIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sampleNow()
  }

  IpcHandler {
    target: "alteringux.diskmon"

    function status(): string {
      return guard.call("ipc.status", function () {
        return JSON.stringify(root.stat && root.stat.primary ? root.stat.primary : {})
      }, "{}")
    }
    function sample(): void { root.sampleNow() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

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
    text: root.displayText
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function (b) {
      if (b === Qt.MiddleButton) root.sampleNow()
      else root.togglePanel()
    }

    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 2
      active: root.warn || root.crit
      level: root.crit ? "critical" : "warning"
    }
  }
}
