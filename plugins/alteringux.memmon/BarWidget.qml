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
  property QtObject _webPalette: Kit.Palette {}
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
  // Date.now() is not a QML dependency. Keep a small reactive clock so a
  // stalled sampler eventually changes the bar from a live reading to stale.
  property double nowMs: Date.now()

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // Model.isStale is tested (test/model.test.js) but was never wired into any
  // of the three sysmon-family widgets. A hung sampler left the bar showing a
  // confident, silently ageing number. 3 missed ticks is the same "gone
  // quiet" threshold netwatch already uses for its own staleness label.
  readonly property bool stale: stateLoaded && Model.isStale(root.stat, root.nowMs, root.sampleIntervalMs * 3)

  readonly property string tooltipText: stateLoaded
    ? "MEM " + Model.formatGb(root.stat.memory.usedKb) + " / " + Model.formatGb(root.stat.memory.totalKb)
      + (root.stat.swap.totalKb > 0 ? "  ·  swap " + Model.formatPct(root.stat.swap.pct) : "")
      + (root.stale ? "  ·  stale" : "")
    : "Loading…"

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-sysmon"
  readonly property int sampleIntervalMs: 4000
  property string sampleError: ""
  property bool sampleFailureAnnounced: false
  signal sampleFeedback(string message)
  function reportSampleFailure(message) {
    root.sampleError = message
    if (root.sampleFailureAnnounced) return
    root.sampleFailureAnnounced = true
    root.sampleFeedback(message)
  }

  Kit.Store {
    id: stateStore
    fileName: "sysmon-state.json"
    watch: true
    pollMs: 4000
    parse: function (raw) { return Model.parseState(raw) }
  }

  Process {
    id: sampleProc
    property bool started: false
    property bool attempted: false
    running: false
    onStarted: started = true
    onRunningChanged: {
      if (running) { started = false; attempted = true }
      else if (attempted && !started) {
        attempted = false
        root.reportSampleFailure("System sample unavailable. Check ~/.local/bin/omarchy-sysmon.")
      }
    }
    onExited: function(code, status) {
      stateStore.reload()
      started = false
      attempted = false
      if (code === 0 && status === 0) { root.sampleError = ""; root.sampleFailureAnnounced = false }
      else root.reportSampleFailure("System sample failed (exit " + code + ").")
    }
  }

  function sampleNow() {
    guard.run("sampleNow", function () {
      // A busy sampleProc used to make this a silent no-op. If the CLI ever
      // hung, or just overran one 4s tick, every future tick and every
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
    target: "alteringux.memmon"

    function status(): string {
      return guard.call("ipc.status", function () {
        // Copy rather than mutate root.stat.memory. When stateLoaded it is a
        // sub-object of stateStore.value, and stamping a field onto it in
        // place would leak into the Kit.Store-held object.
        var out = {}
        var m = (root.stat && root.stat.memory) ? root.stat.memory : {}
        for (var k in m) out[k] = m[k]
        out.stale = root.stale
        return JSON.stringify(out)
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
    activeColor: root.crit ? _webPalette.barNegative : _webPalette.barWarning
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
