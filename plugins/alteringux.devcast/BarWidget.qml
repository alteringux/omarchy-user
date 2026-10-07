import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

BarWidget {
  id: root
  moduleName: "alteringux.devcast"

  property alias index: indexStore.value
  readonly property bool indexLoaded: indexStore.loaded

  readonly property var guard: Kit.BugGuard.create("alteringux.devcast", function(argv) { Quickshell.execDetached(argv) })

  readonly property int castCount: (indexLoaded && root.index) ? (root.index.count || 0) : 0
  readonly property var latest: (indexLoaded && root.index) ? root.index.latest : null

  readonly property string glyph: "󰿎" // nf-md-movie_open
  readonly property string displayText: castCount > 0 ? (glyph + "  " + castCount) : glyph

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-devcast"

  // devcast-index.json is written only by omarchy-devcast (docs/adr/0006).
  Kit.Store {
    id: indexStore
    fileName: "devcast-index.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseIndex(raw) }
  }

  // ---- building state (also surfaced to the panel)
  property bool building: false

  // build/catalog/import all used a bare `onExited: { ... }` handler with no
  // exit-code parameter and no captured stderr — a failure (no active
  // session, a stale `--project` path, jq missing, the projects dir being
  // unreadable) reset the busy flag and reloaded the same index with no
  // trace anywhere that anything went wrong. `lastError` plus each Process's
  // StdioCollector fixes that; a fresh attempt clears it immediately so a
  // stale error can't linger over a later success.
  property string lastError: ""

  Process {
    id: buildProc
    running: false
    stderr: StdioCollector { id: buildErr; waitForEnd: true }
    onExited: function (code) {
      root.building = false
      root.lastError = code === 0 ? "" : ("Build failed: " + root.tail(buildErr.text, "exit " + code))
      indexStore.reload()
    }
  }

  function buildLatest(open) {
    guard.run("buildLatest", function () {
      if (buildProc.running) return
      root.lastError = ""
      root.building = true
      buildProc.command = open
        ? [root.scriptPath, "build", "latest", "--open"]
        : [root.scriptPath, "build", "latest"]
      buildProc.running = true
    })
  }

  function openLatest() {
    guard.run("openLatest", function () {
      Quickshell.execDetached([root.scriptPath, "open"])
    })
  }

  // Last non-blank line of a captured stderr stream, or `fallback` if there
  // wasn't one — short enough to fit a one-line panel message.
  function tail(text, fallback) {
    var lines = String(text || "").split("\n").map(function (l) { return l.trim() }).filter(Boolean)
    return lines.length ? lines[lines.length - 1] : fallback
  }

  // ---- session catalogue ("all sessions + history")
  readonly property var catalog: (indexLoaded && root.index && root.index.catalog) ? root.index.catalog : null
  property bool scanning: false
  property bool importing: false

  Process {
    id: catalogProc
    running: false
    stderr: StdioCollector { id: catalogErr; waitForEnd: true }
    onExited: function (code) {
      root.scanning = false
      root.lastError = code === 0 ? "" : ("Rescan failed: " + root.tail(catalogErr.text, "exit " + code))
      indexStore.reload()
    }
  }
  Process {
    id: importProc
    running: false
    stderr: StdioCollector { id: importErr; waitForEnd: true }
    onExited: function (code) {
      root.importing = false
      root.lastError = code === 0 ? "" : ("Import failed: " + root.tail(importErr.text, "exit " + code))
      indexStore.reload()
    }
  }

  function refreshCatalog() {
    guard.run("refreshCatalog", function () {
      if (catalogProc.running) return
      root.lastError = ""
      root.scanning = true
      catalogProc.command = [root.scriptPath, "catalog"]
      catalogProc.running = true
    })
  }

  function importRecent() {
    guard.run("importRecent", function () {
      if (importProc.running) return
      root.lastError = ""
      root.importing = true
      importProc.command = [root.scriptPath, "import"]
      importProc.running = true
    })
  }

  function buildSession(sourcePath, open) {
    guard.run("buildSession", function () {
      if (buildProc.running || !sourcePath) return
      root.lastError = ""
      root.building = true
      buildProc.command = open
        ? [root.scriptPath, "build", sourcePath, "--open"]
        : [root.scriptPath, "build", sourcePath]
      buildProc.running = true
    })
  }

  // ---- IPC
  IpcHandler {
    target: "alteringux.devcast"

    function status(): string {
      return guard.call("ipc.status", function () {
        return JSON.stringify({
          count: root.castCount,
          building: root.building,
          scanning: root.scanning,
          importing: root.importing,
          latest: root.latest,
          catalog: root.catalog,
          lastError: root.lastError
        })
      }, "{}")
    }
    function build(): void { root.buildLatest(false) }
    function buildOpen(): void { root.buildLatest(true) }
    function open(): void { root.openLatest() }
    function catalog(): void { root.refreshCatalog() }
    function importSessions(): void { root.importRecent() }
    function panel(): void { root.togglePanel() }
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
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function (b) {
      if (b === Qt.MiddleButton) root.buildLatest(true)
      else root.togglePanel()
    }

    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 2
      active: root.building
      level: "info"
    }
  }
}
