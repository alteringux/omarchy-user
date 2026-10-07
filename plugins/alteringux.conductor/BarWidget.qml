import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// The conductor: one bar widget that runs whole *rituals* — ordered
// sequences of other alteringux plugin CLI verbs — and watches the combined
// state of every one of them.
//
// Every write to conductor-state.json / conductor-snapshot.json is owned by
// ~/.local/bin/omarchy-conductor (docs/adr/0006-cli-first-plugins.md). This
// widget is a thin view: Kit.Store watches the files, a serialised Process
// fires verbs, the panel renders the ritual catalogue + the cockpit.
BarWidget {
  id: root
  moduleName: "alteringux.conductor"

  property alias state: stateStore.value
  property alias snapshot: snapStore.value
  readonly property bool stateLoaded: stateStore.loaded

  readonly property string icon: ""   // nf-fa-music — the baton

  readonly property bool active: stateLoaded && root.state.active === true
  readonly property string displayText: root.stateLoaded && root.active
    ? Model.widgetLabel(root.state)
    : ""

  readonly property var guard: Kit.BugGuard.create("alteringux.conductor", function (argv) { Quickshell.execDetached(argv) })
  Kit.PulseTint {
    id: pulseTint
    pluginId: "alteringux.conductor"
  }
  Kit.Usage { id: usage; pluginId: "alteringux.conductor" }

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-conductor"

  // ---- state files, both written only by the CLI ----------------------
  Kit.Store {
    id: stateStore
    fileName: "conductor-state.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseState(raw) }
  }

  Kit.Store {
    id: snapStore
    fileName: "conductor-snapshot.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseSnapshot(raw) }
  }

  // ---- verb runner: one serialising Process, execDetached fallback ----
  Process {
    id: actionProc
    running: false
    onExited: {
      stateStore.reload()
      snapStore.reload()
    }
  }

  function runVerb(args) {
    guard.run("runVerb:" + args.join(" "), function () {
      var cmd = [root.scriptPath].concat(args)
      if (actionProc.running) { Quickshell.execDetached(cmd); return }
      actionProc.command = cmd
      actionProc.running = true
    })
  }

  function runRitual(id, label) {
    if (!id) return
    var args = ["run", id]
    if (label && label.trim().length > 0) args.push(label.trim())
    root.runVerb(args)
    usage.record("run:" + id)
  }
  function stopRitual()  { root.runVerb(["stop"]);  usage.record("stop") }
  function abortRitual() { root.runVerb(["abort"]); usage.record("abort") }
  function advance()     { root.runVerb(["advance"]); usage.record("advance") }

  // ---- ritual catalogue (from `omarchy-conductor list`) --------------
  property var rituals: []

  Process {
    id: listProc
    running: false
    command: [root.scriptPath, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        guard.run("listProc.onStreamFinished", function () {
          root.rituals = Model.parseRitualList(text)
        })
      }
    }
  }

  function refreshRituals() {
    guard.run("refreshRituals", function () {
      if (!listProc.running) listProc.running = true
    })
  }

  // ---- cockpit refresh: `snapshot` recomputes conductor-snapshot.json --
  Process {
    id: snapProc
    running: false
    command: [root.scriptPath, "snapshot"]
    onExited: snapStore.reload()
  }

  function refreshSnapshot() {
    guard.run("refreshSnapshot", function () {
      if (!snapProc.running) snapProc.running = true
    })
  }

  Component.onCompleted: {
    root.refreshRituals()
    root.refreshSnapshot()
  }

  // ---- IPC ----------------------------------------------------------
  IpcHandler {
    target: "alteringux.conductor"

    function run(id: string): void { root.runRitual(id, "") }
    function runLabeled(id: string, label: string): void { root.runRitual(id, label) }
    function advance(): void { root.advance() }
    function stop(): void { root.stopRitual() }
    function abort(): void { root.abortRitual() }
    function refresh(): void { root.refreshSnapshot(); root.refreshRituals() }

    function status(): string {
      return guard.call("ipc.status", function () {
        var c = Model.stepCounts(root.state)
        return JSON.stringify({
          active: root.active,
          ritual: root.state.ritual,
          label: root.state.label,
          phase: root.state.phase,
          step: c.done,
          total: c.total,
          lastSummary: root.state.lastSummary,
          rituals: (root.rituals || []).map(function (r) { return r.id }),
          usage: usage.topActions(6)
        })
      }, "{}")
    }

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // ---- panel ------------------------------------------------------
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
    text: root.active ? (root.icon + "  " + root.displayText) : root.icon
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function (b) {
      if (b === Qt.RightButton) {
        if (root.active) root.advance()
        else root.togglePanel()
      } else if (b === Qt.MiddleButton) {
        if (root.active) root.stopRitual()
      } else {
        root.togglePanel()
      }
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
