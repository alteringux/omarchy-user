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

  // Gentle, non-forced hint: the work length to suggest based on recent
  // completion/interruption patterns at the current duration. Null means
  // "not enough data yet" or "current length looks fine" — the UI only
  // shows a suggestion, it never changes workMinutes on its own.
  readonly property var workSuggestion: root.historyLoaded ? Model.suggestedWorkMinutes(root.history, root.config.workMinutes) : null

  // Today's completed count + current streak, from the same stats bucket the
  // panel's STATISTICS section already reads — exposed on the widget too so
  // IPC status() can report them (a keybinding or another plugin querying
  // `alteringux.pomodoro status` shouldn't have to shell out to the CLI
  // separately just for the numbers the panel already shows).
  readonly property var todayBucket: root.statsLoaded && root.stats.daily && root.stats.daily[Model.todayDateString()]
    ? root.stats.daily[Model.todayDateString()] : { completed: 0, focusedMs: 0 }
  readonly property int completedToday: root.todayBucket.completed || 0
  readonly property int streak: root.statsLoaded ? (root.stats.streak || 0) : 0

  // ---- Timer state: derived from the watched pomodoro-session.json, which is
  // written only by ~/.local/bin/omarchy-pomodoro — its `__run` systemd --user
  // daemon owns the 1s countdown, phase transitions, transition sounds,
  // ready-reminders and streak/stats bookkeeping (docs/adr/0006-cli-first-plugins.md).
  // `displayNowMs` ticks once a second while a phase is live so the mm:ss
  // readout counts down smoothly between the daemon's ~5s heartbeat writes;
  // the exact remaining is reconstructed from savedAtMs, the same way the
  // daemon's own restore does.
  readonly property var session: sessionStore.value || Model.defaultSession()
  property double displayNowMs: Date.now()

  readonly property string phase: session.phase
  readonly property bool running: session.running === true
  readonly property bool ready: session.ready === true
  readonly property real remainingMs: running
    ? Math.max(0, session.remainingMs - (displayNowMs - session.savedAtMs))
    : session.remainingMs
  readonly property real elapsedReadyMs: ready
    ? session.elapsedReadyMs + Math.max(0, displayNowMs - session.savedAtMs)
    : session.elapsedReadyMs
  readonly property int completedPomodorosThisSession: session.completedPomodorosThisSession || 0
  // Focus accounting only includes the live WORK segment. The CLI banks
  // completed segments into today's stats; this live value keeps the bar and
  // panel accurate between heartbeat writes.
  readonly property real liveWorkMs: phase === Model.PHASE_WORK
    ? (session.focusedMs || 0) + (running ? Math.max(0, displayNowMs - session.savedAtMs) : 0)
    : 0
  readonly property real focusedTodayMs: (root.todayBucket.focusedMs || 0) + root.liveWorkMs
  readonly property real dailyGoalMs: Math.max(0, (root.config.dailyGoalMinutes || 0) * 60000)
  readonly property real goalRemainingMs: Model.goalRemainingMs(root.todayBucket.focusedMs || 0, root.config, root.liveWorkMs)
  readonly property real goalProgress: Model.goalProgress(root.todayBucket.focusedMs || 0, root.config, root.liveWorkMs)

  readonly property string goalText: Model.formatGoalRemaining(root.goalRemainingMs)

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

  Kit.PulseTint {
    id: pulseTint
    pluginId: "alteringux.pomodoro"
  }

  // ---- persistence -----------------------------------------------------
  // config stays widget-owned (durations / sounds, edited from the panel AND
  // by hand). session / stats / history are written only by omarchy-pomodoro,
  // so those stores run in watch mode and stream their files back in.
  Kit.Store {
    id: configStore
    fileName: "pomodoro-config.json"
    parse: function (raw) { return Model.parseConfig(raw) }
    seedOnCreate: true
  }

  Kit.Store {
    id: sessionStore
    fileName: "pomodoro-session.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseSession(raw) }
    onExternallyChanged: root.displayNowMs = Date.now()
  }

  Kit.Store {
    id: statsStore
    fileName: "pomodoro-stats.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseStats(raw) }
  }

  Kit.Store {
    id: historyStore
    fileName: "pomodoro-history.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseHistory(raw) }
  }

  // ---- the CLI + daemon that own the timer
  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-pomodoro"

  Process {
    id: actionProc
    running: false
    onExited: { sessionStore.reload(); statsStore.reload(); historyStore.reload() }
  }

  function runVerb(verb) {
    guard.run("runVerb:" + verb, function() {
      if (actionProc.running) { Quickshell.execDetached([root.scriptPath, verb]); return }
      actionProc.command = [root.scriptPath, verb]
      actionProc.running = true
    })
  }

  // Once, on load: let the CLI reconcile a session persisted across a restart /
  // reboot (crediting a WORK block that ran out offline) and respawn the daemon
  // if a phase is still live.
  Component.onCompleted: Qt.callLater(function() { Quickshell.execDetached([root.scriptPath, "restore"]) })

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

  // ---- display clock: only advances the mm:ss readout between the daemon's
  //      heartbeat writes. The daemon owns every real transition.
  Timer {
    interval: 1000
    repeat: true
    running: root.phase !== Model.PHASE_IDLE && (root.running || root.ready)
    onTriggered: root.displayNowMs = Date.now()
  }

  // ---- actions — each runs the matching omarchy-pomodoro verb; the watch on
  //      sessionStore / statsStore / historyStore reflects the result back.
  function togglePause() { root.runVerb("toggle") }
  function skipPhase() { if (root.phase !== Model.PHASE_IDLE) root.runVerb("skip") }
  function resetSession() { root.runVerb("reset") }

  // Sound preview for the settings panel's "test" buttons — not part of the
  // engine (the daemon plays the real transition sounds itself).
  function playSound(transitionKey) {
    guard.run("playSound", function() {
      Quickshell.execDetached(Model.soundPlayCommand(Model.soundForTransition(root.config, transitionKey)))
    })
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
        return JSON.stringify({
          phase: root.phase,
          remainingMs: root.remainingMs,
          running: root.running,
          ready: root.ready,
          elapsedReadyMs: root.elapsedReadyMs,
          focusedTodayMs: root.focusedTodayMs,
          dailyGoalMs: root.dailyGoalMs,
          goalRemainingMs: root.goalRemainingMs,
          goalReached: root.goalRemainingMs <= 0,
          completedToday: root.completedToday,
          streak: root.streak
        })
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

    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 2
      active: pulseTint.active
      level: pulseTint.level
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
