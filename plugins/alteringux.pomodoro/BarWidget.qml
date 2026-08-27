import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Pomodoro timer for the bar: shows the current phase and remaining time,
// hosts the timer engine (countdown, stats, sound), and exposes IPC so
// Hyprland keybindings can drive start/pause/skip/reset. Left-clicking the
// bar label opens a popup with stats and settings.
//
// Phases pause between each other rather than auto-continuing — a
// completed phase lands in a "ready" state and waits for the next
// start/pause press, so a finished work block doesn't march into a break
// unattended.
BarWidget {
  id: root
  moduleName: "alteringux.pomodoro"

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/"
  // Deliberately NOT inside the plugin's own source directory: that tree is
  // watched by the shell's plugin-file watcher, and writing our own state
  // there triggers a "local plugin changed" reload that tears down any open
  // panel mid-interaction (e.g. right after clicking Start or editing a
  // duration field). Keep anything we write outside plugins/alteringux.pomodoro/.
  readonly property string configPath: stateDir + "pomodoro-config.json"
  readonly property string statsPath: stateDir + "pomodoro-stats.json"
  readonly property string historyPath: stateDir + "pomodoro-history.json"

  property var config: Model.defaultConfig()
  property var stats: Model.defaultStats()
  property var history: Model.defaultHistory()
  property bool configLoaded: false
  property bool statsLoaded: false
  property bool historyLoaded: false

  // Gentle, non-forced hint: the work length to suggest based on recent
  // completion/interruption patterns at the current duration. Null means
  // "not enough data yet" or "current length looks fine" — the UI only
  // shows a suggestion, it never changes workMinutes on its own.
  readonly property var workSuggestion: root.historyLoaded ? Model.suggestedWorkMinutes(root.history, root.config.workMinutes) : null

  // ---- Timer state
  property string phase: Model.PHASE_IDLE   // IDLE | WORK | SHORT_BREAK | LONG_BREAK
  property bool running: false
  property bool ready: false                // phase decided, waiting for a start press
  property real remainingMs: 0
  property real elapsedReadyMs: 0           // counts up while `ready` waits on the user
  property int completedPomodorosThisSession: 0

  readonly property string displayText: {
    if (phase === Model.PHASE_IDLE) return "🍅 Pomodoro"
    if (root.ready) return Model.readyIcon() + " " + Model.formatRemaining(root.elapsedReadyMs) + " " + Model.phaseLabel(phase) + " ready"
    var suffix = running ? "" : " ⏸"
    return Model.phaseIcon(phase) + " " + Model.formatRemaining(remainingMs) + " " + Model.phaseLabel(phase) + suffix
  }

  // ---------------------------------------------------- config persistence

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onLoadFailed: root.loadConfig("")
  }

  Timer {
    id: configSaveTimer
    interval: 200
    repeat: false
    onTriggered: root.flushConfig()
  }

  function loadConfig(raw) {
    var parsed = Model.defaultConfig()
    try {
      if (raw && raw.length > 0) {
        var stored = JSON.parse(raw)
        for (var key in parsed) if (stored[key] !== undefined) parsed[key] = stored[key]
        if (stored.sounds) for (var sk in parsed.sounds) if (stored.sounds[sk] !== undefined) parsed.sounds[sk] = stored.sounds[sk]
      }
    } catch (e) {
      console.warn("pomodoro: config parse failed:", e)
    }
    root.config = parsed
    root.configLoaded = true
    if (!raw || raw.length === 0) root.scheduleConfigSave()
  }

  function flushConfig() {
    if (!root.configLoaded) return
    configFile.setText(JSON.stringify(root.config, null, 2) + "\n")
  }

  function scheduleConfigSave() {
    if (!root.configLoaded) return
    configSaveTimer.restart()
  }

  function updateConfig(patch) {
    var next = JSON.parse(JSON.stringify(root.config))
    for (var key in patch) {
      if (key === "sounds") {
        for (var sk in patch.sounds) next.sounds[sk] = patch.sounds[sk]
      } else {
        next[key] = patch[key]
      }
    }
    root.config = next
    root.scheduleConfigSave()
  }

  // ----------------------------------------------------- stats persistence

  FileView {
    id: statsFile
    path: root.statsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadStats(text())
    onLoadFailed: root.loadStats("")
  }

  Timer {
    id: statsSaveTimer
    interval: 200
    repeat: false
    onTriggered: root.flushStats()
  }

  function loadStats(raw) {
    var parsed = Model.defaultStats()
    try {
      if (raw && raw.length > 0) {
        var stored = JSON.parse(raw)
        parsed.streak = stored.streak || 0
        parsed.lastActiveDate = stored.lastActiveDate || ""
        parsed.daily = stored.daily || {}
      }
    } catch (e) {
      console.warn("pomodoro: stats parse failed:", e)
    }
    root.stats = parsed
    root.statsLoaded = true
  }

  function flushStats() {
    if (!root.statsLoaded) return
    statsFile.setText(JSON.stringify(root.stats, null, 2) + "\n")
  }

  function scheduleStatsSave() {
    if (!root.statsLoaded) return
    statsSaveTimer.restart()
  }

  // -------------------------------------------------------- session history

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("")
  }

  Timer {
    id: historySaveTimer
    interval: 200
    repeat: false
    onTriggered: root.flushHistory()
  }

  function loadHistory(raw) {
    var parsed = Model.defaultHistory()
    try {
      if (raw && raw.length > 0) {
        var stored = JSON.parse(raw)
        if (Array.isArray(stored.sessions)) parsed.sessions = stored.sessions
      }
    } catch (e) {
      console.warn("pomodoro: history parse failed:", e)
    }
    root.history = parsed
    root.historyLoaded = true
  }

  function flushHistory() {
    if (!root.historyLoaded) return
    historyFile.setText(JSON.stringify(root.history, null, 2) + "\n")
  }

  function scheduleHistorySave() {
    if (!root.historyLoaded) return
    historySaveTimer.restart()
  }

  // Records one WORK-phase outcome (finished the full duration or cut
  // short) for the adaptive workSuggestion above.
  function recordWorkSession(completed) {
    root.history = Model.recordWorkSession(root.history, root.config.workMinutes, completed)
    root.scheduleHistorySave()
  }

  Process {
    id: ensureDirsProc
    command: ["mkdir", "-p", root.stateDir]
    running: false
  }

  Component.onCompleted: {
    ensureDirsProc.running = true
    Qt.callLater(function() {
      configFile.reload()
      statsFile.reload()
      historyFile.reload()
    })
  }

  // ---------------------------------------------------------- timer engine

  Timer {
    id: tickTimer
    interval: 1000
    repeat: true
    running: root.running
    onTriggered: root.tick()
  }

  function tick() {
    root.remainingMs = Math.max(0, root.remainingMs - 1000)
    if (root.remainingMs <= 0) root.completePhase(false)
  }

  // Counts up while a finished phase sits "ready" so the bar visibly
  // moves instead of looking frozen at the next phase's full duration.
  Timer {
    id: readyTickTimer
    interval: 1000
    repeat: true
    running: root.ready
    onTriggered: root.elapsedReadyMs += 1000
  }

  function playSound(transitionKey) {
    var path = Model.soundForTransition(root.config, transitionKey)
    Quickshell.execDetached(Model.soundPlayCommand(path))
  }

  // Nags the user with a desktop notification on a repeating interval
  // while a finished phase sits "ready", waiting to be started. Stops as
  // soon as they resume (running) or reset (idle).
  Timer {
    id: reminderTimer
    interval: Model.reminderIntervalMs(root.config)
    repeat: true
    running: root.ready
    onTriggered: root.sendReminder()
  }

  function sendReminder() {
    var n = Model.reminderNotification(root.phase)
    Quickshell.execDetached(["notify-send", "-a", "Pomodoro", n.summary, n.body])
  }

  function creditCompletedWork() {
    var today = Model.todayDateString()
    Model.rollDailyStats(root.stats, today)
    root.stats.daily[today].completed += 1
    root.stats.daily[today].focusedMs += Model.phaseDurationMs(Model.PHASE_WORK, root.config)
    root.stats.streak = Model.updateStreak(root.stats, today)
    root.stats.lastActiveDate = today
    root.scheduleStatsSave()
  }

  // Called when a phase's countdown reaches zero (skipped=false) or the
  // user explicitly skips (skipped=true). A skip never credits stats for
  // an unfinished WORK phase.
  function completePhase(skipped) {
    var wasWork = root.phase === Model.PHASE_WORK
    var preCompletedCount = root.completedPomodorosThisSession
    var upcoming = Model.nextPhase(root.phase, preCompletedCount, root.config.longBreakCycle)

    if (wasWork) {
      root.recordWorkSession(!skipped)
      if (!skipped) {
        root.completedPomodorosThisSession += 1
        root.creditCompletedWork()
      }
    }

    root.phase = upcoming
    root.remainingMs = Model.phaseDurationMs(upcoming, root.config)
    root.elapsedReadyMs = 0
    root.running = false
    root.ready = true
    root.playSound(Model.transitionKeyForPhase(upcoming))
    root.sendReminder()
  }

  function togglePause() {
    if (root.phase === Model.PHASE_IDLE) {
      root.phase = Model.PHASE_WORK
      root.remainingMs = Model.phaseDurationMs(Model.PHASE_WORK, root.config)
      root.running = true
      root.ready = false
      root.playSound("workStart")
      return
    }
    if (root.ready) {
      root.running = true
      root.ready = false
      return
    }
    root.running = !root.running
  }

  function skipPhase() {
    if (root.phase === Model.PHASE_IDLE) return
    root.completePhase(true)
  }

  function resetSession() {
    // Resetting out of a live WORK phase (not yet finished or skipped) is
    // itself an interruption signal for workSuggestion.
    if (root.phase === Model.PHASE_WORK) root.recordWorkSession(false)
    root.phase = Model.PHASE_IDLE
    root.running = false
    root.ready = false
    root.remainingMs = 0
    root.completedPomodorosThisSession = 0
  }

  IpcHandler {
    target: "alteringux.pomodoro"

    function togglePause(): void { root.togglePause() }
    function skipPhase(): void { root.skipPhase() }
    function resetSession(): void { root.resetSession() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function status(): string {
      return JSON.stringify({ phase: root.phase, remainingMs: root.remainingMs, running: root.running, ready: root.ready, elapsedReadyMs: root.elapsedReadyMs })
    }
  }

  // ---- Popup panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget
  //      root.
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
