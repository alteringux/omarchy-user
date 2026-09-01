import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

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

  // State lives under ~/.local/state/omarchy/ (via Kit.Store), deliberately NOT
  // inside the plugin's own source directory: that tree is watched by the
  // shell's plugin-file watcher, and writing our own state there triggers a
  // "local plugin changed" reload that tears down any open panel
  // mid-interaction (e.g. right after clicking Start or editing a duration
  // field).
  property alias config: configStore.value
  property alias stats: statsStore.value
  property alias history: historyStore.value
  readonly property bool configLoaded: configStore.loaded
  readonly property bool statsLoaded: statsStore.loaded
  readonly property bool historyLoaded: historyStore.loaded

  // Live-timer persistence: a running pomodoro is written to
  // pomodoro-session.json so a shell restart or reboot resumes it instead of
  // dropping back to idle. `_restored` guards the one-shot reconcile, which
  // waits for every store it touches (session + config for phase maths,
  // stats + history to credit a block that completed offline).
  readonly property bool sessionLoaded: sessionStore.loaded
  readonly property bool restoreReady: sessionLoaded && configLoaded && statsLoaded && historyLoaded
  property bool _restored: false

  onRestoreReadyChanged: if (restoreReady) restoreFromSession()

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
    if (phase === Model.PHASE_IDLE) return "  Pomodoro"
    if (root.ready) return Model.readyIcon() + " " + Model.formatRemaining(root.elapsedReadyMs) + " " + Model.phaseLabel(phase) + " ready"
    var suffix = running ? "" : " "
    return Model.phaseIcon(phase) + " " + Model.formatRemaining(remainingMs) + " " + Model.phaseLabel(phase) + suffix
  }

  // ---- bar progress fill: a hairline under the label that tracks how far
  // the current phase has run (empty at its start, full when it completes).
  // Shown for WORK and both break phases while a timer is live or paused;
  // hidden in IDLE and in the "ready" gap between phases. A paused fill dims
  // rather than disappears so a stopped timer still reads at a glance.
  readonly property bool showProgress: phase !== Model.PHASE_IDLE && !ready
  readonly property real progressFraction: (showProgress && configLoaded) ? Model.phaseProgress(phase, remainingMs, config) : 0
  readonly property color progressColor: phase === Model.PHASE_WORK ? Kit.Palette.info : Kit.Palette.positive

  readonly property var guard: Kit.BugGuard.create("alteringux.pomodoro", function(argv) { Quickshell.execDetached(argv) })

  // ---- persistence: three JSON files under ~/.local/state/omarchy/, each via
  // the shared Kit.Store (owns the FileView, atomic write, `mkdir -p`, and the
  // 200 ms save debounce). `config` / `stats` / `history` read and write
  // straight through the matching store; the tolerant parsers live in Model.js.
  Kit.Store {
    id: configStore
    fileName: "pomodoro-config.json"
    parse: function (raw) { return Model.parseConfig(raw) }
    // Durations / sounds are edited from the panel AND by hand — seed a default
    // file on first run so there's something to open.
    seedOnCreate: true
  }

  // The live timer. No seedOnCreate — no file exists until a pomodoro has
  // actually run, and an all-idle state never writes one.
  Kit.Store {
    id: sessionStore
    fileName: "pomodoro-session.json"
    parse: function (raw) { return Model.parseSession(raw) }
  }

  // Rebuilds the timer from the persisted session, subtracting the wall-clock
  // gap the process was gone for. Runs exactly once, when every store it reads
  // is loaded (see `restoreReady`). A WORK block that ran out while the shell
  // was down is credited to stats/history here, as a live completion would be.
  function restoreFromSession() {
    guard.run("restoreFromSession", function() {
      if (root._restored || !root.restoreReady) return
      root._restored = true

      var stored = sessionStore.value
      if (!stored || stored.phase === Model.PHASE_IDLE) return

      var r = Model.restoreSession(stored, Date.now(), root.config)
      root.phase = r.phase
      root.running = r.running
      root.ready = r.ready
      root.remainingMs = r.remainingMs
      root.elapsedReadyMs = r.elapsedReadyMs
      root.completedPomodorosThisSession = r.completedPomodorosThisSession

      if (r.workCompletedOffline) {
        if (root.historyLoaded) root.recordWorkSession(true)
        if (root.statsLoaded) root.creditCompletedWork()
      }
      // Re-announce a phase that fell due while we were away, and re-play its
      // transition sound, so coming back to the desktop isn't silent.
      if (r.ready && r.workCompletedOffline) {
        root.playSound(Model.transitionKeyForPhase(r.phase))
        root.sendReminder()
      }
      root.snapshotSession()
    })
  }

  // Write the current timer to disk (debounced by Kit.Store). Called on every
  // transition and on a slow heartbeat while a phase is live or waiting.
  function snapshotSession() {
    guard.run("snapshotSession", function() {
      if (!sessionStore.loaded) return
      sessionStore.value = {
        version: 1,
        phase: root.phase,
        running: root.running,
        ready: root.ready,
        remainingMs: root.remainingMs,
        elapsedReadyMs: root.elapsedReadyMs,
        completedPomodorosThisSession: root.completedPomodorosThisSession,
        savedAtMs: Date.now()
      }
      sessionStore.save()
    })
  }

  // Heartbeat: the exact remaining time is reconstructed from savedAtMs on
  // load, so this is just a bound on staleness (and a guard against wall-clock
  // jumps) rather than something accuracy depends on.
  Timer {
    id: sessionPersistTimer
    interval: 15000
    repeat: true
    running: root.running || root.ready
    onTriggered: root.snapshotSession()
  }

  Kit.Store {
    id: statsStore
    fileName: "pomodoro-stats.json"
    parse: function (raw) { return Model.parseStats(raw) }
  }

  Kit.Store {
    id: historyStore
    fileName: "pomodoro-history.json"
    parse: function (raw) { return Model.parseHistory(raw) }
  }

  function updateConfig(patch) {
    guard.run("updateConfig", function() {
      var next = JSON.parse(JSON.stringify(root.config))
      for (var key in patch) {
        if (key === "sounds") {
          for (var sk in patch.sounds) next.sounds[sk] = patch.sounds[sk]
        } else {
          next[key] = patch[key]
        }
      }
      root.config = next
      configStore.save()
    })
  }

  // Records one WORK-phase outcome (finished the full duration or cut
  // short) for the adaptive workSuggestion above.
  function recordWorkSession(completed) {
    guard.run("recordWorkSession", function() {
      root.history = Model.recordWorkSession(root.history, root.config.workMinutes, completed)
      historyStore.save()
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
    guard.run("tick", function() {
      root.remainingMs = Math.max(0, root.remainingMs - 1000)
      if (root.remainingMs <= 0) root.completePhase(false)
    })
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
    guard.run("playSound", function() {
      var path = Model.soundForTransition(root.config, transitionKey)
      Quickshell.execDetached(Model.soundPlayCommand(path))
    })
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
    guard.run("sendReminder", function() {
      var n = Model.reminderNotification(root.phase)
      Quickshell.execDetached(["notify-send", "-a", "Pomodoro", n.summary, n.body])
    })
  }

  function creditCompletedWork() {
    guard.run("creditCompletedWork", function() {
      var today = Model.todayDateString()
      Model.rollDailyStats(root.stats, today)
      root.stats.daily[today].completed += 1
      root.stats.daily[today].focusedMs += Model.phaseDurationMs(Model.PHASE_WORK, root.config)
      root.stats.streak = Model.updateStreak(root.stats, today)
      root.stats.lastActiveDate = today
      statsStore.save()
    })
  }

  // Called when a phase's countdown reaches zero (skipped=false) or the
  // user explicitly skips (skipped=true). A skip never credits stats for
  // an unfinished WORK phase.
  function completePhase(skipped) {
    guard.run("completePhase", function() {
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
    })
    root.snapshotSession()
  }

  function togglePause() {
    guard.run("togglePause", function() {
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
    })
    root.snapshotSession()
  }

  function skipPhase() {
    guard.run("skipPhase", function() {
      if (root.phase === Model.PHASE_IDLE) return
      root.completePhase(true)
    })
  }

  function resetSession() {
    guard.run("resetSession", function() {
      // Resetting out of a live WORK phase (not yet finished or skipped) is
      // itself an interruption signal for workSuggestion.
      if (root.phase === Model.PHASE_WORK) root.recordWorkSession(false)
      root.phase = Model.PHASE_IDLE
      root.running = false
      root.ready = false
      root.remainingMs = 0
      root.completedPomodorosThisSession = 0
    })
    root.snapshotSession()
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
      return guard.call("ipc.status", function() {
        return JSON.stringify({ phase: root.phase, remainingMs: root.remainingMs, running: root.running, ready: root.ready, elapsedReadyMs: root.elapsedReadyMs })
      }, "{}")
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

    // ---- phase progress bar ---------------------------------------
    // A thin fill pinned to the widget's bottom edge: a faint full-width
    // track with a colored fill whose width is the elapsed fraction of the
    // current phase. Runs under the mm:ss label without covering it.
    Item {
      id: progress
      visible: root.showProgress
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.spaceReal(4)
      anchors.rightMargin: Style.spaceReal(4)
      anchors.bottomMargin: Style.spaceReal(2)
      height: Math.max(2, Style.spaceReal(2.5))

      Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Kit.Palette.faint
        opacity: 0.35
      }

      Rectangle {
        id: fill
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        radius: height / 2
        width: Math.round(track.width * Math.max(0, Math.min(1, root.progressFraction)))
        color: root.progressColor
        opacity: root.running ? 1 : 0.4

        // Glide between the 1 s ticks instead of stepping; a phase change
        // snaps the fraction near 0 and this just sweeps back quickly.
        Behavior on width {
          NumberAnimation { duration: 900; easing.type: Easing.Linear }
        }
        Behavior on opacity {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }
    }
  }
}
