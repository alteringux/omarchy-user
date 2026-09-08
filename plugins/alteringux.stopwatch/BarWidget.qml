import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Bar widget for the `omarchy-stopwatch` spoken-stopwatch script. The
// script (a systemd --user unit) owns the actual timing and speech; this
// widget only reads its JSON state file to display elapsed time and
// offers a panel to start/cancel it. Deliberately separate from
// alteringux.countdown: a stopwatch has no end time, so it doesn't fit
// that plugin's {end_epoch, total_seconds} state shape.
BarWidget {
  id: root
  moduleName: "alteringux.stopwatch"

  readonly property string home: Quickshell.env("HOME")
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string scriptPath: home + "/.local/bin/omarchy-stopwatch"
  readonly property string unitName: "omarchy-stopwatch.service"

  property bool active: false
  property int startEpoch: 0
  property string label: ""
  property int intervalMinutes: 5
  property int elapsedSeconds: 0
  // Mirrors the CLI's voice switch (voiceStore). True = announcements are
  // muted for the running stopwatch; the systemd unit keeps counting.
  property bool voiceMuted: false
  // Mirrors the CLI's bell switch (chimeStore). True = the running stopwatch
  // rings a bell at each interval instead of speaking the elapsed time.
  property bool chimeMode: false
  // Epoch the CLI's `pause` froze the stopwatch at (0 = running). While set,
  // the timing unit is stopped and elapsedSeconds is held at this point.
  property int pausedEpoch: 0
  readonly property bool paused: root.pausedEpoch > 0
  // Persisted "ring a bell instead of speaking" default for the next stopwatch
  // (stopwatch-config.json, alongside the announce interval). The CLI seeds the
  // live chime marker from this on start.
  readonly property bool chimeDefault: !!(configStore.value && configStore.value.chime)
  property alias historyData: historyStore.value
  // Last announce-interval the user picked in the panel, persisted to
  // stopwatch-config.json so it survives a shell restart / reboot and becomes
  // the starting value for the next stopwatch. A *running* stopwatch's own
  // interval is restored independently by the CLI's `resume`.
  readonly property int lastInterval: Model.sanitizeInterval(configStore.value && configStore.value.interval_minutes)
  // Frozen copy of historyData as it stood *before* the current session
  // started. The CLI's `cancel` appends the finished session to the history
  // file and only then removes the state file, so by the time this widget
  // reacts to the state file vanishing, historyData may already include the
  // session we're about to summarise — comparing it against an average that
  // contains itself. Snapshotting on the idle→active edge (and keeping the
  // snapshot fresh while idle) gives resetState() a clean baseline.
  property var historySnapshot: ({ version: 1, sessions: [] })
  // True once historySnapshot holds a real read of historyStore for the
  // *current* active session (as opposed to the placeholder default above).
  // Needed because stateStore and historyStore load independently: if the
  // shell starts with a stopwatch already running, applyState's idle->active
  // edge can fire before historyStore's own first read completes, seeding
  // historySnapshot from the empty placeholder. historyStore.onExternallyChanged
  // still fires for that first real read (Kit.Store always emits once), but its
  // own `!root.active` guard would otherwise ignore it because active flipped
  // true already — this flag lets it land the real snapshot anyway, once.
  property bool historySnapshotReady: false
  // Set when a session just ended, comparing it against past sessions with
  // the same label. Self-improving in the sense that the baseline it's
  // judged against keeps shifting as more sessions accumulate.
  property string lastSessionSummary: ""
  // "N sessions today, HH:MM total" for the idle panel — hidden (empty) once
  // nothing's been logged yet today. Recomputes whenever historyData changes;
  // a session ending is what actually moves this number, so a same-day
  // midnight rollover with no new session leaves it stale until the next one
  // (matches the coarse-refresh precedent elsewhere in this widget).
  readonly property string todaySummary: Model.formatTodaySummary(Model.historyToday(root.historyData, Date.now()))

  readonly property string displayText: {
    if (!root.active) return "  Stopwatch"
    var time = Model.formatElapsed(root.elapsedSeconds)
    return root.label.length > 0 ? ("  " + time + " " + root.label) : ("  " + time)
  }

  // Trailing state glyphs so the bar shows how the running stopwatch is set up
  // without opening the panel: pause bars while paused, muted-speaker while the
  // voice is off, bell while it rings instead of speaking.
  readonly property string pausedBadge: (root.active && root.paused) ? "  \uf04c" : ""
  readonly property string voiceBadge: (root.active && root.voiceMuted) ? "  \uf026" : ""
  readonly property string chimeBadge: (root.active && root.chimeMode && !root.voiceMuted) ? "  \uf0f3" : ""

  readonly property var guard: Kit.BugGuard.create("alteringux.stopwatch", function(argv) { Quickshell.execDetached(argv) })

  // Called by stateStore each time the CLI's state file appears / changes /
  // vanishes. `state` is Model.parseState()'s result — null means "no stopwatch
  // running" (missing / empty / malformed file).
  function applyState(state) {
    guard.run("applyState", function() {
      if (!state) {
        // A vanished / briefly-unreadable state file while we believe a
        // stopwatch is running could be a real cancel or crash, or just a
        // transient read landing during the CLI's own write. Let the
        // authoritative unit check arbitrate rather than flip straight to idle.
        if (root.active) root.checkLiveness()
        else root.resetState()
        return
      }
      // Idle -> active edge: freeze the baseline this session will be judged
      // against, before the CLI can fold this session into historyData.
      // historySnapshotReady only latches true once that baseline actually
      // came from a completed historyStore read (see the property comment);
      // false here lets the store's own first-load event still land the real
      // snapshot below if this fires before that read completes.
      if (!root.active) {
        root.historySnapshot = root.historyData
        root.historySnapshotReady = historyStore.loaded
      }
      root.startEpoch = state.start_epoch
      root.label = state.label || ""
      root.intervalMinutes = state.interval_minutes || 5
      root.pausedEpoch = Model.pausedEpochOf(state)
      root.active = true
      root.recompute()
      // Delay the first liveness check: right after startStopwatch() writes
      // this same state, systemd may not have finished marking the unit
      // active yet, and checking too early would self-heal a stopwatch that
      // just started.
      initialLivenessTimer.restart()
    })
  }

  function resetState() {
    guard.run("resetState", function() {
      if (root.active) {
        var avg = Model.historyAverage(root.historySnapshot, root.label)
        root.lastSessionSummary = avg !== null ? Model.formatDelta(root.elapsedSeconds, avg) : ""
      }
      root.active = false
      root.startEpoch = 0
      root.label = ""
      root.elapsedSeconds = 0
      root.pausedEpoch = 0
      root.historySnapshotReady = false
    })
  }

  // Persist the panel's announce-interval so the next stopwatch (this session
  // or after a reboot) defaults to it instead of the hard-coded 5. Merges into
  // the existing config so it doesn't clobber the persisted chime default.
  function rememberInterval(minutes) {
    guard.run("rememberInterval", function() {
      var cur = configStore.value || {}
      cur.interval_minutes = Model.sanitizeInterval(minutes)
      configStore.value = cur
      configStore.save()
    })
  }

  // Persist "ring a bell instead of speaking" as the default the CLI seeds the
  // next stopwatch's chime marker from. Merges, like rememberInterval().
  // Flushes immediately (not the debounced save()) so the file is on disk
  // before the user can click Start and the CLI reads it.
  function rememberChimeDefault(on) {
    guard.run("rememberChimeDefault", function() {
      var cur = configStore.value || {}
      cur.chime = !!on
      configStore.value = cur
      configStore.flush()
    })
  }

  function recompute() {
    guard.run("recompute", function() {
      if (!root.active) return
      // Paused: the timing unit is stopped, so hold the counter at the point
      // the CLI froze it rather than letting wall-clock time run on.
      if (root.paused) {
        root.elapsedSeconds = Math.max(0, root.pausedEpoch - root.startEpoch)
        return
      }
      var now = Math.floor(Date.now() / 1000)
      root.elapsedSeconds = Math.max(0, now - root.startEpoch)
    })
  }

  // The state file only tells us a stopwatch was started, not that it's
  // still running: if the systemd unit dies without going through
  // cancelStopwatch() (crash, OOM kill, manual `systemctl stop`), the file
  // is left behind and the bar would otherwise count up forever against a
  // unit that no longer exists. Poll unit liveness the same way the CLI's
  // own `cmd_status` does, and self-heal by clearing the stale file.
  function checkLiveness() {
    // While paused the timing unit is intentionally stopped, so a "unit not
    // active" result is expected and must not self-heal the state away.
    if (!root.active || root.paused || unitCheckProc.running) return
    unitCheckProc.running = true
  }

  function clearStaleState() {
    guard.run("clearStaleState", function() {
      root.resetState()
      Quickshell.execDetached(["rm", "-f", stateStore.path])
    })
  }

  Process {
    id: unitCheckProc
    command: ["systemctl", "--user", "is-active", "--quiet", root.unitName]
    running: false
    onExited: function(exitCode) {
      if (exitCode !== 0) root.clearStaleState()
    }
  }

  // The CLI owns $XDG_RUNTIME_DIR/omarchy-stopwatch/state: it creates it on
  // start, rm's it on cancel, recreates it on the next start. watch + a 2 s
  // idle poll (only while we think nothing's running — FileView's inode watch
  // is dead against the recreated file) tracks all of that. parse() returns
  // null for "no state", which applyState() reads as idle.
  Kit.Store {
    id: stateStore
    dir: root.runtimeDir + "/omarchy-stopwatch/"
    fileName: "state"
    watch: true
    pollMs: 2000
    // Poll even while running: FileView's inode watch can go stale against a
    // file the CLI deletes on `cancel` and recreates on the next start (or that
    // `resume` recreates at boot), so a running -> idle edge would otherwise
    // wait on the 5 s liveness timer, or be missed entirely. A null read while
    // active is routed through checkLiveness(), not straight to reset.
    polling: true
    parse: function (raw) { return Model.parseState(raw) }
    onExternallyChanged: function (value) { root.applyState(value) }
  }

  // Read independently of the cancel that triggers resetState(), so a
  // just-finished session is compared against sessions logged *before* it
  // rather than racing the CLI's own write to this same file.
  Kit.Store {
    id: historyStore
    fileName: "stopwatch-history.json"
    watch: true
    parse: function (raw) { return Model.parseHistory(raw) }
    // While idle, keep the pre-session snapshot tracking real history so the
    // next session starts from an up-to-date baseline. Once active, the
    // snapshot is frozen (see applyState) UNLESS it hasn't actually landed a
    // real read yet — the load-order race applyState's comment describes —
    // in which case this first real read is that snapshot, taken once.
    onExternallyChanged: function (value) {
      if (!root.active || !root.historySnapshotReady) {
        root.historySnapshot = value
        root.historySnapshotReady = true
      }
    }
  }

  // Panel config: the last announce-interval the user chose. Plugin-owned
  // (only rememberInterval() writes it), so no watch — just load-on-start.
  Kit.Store {
    id: configStore
    fileName: "stopwatch-config.json"
    parse: function (raw) { return Model.parseConfig(raw) }
  }

  // The CLI's voice switch: `omarchy-stopwatch mute` drops a marker file here,
  // `unmute` / `cancel` / a fresh start remove it. watch + idle poll for the
  // same watch-on-create reason as stateStore: the file is created and deleted
  // repeatedly across a session, so FileView's inode watch goes stale.
  Kit.Store {
    id: voiceStore
    dir: root.runtimeDir + "/omarchy-stopwatch/"
    fileName: "voice-muted"
    watch: true
    pollMs: 2000
    parse: function (raw) { return Model.parseVoiceMuted(raw) }
    onExternallyChanged: function (value) { root.voiceMuted = value }
  }

  // The CLI's bell switch: `omarchy-stopwatch chime` drops a marker file here,
  // `unchime` / `cancel` / a start that isn't chime-seeded remove it. Same
  // watch + idle poll as voiceStore — the file is created and deleted across a
  // session, so FileView's inode watch goes stale.
  Kit.Store {
    id: chimeStore
    dir: root.runtimeDir + "/omarchy-stopwatch/"
    fileName: "chime"
    watch: true
    pollMs: 2000
    parse: function (raw) { return Model.parseChimeMode(raw) }
    onExternallyChanged: function (value) { root.chimeMode = value }
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.recompute()
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.active && !root.paused
    onTriggered: root.checkLiveness()
  }

  Timer {
    id: initialLivenessTimer
    interval: 2000
    repeat: false
    onTriggered: root.checkLiveness()
  }

  function startStopwatch(intervalMinutes, labelText) {
    guard.run("startStopwatch", function() {
      Quickshell.execDetached([root.scriptPath, String(intervalMinutes), labelText])
    })
  }

  function cancelStopwatch() {
    guard.run("cancelStopwatch", function() {
      Quickshell.execDetached([root.scriptPath, "cancel"])
    })
  }

  // Voice on/off for a *running* stopwatch. The CLI owns the marker file and
  // speak() re-checks it every interval, so the switch lands on the next
  // announcement with no systemd restart. Set voiceMuted optimistically so
  // the panel switch throws immediately; voiceStore reasserts the real value.
  function setVoiceMuted(muted) {
    guard.run("setVoiceMuted", function() {
      root.voiceMuted = muted
      Quickshell.execDetached([root.scriptPath, muted ? "mute" : "unmute"])
    })
  }

  function toggleVoice() {
    root.setVoiceMuted(!root.voiceMuted)
  }

  // Bell-vs-voice for a *running* stopwatch. Like the voice switch, the CLI
  // owns the marker file and speak() re-checks it each interval, so the change
  // lands on the next announcement with no systemd restart. Optimistic set so
  // the panel toggle flips immediately; chimeStore reasserts the real value.
  function setChimeMode(on) {
    guard.run("setChimeMode", function() {
      root.chimeMode = on
      Quickshell.execDetached([root.scriptPath, on ? "chime" : "unchime"])
    })
  }

  function toggleChime() {
    root.setChimeMode(!root.chimeMode)
  }

  // Freeze / thaw a running stopwatch via the CLI. `pause` stops the timing
  // unit and stamps paused_epoch into the state file (stateStore then flips
  // root.paused); `unpause` relaunches from a shifted start so elapsed time
  // continues where it left off.
  function pauseStopwatch() {
    guard.run("pauseStopwatch", function() {
      Quickshell.execDetached([root.scriptPath, "pause"])
    })
  }

  function resumeStopwatch() {
    guard.run("resumeStopwatch", function() {
      Quickshell.execDetached([root.scriptPath, "unpause"])
    })
  }

  IpcHandler {
    target: "alteringux.stopwatch"

    function toggle(): void { root.togglePanel() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function cancel(): void { root.cancelStopwatch() }
    // Set the persisted default announce-interval (what the panel starts on).
    function setInterval(minutes: int): void { root.rememberInterval(minutes) }
    function mute(): void { root.setVoiceMuted(true) }
    function unmute(): void { root.setVoiceMuted(false) }
    function voiceToggle(): void { root.toggleVoice() }
    function chime(): void { root.setChimeMode(true) }
    function unchime(): void { root.setChimeMode(false) }
    function chimeToggle(): void { root.toggleChime() }
    function pause(): void { root.pauseStopwatch() }
    function unpause(): void { root.resumeStopwatch() }
    function status(): string {
      return guard.call("ipc.status", function() {
        return JSON.stringify({ active: root.active, elapsedSeconds: root.elapsedSeconds, label: root.label, paused: root.paused, voiceMuted: root.voiceMuted, chimeMode: root.chimeMode, lastInterval: root.lastInterval })
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
    text: root.displayText + root.pausedBadge + root.voiceBadge + root.chimeBadge
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      root.togglePanel()
    }
  }
}
