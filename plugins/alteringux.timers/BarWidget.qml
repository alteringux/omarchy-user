import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit
import "Model.js" as Model

// Bar widget for a list of labelled "activity timers". Owns the entry list
// (label + createdAt epoch-ms) and persists it to a JSON state file; elapsed
// time is always derived (now - createdAt), never stored. The bar label is
// just icon + running count; the popup panel is the input + card list. Same
// bar-widget + click-panel shape as alteringux.stocks / alteringux.score.
//
// Self-improvement: a SEPARATE rolling log of completed timers
// (timers-history.json, capped) feeds two panel features — most-used labels
// as one-tap chips, and a "running long" flag when a live timer passes its
// label's typical run time. The active list itself stays history-free.
BarWidget {
  id: root
  moduleName: "alteringux.timers"

  // State + history are two JSON files under ~/.local/state/omarchy/, each
  // managed by a Kit.Store (FileView + atomic write + `mkdir -p` + the 200 ms
  // save debounce — written once in alteringux.kit instead of copied in here).
  // The Store instances are defined further down; `state` / `history` read and
  // write straight through them.
  property alias state: stateStore.value
  property alias history: historyStore.value
  readonly property bool stateLoaded: stateStore.loaded
  readonly property bool historyLoaded: historyStore.loaded
  readonly property var completed: history && history.completed ? history.completed : []

  // Ticks (see the tick Timer) only while the panel is open, so the cards'
  // elapsed-time bindings (they read root.nowMs) re-evaluate. The bar label
  // itself does not count up — it's just icon + count — so nothing ticks
  // while the overlay is closed.
  property double nowMs: Date.now()

  readonly property var entries: state && state.entries ? state.entries : []
  readonly property string displayText: stateLoaded
    ? Model.formatBadge(root.entries)
    : "  Timers"

  // Footer summary in the panel: total running time + time completed today.
  // Re-evaluates off nowMs, so it only advances while the panel is open.
  readonly property string totalsText: Model.formatTotals(root.entries, root.completed, root.nowMs)

  readonly property var guard: Kit.BugGuard.create("alteringux.timers", function(argv) { Quickshell.execDetached(argv) })

  // Per-plugin usage analytics — every user action is recorded so the panel
  // can adapt (chip row length) and status() can report habits.
  Kit.Usage { id: usage; pluginId: "alteringux.timers" }

  // Adaptive UI: someone who leans on the one-tap chips gets a longer chip
  // row; someone who mostly types keeps the compact four.
  readonly property int adaptiveChipLimit: usage.count("chip") >= 5 ? 6 : 4
  function recordChipUse() { usage.record("chip") }

  // ---- persistence: two JSON files, each via the shared Kit.Store -------
  // Store owns the FileView, atomic writes, the ~/.local/state/omarchy/ path,
  // `mkdir -p`, and the save debounce. We hand it a file name and the matching
  // tolerant parser from Model.js; it gives back `value` (aliased above to
  // `state` / `history`) and `loaded`. Mutations go: assign a fresh object to
  // `state` / `history`, then call `<store>.save()`.
  // Both files are now written only by ~/.local/bin/omarchy-timers
  // (docs/adr/0006-cli-first-plugins.md). Kit.Store runs in watch mode: it
  // re-reads + re-parses as the CLI rewrites them and the `state` / `history`
  // aliases update straight through. The idle poll covers FileView's
  // watch-on-create blind spot.
  Kit.Store {
    id: stateStore
    fileName: "timers.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseState(raw) }
    onLoadedChanged: if (loaded) root.nowMs = Date.now()
    onExternallyChanged: root.nowMs = Date.now()
  }

  // The rolling log of completed timers (capped by the CLI) — feeds the
  // panel's most-used-label chips and the "running long" flag.
  Kit.Store {
    id: historyStore
    fileName: "timers-history.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseHistory(raw) }
  }

  // ---- the CLI that owns every write to timers.json / timers-history.json
  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-timers"

  property string actionStatus: ""
  property int actionGeneration: 0
  readonly property bool actionPending: actionProc.feedbackGeneration === actionGeneration && actionProc.feedbackGeneration >= 0
  signal actionFeedback(string message, int generation, bool success)
  function reportActionStatus(message, success) {
    actionStatus = message
    actionFeedback(message, actionGeneration, success)
  }

  Process {
    id: actionProc
    property int feedbackGeneration: -1
    property bool feedbackStarted: false
    running: false
    onStarted: feedbackStarted = true
    onRunningChanged: {
      // Quickshell emits runningChanged(false), without exited, on launch failure.
      if (!running && !feedbackStarted && feedbackGeneration === root.actionGeneration) {
        feedbackGeneration = -1
        root.reportActionStatus("Timer helper unavailable. Check ~/.local/bin/omarchy-timers is installed and executable, then try again.", false)
      }
    }
    onExited: function(code, status) {
      stateStore.reload(); historyStore.reload()
      var generation = feedbackGeneration
      feedbackGeneration = -1
      if (generation !== root.actionGeneration) return
      root.reportActionStatus(code === 0 && status === 0
        ? "Timer request completed."
        : "Timer request failed (exit " + code + "). Try again; check that ~/.local/state/omarchy is writable.", code === 0 && status === 0)
    }
  }

  // Run one omarchy-timers verb (argv after the script path). Serialised
  // through actionProc; a verb fired mid-run falls back to execDetached.
  function runVerb(argv) {
    return guard.run("runVerb:" + argv[0], function() {
      root.actionGeneration++
      try {
        var cmd = [root.scriptPath].concat(argv)
        if (actionProc.running || actionProc.feedbackGeneration >= 0) {
          Quickshell.execDetached(cmd)
          root.reportActionStatus("Request sent. Completion is unavailable; check the timer list before trying again.", false)
          return -1
        }
        actionProc.feedbackGeneration = root.actionGeneration
        actionProc.feedbackStarted = false
        actionProc.command = cmd
        root.actionStatus = "Working…"
        actionProc.running = true
        return root.actionGeneration
      } catch (error) {
        actionProc.feedbackGeneration = -1
        root.reportActionStatus("Timer request could not be sent. Check ~/.local/bin/omarchy-timers is installed and executable, then try again.", false)
        throw error
      }
    })
  }

  function entryById(id) {
    var list = root.entries
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }

  // ---- actions — each runs the matching omarchy-timers verb; the watch on
  //      the two stores reflects the result back into `state` / `history`.
  //      The CLI also owns folding a removed/cleared timer into the log.
  function addEntry(label) {
    if (!label || label.trim().length === 0) return
    var generation = root.runVerb(["add", label])
    root.nowMs = Date.now()
    usage.record("add")
    return generation
  }

  function removeEntry(id) {
    root.runVerb(["remove", id])
    usage.record("remove")
  }

  // Edit-in-place: rename one timer from its card (see docs/adr/0003).
  function renameEntry(id, label) {
    root.runVerb(["rename", id, label])
    usage.record("rename")
  }

  // Pause / resume one timer's count-up clock.
  function togglePauseEntry(id) {
    var entry = root.entryById(id)
    var wasPaused = entry ? Model.isPaused(entry) : false
    root.runVerb(["pause-toggle", id])
    root.nowMs = Date.now()
    usage.record(wasPaused ? "resume" : "pause")
  }

  function clearEntries() {
    root.runVerb(["clear"])
    usage.record("clear")
  }

  // Forget one remembered label — the × on that chip in the panel. The CLI
  // drops every completed entry with that label, so the chip disappears and
  // the label's "running long" baseline is recomputed from what's left.
  function forgetLabel(label) { root.runVerb(["forget", label]) }

  // ---- tick ----------------------------------------------------------
  // Only runs while the overlay is open — that's the only place elapsed
  // time is shown. Kick nowMs once on open so cards are current immediately.
  Timer {
    interval: 1000
    repeat: true
    running: root.opened
    onTriggered: root.nowMs = Date.now()
  }

  onOpenedChanged: if (opened) nowMs = Date.now()

  // ---- IPC ---------------------------------------------------------
  IpcHandler {
    target: "alteringux.timers"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function add(label: string): void { root.addEntry(label) }
    function removeEntry(id: string): void { root.removeEntry(id) }
    function rename(id: string, label: string): void { root.renameEntry(id, label) }
    function pauseToggle(id: string): void { root.togglePauseEntry(id) }
    function clear(): void { root.clearEntries() }
    function forgetLabel(label: string): void { root.forgetLabel(label) }
    function status(): string {
      return guard.call("ipc.status", function() {
        var now = Date.now()
        var paused = 0
        for (var i = 0; i < root.entries.length; i++)
          if (Model.isPaused(root.entries[i])) paused++
        return JSON.stringify({
          count: root.entries.length,
          paused: paused,
          longestMs: Model.longestElapsedMs(root.entries, now),
          totalActiveMs: Model.totalActiveMs(root.entries, now),
          doneTodayMs: Model.completedTodayMs(root.completed, now),
          historyCount: root.completed.length,
          topLabels: Model.rankLabels(root.completed, root.entries, 4),
          usage: usage.topActions(6)
        })
      }, "{}")
    }
  }

  // ---- Popup panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
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
      root.togglePanel()
    }
  }
}
