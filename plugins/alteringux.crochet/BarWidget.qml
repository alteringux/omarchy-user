import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

BarWidget {
  id: root
  moduleName: "alteringux.crochet"

  property alias index: indexStore.value
  readonly property bool indexLoaded: indexStore.loaded

  readonly property var guard: Kit.BugGuard.create("alteringux.crochet", function(argv) { Quickshell.execDetached(argv) })

  readonly property var lastRun: (indexLoaded && root.index) ? root.index.lastRun : null
  readonly property var tests: (indexLoaded && root.index) ? root.index.tests : null
  readonly property bool needsAttention: (root.lastRun && root.lastRun.ok === false) || (root.tests && root.tests.ok === false)

  readonly property string glyph: "🧶" // yarn emoji (U+1F9F6), matches the published preview's favicon
  readonly property string displayText: glyph

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-crochet"

  // crochet-index.json is written only by omarchy-crochet (see the plugin's
  // manifest description; follows the same CLI-first shape as devcast/
  // pomodoro per docs/adr/0006-cli-first-plugins.md).
  Kit.Store {
    id: indexStore
    fileName: "crochet-index.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseIndex(raw) }
  }

  // ---- pattern list (scanned on demand, not watched)
  property var patterns: []
  property bool scanning: false

  Process {
    id: listProc
    running: false
    property var listBuf: []
    stdout: SplitParser {
      onRead: function (line) { listProc.listBuf.push(line) }
    }
    onRunningChanged: {
      if (running) listProc.listBuf = []
    }
    onExited: {
      root.scanning = false
      root.patterns = Model.parsePatternList(listProc.listBuf.join("\n"))
    }
  }

  function refreshPatterns() {
    guard.run("refreshPatterns", function () {
      if (listProc.running) return
      root.scanning = true
      listProc.command = [root.scriptPath, "list"]
      listProc.running = true
    })
  }

  // ---- run / test
  property bool running: false
  property bool testing: false

  Process {
    id: runProc
    running: false
    onExited: { root.running = false; indexStore.reload() }
  }
  Process {
    id: testProc
    running: false
    onExited: { root.testing = false; indexStore.reload() }
  }

  function runPattern(name) {
    guard.run("runPattern", function () {
      if (runProc.running || !name) return
      root.running = true
      runProc.command = [root.scriptPath, "run", name]
      runProc.running = true
    })
  }

  function runTests() {
    guard.run("runTests", function () {
      if (testProc.running) return
      root.testing = true
      testProc.command = [root.scriptPath, "test"]
      testProc.running = true
    })
  }

  function openProject() { guard.run("openProject", function () { Quickshell.execDetached([root.scriptPath, "open", "project"]) }) }
  function openPreview() { guard.run("openPreview", function () { Quickshell.execDetached([root.scriptPath, "open", "preview"]) }) }
  function openDoc()     { guard.run("openDoc", function () { Quickshell.execDetached([root.scriptPath, "open", "doc"]) }) }
  function openLast()    { guard.run("openLast", function () { Quickshell.execDetached([root.scriptPath, "open", "last"]) }) }

  // ---- IPC
  IpcHandler {
    target: "alteringux.crochet"

    function status(): string {
      return guard.call("ipc.status", function () {
        return JSON.stringify({
          lastRun: root.lastRun,
          tests: root.tests,
          patterns: root.patterns,
          running: root.running,
          testing: root.testing
        })
      }, "{}")
    }
    function run(pattern: string): void { root.runPattern(pattern) }
    function test(): void { root.runTests() }
    // `patterns` in status() only reflects the last on-demand scan (only
    // triggered by opening the panel) — this lets a script force a rescan
    // without going through the UI first.
    function scan(): void { root.refreshPatterns() }
    function openPreview(): void { root.openPreview() }
    function openProject(): void { root.openProject() }
    function openDoc(): void { root.openDoc() }
    function panel(): void { root.togglePanel() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // ---- popup panel
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
    root.refreshPatterns()
  }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (root.opened) root.close(); else root.open() }

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
      if (b === Qt.MiddleButton) root.openPreview()
      else root.togglePanel()
    }

    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 2
      active: root.needsAttention
      level: "warning"
    }
  }
}
