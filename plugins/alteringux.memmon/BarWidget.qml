import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../alteringux.sysmon/Model.js" as Model
import "../alteringux.kit" as Kit

// Memory slice of the split system monitor. Reads the shared sysmon-state.json
// (sole writer: ~/.local/bin/omarchy-sysmon, docs/adr/0006). A flock in the CLI
// coalesces the three sysmon widgets' samplers to one /proc read per tick.
BarWidget {
  id: root
  moduleName: "alteringux.memmon"

  property alias state: stateStore.value
  readonly property bool stateLoaded: stateStore.loaded

  readonly property var guard: Kit.BugGuard.create("alteringux.memmon", function (argv) { Quickshell.execDetached(argv) })

  readonly property var stat: stateLoaded ? root.state : Model.defaultState()
  readonly property string glyph: "󰍛" // nf-md-memory

  readonly property string displayText: stateLoaded
    ? glyph + "  " + Model.formatPct(root.stat.memory.pct)
    : glyph + "  …"

  readonly property string level: Model.pctLevel(stat.memory.pct)
  readonly property bool warn: level === "warning"
  readonly property bool crit: level === "critical"

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-sysmon"
  readonly property int sampleIntervalMs: 2000

  Kit.Store {
    id: stateStore
    fileName: "sysmon-state.json"
    watch: true
    pollMs: 2000
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
    target: "alteringux.memmon"

    function status(): string {
      return guard.call("ipc.status", function () {
        return JSON.stringify(root.stat && root.stat.memory ? root.stat.memory : {})
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
