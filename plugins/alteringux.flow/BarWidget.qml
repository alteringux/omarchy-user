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
  readonly property string docSaveBin: Quickshell.env("HOME") + "/.config/omarchy/local-bin/omarchy-flow-doc-save"
  readonly property string speakBin: Quickshell.env("HOME") + "/Work/bin/flow-speak"
  readonly property string piperBin: Quickshell.env("HOME") + "/.local/bin/piper-tts"
  readonly property string briefFeedsBin: Quickshell.env("HOME") + "/Work/bin/brief-feeds"
  readonly property string ttsTag: "flow-" + root.flowId


  // Canvas writes use a compare-and-swap helper rather than Kit.Store.save().
  // The document is also edited by `flow watch` / a text editor; a debounced
  // blind write could otherwise overwrite a refresh that landed meanwhile.
  property var pendingDoc: null
  property string pendingDocRaw: ""
  property string pendingExpectedRaw: ""
  property var localDoc: null
  property string docSaveStatus: ""
  property bool docWriteBlocked: false
  property string inFlightDocRaw: ""
  property string inFlightFlowId: ""
  property string inFlightExpectedRaw: ""
  property bool docWriteConflict: false
  property string ignoreDocRaw: ""
  readonly property var guard: Kit.BugGuard.create("alteringux.flow", function (argv) { Quickshell.execDetached(argv) })

  // ---- watched files (someone else writes them) -----------------------------
  Kit.Store {
    id: docStore
    dir: root.flowsDir
    fileName: root.flowId + ".json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseDoc(raw) }
    // value is the parsed canvas shape (flat x/y); write it back as the on-disk
    // flow-document shape (ui:{x,y}, sparse fields).
    serialize: function (v) { return Model.serializeDoc(v) }
  }
  Kit.Store {
    id: runStore
    fileName: "flows/" + root.flowId + ".json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseRunState(raw) }
  }
  // The sector `brief-feeds` is currently focused on (empty = every sector).
  // A plain one-line text file, written by `brief-feeds --set-focus`.
  Kit.Store {
    id: focusStore
    fileName: "flows/brief-focus"
    watch: true

    pollMs: 60000
    parse: function (raw) { return (raw || "").trim() }
  }
  Connections {
    target: docStore
    function onExternallyChanged(value) { root._onDocRefresh(value) }
  }

  Timer {
    id: docWriteTimer
    interval: 200
    repeat: false
    onTriggered: root._startDocWrite()
  }

  Process {
    id: docWriteProc
    running: false
    onExited: function (code) { root._finishDocWrite(code) }
  }

  readonly property var doc: root.localDoc !== null ? root.localDoc : docStore.value
  property alias runState: runStore.value
  readonly property string focusSector: focusStore.value || ""
  readonly property bool ready: docStore.loaded && runStore.loaded

  // Re-point both stores when the flow selection changes. Never carry a
  // debounced write across flows; an in-flight helper is already bound to the
  // old path and is allowed to finish there.
  onFlowIdChanged: {
    docWriteTimer.stop()
    pendingDoc = null
    pendingDocRaw = ""
    pendingExpectedRaw = ""
    localDoc = null
    docSaveStatus = ""
    docWriteBlocked = false
    docWriteConflict = false
    docStore.reload()
    runStore.reload()
  }

  // ---- text-to-speech + sector focus (the brief's play controls) ----------
  readonly property string briefText: root.guard.call("briefText", function () {
    var envs = (root.runState && root.runState.envelopes) || []
    for (var i = 0; i < envs.length; i++) {
      var e = envs[i]
      if (e && (e.shape === "markdown" || e.shape === "text") && typeof e.data === "string" && e.data.length)
        return e.data
    }
    return ""
  }, "")

  function speak(text) {
    root.guard.run("speak", function () {
      var t = String(text == null ? "" : text).trim()
      if (!t.length) return
      Quickshell.execDetached([root.speakBin, "--tag", root.ttsTag, t])
    })
  }
  function speakBrief() { root.speak(Model.speakable(root.briefText)) }
  function stopSpeak() {
    root.guard.run("stopSpeak", function () {
      Quickshell.execDetached([root.piperBin, "--stop", "--tag", root.ttsTag])
    })
  }

  // Write the focus file (empty name clears it) then re-run the flow so the
  // brief re-fetches for just that sector. One `sh -c` keeps the two steps
  // ordered; args are single-quoted (a sector name may contain "&").
  function setSector(name) {
    root.guard.run("setSector", function () {
      var n = String(name == null ? "" : name).trim()
      var q = function (s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
      var focusCmd = n.length ? (q(root.briefFeedsBin) + " --set-focus " + q(n))
                              : (q(root.briefFeedsBin) + " --clear-focus")
      var runCmd = q(root.flowBin) + " run " + q(root.flowId) + " --once"
      Quickshell.execDetached(["sh", "-c", focusCmd + " ; " + runCmd])
    })
  }

  readonly property string summary: guard.call("summary", function () {
    return root.runState && root.runState.ok !== undefined ? Model.barSummary(root.runState) : ""
  }, "")

  readonly property string displayText: "  " + root.flowId
    + (root.focusSector ? "  ·" + root.focusSector : "")
    + (root.summary ? "  " + root.summary : "")

  function runFlow() {
    guard.run("runFlow", function () {
      Quickshell.execDetached([root.flowBin, "run", root.flowId, "--once"])
    })
  }

  // ---- canvas edits: compare-and-swap persistence --------------------------
  // The flow document is shared with the CLI and text editors. Kit.Store's
  // debounced save has no read-before-write check, so a refresh could be
  // silently overwritten by a pending canvas edit. Queue edits locally, then
  // atomically write only when the file still contains our expected revision.
  function persistDoc(newDoc) {
    guard.run("persistDoc", function () {
      if (!newDoc || !docStore.loaded) return
      var hasPending = root.pendingDoc !== null
      root.pendingExpectedRaw = hasPending
        ? root.pendingExpectedRaw
        : (docWriteProc.running ? root.inFlightDocRaw : docStore._lastRaw)
      root.pendingDoc = newDoc
      root.pendingDocRaw = Model.serializeDoc(newDoc)
      root.localDoc = newDoc
      if (root.docWriteBlocked) {
        root.pendingDoc = null
        root.pendingDocRaw = ""
        root.pendingExpectedRaw = ""
        root.docSaveStatus = "The flow file changed elsewhere. Your canvas edits are still here; retry to save over that version, or discard them."
        return
      }
      root.docSaveStatus = "Saving canvas edits…"
      docWriteTimer.restart()
    })
  }

  function _startDocWrite() {
    if (docWriteProc.running || root.pendingDoc === null) return
    root.inFlightExpectedRaw = root.pendingExpectedRaw
    root.inFlightDocRaw = root.pendingDocRaw
    root.inFlightFlowId = root.flowId
    root.pendingDoc = null
    root.pendingDocRaw = ""
    root.pendingExpectedRaw = ""
    root.docSaveStatus = "Saving canvas edits…"
    docWriteProc.command = [
      root.docSaveBin, docStore.path, root.inFlightExpectedRaw, root.inFlightDocRaw
    ]
    docWriteProc.running = true
  }
  function _onDocRefresh(value) {
    // A successful CAS is followed by reload() so Store's own cache catches
    // up. Recognise that exact text and do not mistake it for an outside edit.
    var adopted = ""
    try { adopted = Model.serializeDoc(value) } catch (_) {}
    if (root.inFlightDocRaw && adopted === root.inFlightDocRaw) return
    if (root.ignoreDocRaw) {
      var selfRefresh = adopted === root.ignoreDocRaw
      root.ignoreDocRaw = ""
      if (selfRefresh) return
    }
    if (root.localDoc !== null) {
      root.docWriteBlocked = true
      if (docWriteTimer.running) docWriteTimer.stop()
      root.pendingDoc = null
      root.pendingDocRaw = ""
      root.pendingExpectedRaw = ""
      if (docWriteProc.running) root.docWriteConflict = true
      root.docSaveStatus = "The flow file changed elsewhere. Your canvas edits are still here; retry to save over that version, or discard them."
      return
    }
    // External state wins over a not-yet-written local edit. This makes a
    // refresh/write collision deterministic instead of last-timer-wins.
    if (docWriteTimer.running) docWriteTimer.stop()
    root.pendingDoc = null
    root.pendingDocRaw = ""
    root.pendingExpectedRaw = ""
    if (docWriteProc.running) root.docWriteConflict = true
  }

  function _finishDocWrite(code) {
    var sameFlow = root.inFlightFlowId === root.flowId
    var committed = code === 0 && !root.docWriteConflict
    var writeConflict = root.docWriteConflict
    root.docWriteConflict = false
    root.inFlightExpectedRaw = ""
    root.inFlightFlowId = ""
    if (committed && sameFlow) {
      // Store will adopt the exact text and emit externallyChanged; remember
      // it so that self-refresh does not cancel the next queued edit.
      root.ignoreDocRaw = root.inFlightDocRaw
      if (root.pendingDoc === null) root.localDoc = null
      root.docWriteBlocked = false
      root.docSaveStatus = "Canvas edits saved."
      docStore.reload()
    } else {
      root.ignoreDocRaw = ""
      if (sameFlow && root.localDoc !== null) {
        if (writeConflict || code === 2) root.docWriteBlocked = true
        root.docSaveStatus = writeConflict || code === 2
          ? "The flow file changed elsewhere. Your canvas edits are still here; retry to save over that version, or discard them."
          : "Could not save the flow. Your canvas edits are still here; retry or discard them."
      }
      docStore.reload()
    }
    root.inFlightDocRaw = ""
    if (sameFlow && committed && root.pendingDoc !== null) docWriteTimer.restart()
    else {
      root.pendingDoc = null
      root.pendingDocRaw = ""
      root.pendingExpectedRaw = ""
    }
  }

  function retryDocSave() {
    if (root.localDoc === null || docWriteProc.running) return
    root.docWriteBlocked = false
    root.pendingDoc = root.localDoc
    root.pendingDocRaw = Model.serializeDoc(root.localDoc)
    // Retrying is an explicit choice to write the retained canvas over the
    // currently observed version, including after a compare-and-swap conflict.
    root.pendingExpectedRaw = docStore._lastRaw
    root.docSaveStatus = "Saving canvas edits…"
    docWriteTimer.restart()
  }

  function discardDocEdits() {
    docWriteTimer.stop()
    root.pendingDoc = null
    root.pendingDocRaw = ""
    root.pendingExpectedRaw = ""
    root.localDoc = null
    root.docWriteBlocked = false
    root.docSaveStatus = "Canvas edits discarded."
    docStore.reload()
  }

  // ---- IPC -----------------------------------------------------------------
  IpcHandler {
    target: "alteringux.flow"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function run(): void { root.runFlow() }
    function show(id: string): void { if (id && id.length) root.flowId = id }
    function speak(): void { root.speakBrief() }
    function stopSpeak(): void { root.stopSpeak() }
    // sector("") / sector("full") / sector("all") clear the focus; any other
    // value focuses the brief on that sector and re-runs it.
    function sector(name: string): void {
      var n = (name || "").trim()
      root.setSector(/^(|full|all|every|clear)$/i.test(n) ? "" : n)
    }
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
          focus: root.focusSector,
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
