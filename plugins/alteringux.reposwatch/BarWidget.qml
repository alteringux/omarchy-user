import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Git working-tree status across a watched list of repos (sole writer:
// ~/.local/bin/omarchy-reposwatch, docs/adr/0006). A thin view: Kit.Store
// watches reposwatch-state.json; this widget's own Timer ticks the scanner.
BarWidget {
  id: root
  moduleName: "alteringux.reposwatch"

  property alias state: stateStore.value
  readonly property bool stateLoaded: stateStore.loaded

  readonly property var guard: Kit.BugGuard.create("alteringux.reposwatch", function (argv) { Quickshell.execDetached(argv) })

  readonly property var stat: stateLoaded ? root.state : Model.defaultState()
  readonly property string glyph: "" // nf-oct-git_branch

  readonly property string displayText: stateLoaded
    ? glyph + "  " + Model.barLabel(root.stat)
    : glyph + "  …"

  readonly property string level: Model.overallLevel(root.stat)
  readonly property bool warn: level === "warning"
  readonly property bool crit: level === "critical"

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-reposwatch"
  // git status across a handful of repos is cheap but not free; a repo's
  // dirty state also doesn't change every couple seconds the way CPU% does.
  readonly property int scanIntervalMs: 60000

  Kit.Store {
    id: stateStore
    fileName: "reposwatch-state.json"
    watch: true
    pollMs: 5000
    parse: function (raw) { return Model.parseState(raw) }
  }

  Process { id: scanProc; running: false; onExited: stateStore.reload() }

  function scanNow() {
    guard.run("scanNow", function () {
      if (scanProc.running) return
      scanProc.command = [root.scriptPath, "scan"]
      scanProc.running = true
    })
  }

  Timer {
    interval: root.scanIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.scanNow()
  }

  IpcHandler {
    target: "alteringux.reposwatch"

    function status(): string {
      return guard.call("ipc.status", function () {
        return JSON.stringify(root.stat && root.stat.totals ? root.stat.totals : {})
      }, "{}")
    }
    function scan(): void { root.scanNow() }
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
      if (b === Qt.MiddleButton) root.scanNow()
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
