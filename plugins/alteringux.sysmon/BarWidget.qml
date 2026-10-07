import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

BarWidget {
  id: root
  moduleName: "alteringux.sysmon"

  property alias state: stateStore.value
  readonly property bool stateLoaded: stateStore.loaded

  readonly property var guard: Kit.BugGuard.create("alteringux.sysmon", function(argv) { Quickshell.execDetached(argv) })

  readonly property var stat: stateLoaded ? root.state : Model.defaultState()
  // Date.now() is not a reactive QML dependency. Tick a local clock so a
  // stopped sampler is visibly marked stale as the sample ages.
  property double clockMs: Date.now()

  readonly property string cpuGlyph: "\udb81\ude1a"   // nf-fae-chip (cpu)
  readonly property string memGlyph: "\udb80\udf5b"   // nf-md-memory
  readonly property string tempGlyph: "\udb81\udd0f"  // nf-md-thermometer

  readonly property string displayText: {
    if (!stateLoaded) return root.cpuGlyph + " …"
    var parts = [root.cpuGlyph + " " + Model.formatPct(root.stat.cpu.pct), root.memGlyph + " " + Model.formatPct(root.stat.memory.pct)]
    if (root.stat.temp !== null && root.stat.temp !== undefined)
      parts.push(root.tempGlyph + " " + Model.formatTemp(root.stat.temp))
    return parts.join("  ")
  }

  readonly property bool cpuHot: Model.pctLevel(stat.cpu.pct) !== "normal"
  readonly property bool memHot: Model.pctLevel(stat.memory.pct) !== "normal"
  readonly property bool tempHot: Model.tempLevel(stat.temp) !== "normal"
  readonly property bool anyCritical: Model.pctLevel(stat.cpu.pct) === "critical"
    || Model.pctLevel(stat.memory.pct) === "critical"
    || Model.tempLevel(stat.temp) === "critical"
  readonly property bool anyWarning: (cpuHot || memHot || tempHot) && !anyCritical

  // Model.isStale marks a sample stale after three missed sampler ticks.
  // The reactive clock makes this update even when the sampler is hung.
  readonly property bool stale: stateLoaded && Model.isStale(root.stat, root.clockMs, root.sampleIntervalMs * 3)

  readonly property string tooltipText: stateLoaded
    ? "CPU " + Model.formatPct(root.stat.cpu.pct)
      + "  ·  MEM " + Model.formatPct(root.stat.memory.pct)
      + (root.stat.temp !== null ? "  ·  " + Model.formatTemp(root.stat.temp) : "")
      + (root.stale ? "  ·  stale" : "")
    : "Loading…"

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-sysmon"

  // ---- persistence: sysmon-state.json is written only by omarchy-sysmon
  //      (docs/adr/0006-cli-first-plugins.md). Watch mode re-reads on change;
  //      the idle poll covers FileView's watch-on-create blind spot.
  Kit.Store {
    id: stateStore
    fileName: "sysmon-state.json"
    watch: true
    pollMs: 2000
    parse: function (raw) { return Model.parseState(raw) }
  }

  // ---- the sampler. No systemd timer — this data is only meaningful while
  //      the shell is running to show it, unlike netwatch's accruing buckets.
  readonly property int sampleIntervalMs: 2000

  Process { id: sampleProc; running: false; onExited: stateStore.reload() }

  function sampleNow() {
    guard.run("sampleNow", function () {
      // A busy sampleProc used to make this a silent no-op. If the CLI ever
      // hung, or just overran one 2s tick, every future tick and every
      // middle-click sample request dropped forever, with the bar frozen on
      // whatever it last read. netwatch already fires a detached one-off in
      // that case, since the write to sysmon-state.json is the point, not
      // this Process's own exit. Mirror it here.
      if (sampleProc.running) { Quickshell.execDetached([root.scriptPath, "sample"]); return }
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

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.clockMs = Date.now()
  }

  // ---- IPC
  IpcHandler {
    target: "alteringux.sysmon"

    function status(): string {
      return guard.call("ipc.status", function () {
        // Copy rather than mutate root.stat. When stateLoaded it *is*
        // stateStore.value, and stamping a field onto it in place would leak
        // into the Kit.Store-held object.
        var out = {}
        var s = root.stat || {}
        for (var k in s) out[k] = s[k]
        out.stale = root.stale
        return JSON.stringify(out)
      }, "{}")
    }
    function sample(): void { root.sampleNow() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // ---- popup panel
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
    active: root.anyWarning || root.anyCritical
    activeColor: root.anyCritical ? Kit.Palette.negative : Kit.Palette.warning
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
      active: root.anyWarning || root.anyCritical
      level: root.anyCritical ? "critical" : "warning"
    }
  }
}
