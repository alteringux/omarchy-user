import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

BarWidget {
  id: root
  moduleName: "alteringux.netwatch"

  property alias config: configStore.value
  property alias state: stateStore.value
  readonly property bool configLoaded: configStore.loaded
  readonly property bool stateLoaded: stateStore.loaded

  readonly property var guard: Kit.BugGuard.create("alteringux.netwatch", function(argv) { Quickshell.execDetached(argv) })

  // The whole read-side projection, recomputed whenever the watched state file
  // changes. Model.status is pure JS and tolerates the parsed object directly.
  readonly property var stat: stateLoaded
    ? Model.status(root.state, root.config || {}, Date.now())
    : null

  readonly property string glyph: "" // nf-fa-exchange — up/down traffic
  readonly property string displayText: stat
    ? glyph + "  " + stat.label
    : glyph + "  …"

  readonly property bool quotaWarn: !!(stat && stat.quota && stat.quota.enabled && stat.quota.pct >= 80)
  readonly property bool quotaCrit: !!(stat && stat.quota && stat.quota.enabled && stat.quota.pct >= 100)

  // Model.status already computes staleness (the "— " prefix on the compact
  // label), but nothing surfaced it beyond that one glyph. The sysmon-family
  // widgets dim + tooltip on stale; mirror that here instead of leaving
  // netwatch as the one widget with no visible "this reading is old" state.
  readonly property string tooltipText: stat
    ? "NET " + stat.iface + (stat.up ? "" : " (down)")
      + "  ·  ↓" + Model.formatRate(stat.rxRate) + " ↑" + Model.formatRate(stat.txRate)
      + (stat.quota.enabled ? "  ·  quota " + Math.round(stat.quota.pct) + "%" : "")
      + (stat.stale ? "  ·  stale" : "")
    : "Loading…"

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-netwatch"

  // ---- persistence: both files are written only by omarchy-netwatch
  //      (docs/adr/0006-cli-first-plugins.md). Watch mode re-reads on change;
  //      the idle poll covers FileView's watch-on-create blind spot.
  Kit.Store {
    id: configStore
    fileName: "netwatch-config.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseConfig(raw) }
  }

  Kit.Store {
    id: stateStore
    fileName: "netwatch-state.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseState(raw) }
  }

  // ---- the sampler. The shipped systemd timer keeps buckets accruing when the
  //      shell isn't running; this keeps the live rate fresh while it is.
  readonly property int sampleIntervalMs: Model.sampleIntervalMs(root.config || {})

  Process { id: sampleProc; running: false; onExited: stateStore.reload() }

  function sampleNow() {
    guard.run("sampleNow", function () {
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

  // ---- IPC
  IpcHandler {
    target: "alteringux.netwatch"

    function status(): string {
      return guard.call("ipc.status", function () {
        return JSON.stringify(root.stat || {})
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
    dimmed: !!(stat && stat.stale)
    active: root.quotaWarn
    activeColor: root.quotaCrit ? Kit.Palette.negative : Kit.Palette.warning
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
      active: root.quotaWarn
      level: root.quotaCrit ? "critical" : "warning"
    }
  }
}
