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
  Kit.Store {
    id: stateStore
    fileName: "timers.json"
    parse: function (raw) { return Model.parseState(raw) }
    onLoadedChanged: if (loaded) root.nowMs = Date.now()
  }

  // A SEPARATE rolling log of completed timers (capped in Model.js) — feeds
  // the panel's most-used-label chips and the "running long" flag. The active
  // list itself stays history-free.
  Kit.Store {
    id: historyStore
    fileName: "timers-history.json"
    parse: function (raw) { return Model.parseHistory(raw) }
  }

  // Fold one entry that's about to leave the active list into the rolling
  // completion log. No-op until the history file has loaded, so a completion
  // during startup can't clobber real history with an empty log.
  function recordCompletion(entry) {
    if (!root.historyLoaded || !entry) return
    root.history = Model.recordCompletion(root.history, entry, Date.now())
    historyStore.save()
  }

  function entryById(id) {
    var list = root.entries
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }

  // ---- actions ---------------------------------------------------------
  function addEntry(label) {
    guard.run("addEntry", function() {
      var before = root.entries.length
      root.state = Model.addEntry(root.state, label)
      if (root.entries.length !== before) {
        root.nowMs = Date.now()
        stateStore.save()
        usage.record("add")
      }
    })
  }

  function removeEntry(id) {
    guard.run("removeEntry", function() {
      root.recordCompletion(root.entryById(id))
      root.state = Model.removeEntry(root.state, id)
      stateStore.save()
      usage.record("remove")
    })
  }

  // Edit-in-place: rename one timer from its card. Same persist path as
  // add/remove; the elapsed clock is untouched. See docs/adr/0003.
  function renameEntry(id, label) {
    guard.run("renameEntry", function() {
      root.state = Model.renameEntry(root.state, id, label)
      stateStore.save()
      usage.record("rename")
    })
  }

  // Pause / resume one timer's count-up clock. The card's × still records a
  // completion; pausing just banks the live span so elapsed stops advancing.
  function togglePauseEntry(id) {
    guard.run("togglePauseEntry", function() {
      var entry = root.entryById(id)
      if (!entry) return
      var wasPaused = Model.isPaused(entry)
      root.state = Model.togglePause(root.state, id, Date.now())
      root.nowMs = Date.now()
      stateStore.save()
      usage.record(wasPaused ? "resume" : "pause")
    })
  }

  function clearEntries() {
    guard.run("clearEntries", function() {
      var list = root.entries
      for (var i = 0; i < list.length; i++) root.recordCompletion(list[i])
      root.state = Model.defaultState()
      stateStore.save()
      usage.record("clear")
    })
  }

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
