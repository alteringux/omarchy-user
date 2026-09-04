import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

BarWidget {
  id: root
  moduleName: "alteringux.score"

  property alias config: configStore.value
  property alias state: stateStore.value
  readonly property bool configLoaded: configStore.loaded
  readonly property bool stateLoaded: stateStore.loaded

  readonly property string displayText: stateLoaded
    ? Model.formatScore(state.score, config)
    : "  0"

  readonly property var guard: Kit.BugGuard.create("alteringux.score", function(argv) { Quickshell.execDetached(argv) })

  // Per-plugin usage analytics — records every counter action so status()
  // can report habits and the panel can de-emphasise an unused control.
  Kit.Usage { id: usage; pluginId: "alteringux.score" }

  Kit.PulseTint {
    id: pulseTint
    pluginId: "alteringux.score"
  }

  readonly property bool canUndo: stateLoaded && Model.canUndo(root.state)

  // ---- persistence: two JSON files under ~/.local/state/omarchy/, both now
  // written only by ~/.local/bin/omarchy-score (docs/adr/0006-cli-first-plugins.md).
  // Kit.Store runs in watch mode: it re-reads + re-parses as the CLI rewrites
  // the file, and the `state` / `config` aliases update straight through. The
  // idle poll covers FileView's watch-on-create blind spot.
  Kit.Store {
    id: configStore
    fileName: "score-config.json"
    watch: true
    pollMs: 2000
    parse: function (raw) { return Model.parseConfig(raw) }
  }

  Kit.Store {
    id: stateStore
    fileName: "score-state.json"
    watch: true
    pollMs: 1500
    parse: function (raw) { return Model.parseState(raw) }
  }

  // ---- the CLI that owns every write to score-state.json
  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-score"

  Process {
    id: actionProc
    running: false
    onExited: stateStore.reload()   // reflect the write without waiting on the poll
  }

  // Run one omarchy-score verb. Serialised through actionProc; a verb fired
  // while one is already running falls back to execDetached so it isn't lost.
  function runVerb(verb) {
    guard.run("runVerb:" + verb, function() {
      if (actionProc.running) { Quickshell.execDetached([root.scriptPath, verb]); return }
      actionProc.command = [root.scriptPath, verb]
      actionProc.running = true
    })
  }

  // ---- Actions — each runs the matching CLI verb; the watch on stateStore
  //      reflects the result back into `state`.
  function increment() { root.runVerb("increment"); usage.record("increment") }
  function decrement() { root.runVerb("decrement"); usage.record("decrement") }
  function resetScore() { root.runVerb("reset"); usage.record("reset") }

  function undo() {
    if (!root.canUndo) return
    root.runVerb("undo")
    usage.record("undo")
  }

  // ---- IPC
  IpcHandler {
    target: "alteringux.score"

    function increment(): void { root.increment() }
    function decrement(): void { root.decrement() }
    function reset(): void { root.resetScore() }
    function undo(): void { root.undo() }
    function status(): string {
      return guard.call("ipc.status", function() {
        return JSON.stringify({
          score: root.state.score,
          config: root.config,
          historyCount: (root.state.history || []).length,
          canUndo: root.canUndo,
          usage: usage.topActions(6)
        })
      }, "{}")
    }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // ---- Popup panel
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

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

    onPressed: function(b) {
      if (b === Qt.RightButton) root.decrement()
      else if (b === Qt.MiddleButton) root.resetScore()
      else root.togglePanel()
    }

    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 2
      active: pulseTint.active
      level: pulseTint.level
    }
  }
}
