import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../alteringux.sysmon/Model.js" as Model
import "../alteringux.kit" as Kit

// Temperature slice of the split system monitor. Reads the shared
// sysmon-state.json (sole writer: ~/.local/bin/omarchy-sysmon, docs/adr/0006).
// A flock in the CLI coalesces the three samplers to one read per tick.
BarWidget {
  id: root
  moduleName: "alteringux.tempmon"

  property alias state: stateStore.value
  readonly property bool stateLoaded: stateStore.loaded

  readonly property var guard: Kit.BugGuard.create("alteringux.tempmon", function (argv) { Quickshell.execDetached(argv) })

  readonly property var stat: stateLoaded ? root.state : Model.defaultState()
  readonly property bool hasTemp: root.stat.temp !== null && root.stat.temp !== undefined
  readonly property string glyph: "󰔏" // nf-md-thermometer

  readonly property string displayText: !stateLoaded
    ? glyph + "  …"
    : glyph + "  " + Model.formatTemp(root.stat.temp)

  readonly property string level: Model.tempLevel(stat.temp)
  readonly property bool warn: level === "warning"
  readonly property bool crit: level === "critical"

  // Model.isStale is tested (test/model.test.js) but was never wired into any
  // of the three sysmon-family widgets. A hung sampler left the bar showing a
  // confident, silently ageing number. 3 missed ticks is the same "gone
  // quiet" threshold netwatch already uses for its own staleness label.
  readonly property bool stale: stateLoaded && Model.isStale(root.stat, Date.now(), root.sampleIntervalMs * 3)

  readonly property string tooltipText: stateLoaded
    ? (root.hasTemp ? "TEMP " + Model.formatTemp(root.stat.temp) : "No sensor detected")
      + (root.stale ? "  ·  stale" : "")
    : "Loading…"

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-sysmon"
  readonly property int sampleIntervalMs: 4000

  Kit.Store {
    id: stateStore
    fileName: "sysmon-state.json"
    watch: true
    pollMs: 4000
    parse: function (raw) { return Model.parseState(raw) }
  }

  Process { id: sampleProc; running: false; onExited: stateStore.reload() }

  function sampleNow() {
    guard.run("sampleNow", function () {
      // A busy sampleProc used to make this a silent no-op. If the CLI ever
      // hung, or just overran one 2s tick, every future tick and every
      // middle-click sample request dropped forever, with the bar frozen on
      // whatever it last read. netwatch already fires a detached one-off in
      // that case, since the write to sysmon-state.json is the point, not
      // this Process's own exit. Mirror it here.
      // sysmon-state.json is shared by cpumon/memmon/tempmon and by one
      // copy of each PER screen. Coalesce N pollers to one real sample
      // per interval; keep a bounded recovery if the sampler is stuck.
      var updatedAt = Number((root.state && root.state.updatedAt) || 0)
      var age = Date.now() - updatedAt
      if (sampleProc.running) {
        if (age > root.sampleIntervalMs * 4) Quickshell.execDetached([root.scriptPath, "sample"])
        return
      }
      if (age >= 0 && age < root.sampleIntervalMs * 0.75) return
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
    target: "alteringux.tempmon"

    function status(): string {
      return guard.call("ipc.status", function () {
        return JSON.stringify({
          temp: root.stat ? root.stat.temp : null,
          level: root.level,
          stale: root.stale
        })
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
    tooltipText: root.tooltipText
    dimmed: root.stale
    active: root.warn || root.crit
    activeColor: root.crit ? Kit.Palette.negative : Kit.Palette.warning
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
