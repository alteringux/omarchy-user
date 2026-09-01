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
  readonly property bool canUndo: stateLoaded && Model.canUndo(root.state)

  // ---- persistence: two JSON files under ~/.local/state/omarchy/, each via
  // the shared Kit.Store (owns the FileView, atomic write, `mkdir -p`, and the
  // 200 ms save debounce). We hand it a file name and the matching tolerant
  // parser from Model.js; `config` / `state` read and write straight through.
  Kit.Store {
    id: configStore
    fileName: "score-config.json"
    parse: function (raw) { return Model.parseConfig(raw) }
    // score's icon / step are only settable by hand-editing this file, so
    // write a default on first run for the user to find.
    seedOnCreate: true
  }

  Kit.Store {
    id: stateStore
    fileName: "score-state.json"
    parse: function (raw) { return Model.parseState(raw) }
    // History is capped at write time so the file can't grow without bound
    // (the in-memory copy still holds the full log until restart, as before).
    serialize: function (v) { return JSON.stringify(Model.trimHistory(v, 50), null, 2) + "\n" }
  }

  function updateConfig(patch) {
    var next = JSON.parse(JSON.stringify(root.config))
    for (var key in patch) next[key] = patch[key]
    root.config = next
    configStore.save()
  }

  // ---- Actions
  function increment() {
    guard.run("increment", function() {
      root.state = Model.increment(root.state, root.config)
      stateStore.save()
      usage.record("increment")
    })
  }

  function decrement() {
    guard.run("decrement", function() {
      root.state = Model.decrement(root.state, root.config)
      stateStore.save()
      usage.record("decrement")
    })
  }

  function resetScore() {
    guard.run("resetScore", function() {
      root.state = Model.reset(root.state, root.config)
      stateStore.save()
      usage.record("reset")
    })
  }

  // Step back through the history log, reversing one entry at a time.
  function undo() {
    guard.run("undo", function() {
      if (!Model.canUndo(root.state)) return
      root.state = Model.undo(root.state)
      stateStore.save()
      usage.record("undo")
    })
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
  }
}
