import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit
import "Model.js" as Model

// Bar widget for "Omarchy Flows". It owns nothing — the runner is
// ~/Work/bin/flow (Node). This widget only *watches* two JSON files:
//
//   ~/.config/omarchy/flows/<id>.json        the flow document (the canvas edits this)
//   ~/.local/state/omarchy/flows/<id>.json    the last run: per-node status + envelopes
//
// The bar label is a one-line read of the latest run (a sparkline of the first
// `series` envelope, or a ✓/✗ tally). Clicking opens the panel: the rendered
// output on one tab, a draggable node canvas with a Run button on the other.
BarWidget {
  id: root
  moduleName: "alteringux.flow"

  // Which flow this surface shows. Change with `omarchy-shell alteringux.flow show <id>`.
  property string flowId: "morning-brief"

  readonly property string flowsDir: Quickshell.env("HOME") + "/.config/omarchy/flows/"
  readonly property string flowBin: Quickshell.env("HOME") + "/Work/bin/flow"

  readonly property var guard: Kit.BugGuard.create("alteringux.flow", function (argv) { Quickshell.execDetached(argv) })

  // ---- watched files (someone else writes them) -----------------------------
  Kit.Store {
    id: docStore
    dir: root.flowsDir
    fileName: root.flowId + ".json"
    watch: true
    pollMs: 2500
    parse: function (raw) { return Model.parseDoc(raw) }
    // value is the parsed canvas shape (flat x/y); write it back as the on-disk
    // flow-document shape (ui:{x,y}, sparse fields).
    serialize: function (v) { return Model.serializeDoc(v) }
  }
  Kit.Store {
    id: runStore
    fileName: "flows/" + root.flowId + ".json"
    watch: true
    pollMs: 2500
    parse: function (raw) { return Model.parseRunState(raw) }
  }

  property alias doc: docStore.value
  property alias runState: runStore.value
  readonly property bool ready: docStore.loaded && runStore.loaded

  // Re-point both stores when the flow selection changes.
  onFlowIdChanged: {
    docStore.reload()
    runStore.reload()
  }

  readonly property string summary: guard.call("summary", function () {
    return root.runState && root.runState.ok !== undefined ? Model.barSummary(root.runState) : ""
  }, "")

  readonly property string displayText: "  " + root.flowId + (root.summary ? "  " + root.summary : "")

  function runFlow() {
    guard.run("runFlow", function () {
      Quickshell.execDetached([root.flowBin, "run", root.flowId, "--once"])
    })
  }

  // ---- canvas edits: mutate the parsed doc, let Kit.Store write it back -----
  // save() works in watch mode too; the reload of our own write re-reads
  // identical text, so it does not re-loop.
  function persistDoc(newDoc) {
    guard.run("persistDoc", function () {
      if (!newDoc) return
      docStore.value = newDoc
      docStore.save()
    })
  }
  function moveNode(id, x, y) { root.persistDoc(Model.moveNode(root.doc, id, x, y)) }
  function setNodeField(id, key, val) { root.persistDoc(Model.setField(root.doc, id, key, val)) }
  function toggleEdge(fromId, toId) { root.persistDoc(Model.toggleEdge(root.doc, fromId, toId)) }
  function removeNode(id) { root.persistDoc(Model.removeNode(root.doc, id)) }
  function addNode(type) {
    root.guard.run("addNode", function () {
      var r = Model.addNode(root.doc, type)
      root.persistDoc(r.doc)
    })
  }

  // ---- IPC -----------------------------------------------------------------
  IpcHandler {
    target: "alteringux.flow"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function run(): void { root.runFlow() }
    function show(id: string): void { if (id && id.length) root.flowId = id }
    function status(): string {
      return root.guard.call("ipc.status", function () {
        var rs = root.runState || {}
        var envs = rs.envelopes || []
        var shapes = []
        for (var i = 0; i < envs.length; i++) shapes.push(envs[i].node + ":" + envs[i].shape)
        var ok = 0, bad = 0, skip = 0
        for (var k in (rs.nodes || {})) {
          var s = rs.nodes[k].status
          if (s === "ok") ok++; else if (s === "error") bad++; else if (s === "skipped") skip++
        }
        return JSON.stringify({
          flow: root.flowId,
          loaded: root.ready,
          nodes: root.doc && root.doc.nodes ? root.doc.nodes.length : 0,
          lastRun: { ok: rs.ok, at: rs.finishedAt || "", pass: ok, fail: bad, skipped: skip, error: rs.error || "" },
          envelopes: shapes
        })
      }, "{}")
    }
  }

  // ---- panel plumbing (same shape contract as alteringux.timers) ----------
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
    onPressed: function (b) { root.togglePanel() }
  }
}
