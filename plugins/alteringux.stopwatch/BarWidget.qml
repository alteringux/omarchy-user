import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

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
  readonly property string statePath: runtimeDir + "/omarchy-stopwatch/state"
  readonly property string historyPath: home + "/.local/state/omarchy/stopwatch-history.json"
  readonly property string scriptPath: home + "/.local/bin/omarchy-stopwatch"
  readonly property string unitName: "omarchy-stopwatch.service"

  property bool active: false
  property int startEpoch: 0
  property string label: ""
  property int intervalMinutes: 5
  property int elapsedSeconds: 0
  property var historyData: ({ version: 1, sessions: [] })
  // Frozen copy of historyData as it stood *before* the current session
  // started. The CLI's `cancel` appends the finished session to the history
  // file and only then removes the state file, so by the time this widget
  // reacts to the state file vanishing, historyData may already include the
  // session we're about to summarise — comparing it against an average that
  // contains itself. Snapshotting on the idle→active edge (and keeping the
  // snapshot fresh while idle) gives resetState() a clean baseline.
  property var historySnapshot: ({ version: 1, sessions: [] })
  // Set when a session just ended, comparing it against past sessions with
  // the same label. Self-improving in the sense that the baseline it's
  // judged against keeps shifting as more sessions accumulate.
  property string lastSessionSummary: ""

  readonly property string displayText: {
    if (!root.active) return "⏱ Stopwatch"
    var time = Model.formatElapsed(root.elapsedSeconds)
    return root.label.length > 0 ? ("⏱ " + time + " " + root.label) : ("⏱ " + time)
  }

  function applyState(raw) {
    var state = Model.parseState(raw)
    if (!state) {
      root.resetState()
      return
    }
    // Idle -> active edge: freeze the baseline this session will be judged
    // against, before the CLI can fold this session into historyData.
    if (!root.active) root.historySnapshot = root.historyData
    root.startEpoch = state.start_epoch
    root.label = state.label || ""
    root.intervalMinutes = state.interval_minutes || 5
    root.active = true
    root.recompute()
    // Delay the first liveness check: right after startStopwatch() writes
    // this same state, systemd may not have finished marking the unit
    // active yet, and checking too early would self-heal a stopwatch that
    // just started.
    initialLivenessTimer.restart()
  }

  function resetState() {
    if (root.active) {
      var avg = Model.historyAverage(root.historySnapshot, root.label)
      root.lastSessionSummary = avg !== null ? Model.formatDelta(root.elapsedSeconds, avg) : ""
    }
    root.active = false
    root.startEpoch = 0
    root.label = ""
  }

  function recompute() {
    if (!root.active) return
    var now = Math.floor(Date.now() / 1000)
    root.elapsedSeconds = Math.max(0, now - root.startEpoch)
  }

  // The state file only tells us a stopwatch was started, not that it's
  // still running: if the systemd unit dies without going through
  // cancelStopwatch() (crash, OOM kill, manual `systemctl stop`), the file
  // is left behind and the bar would otherwise count up forever against a
  // unit that no longer exists. Poll unit liveness the same way the CLI's
  // own `cmd_status` does, and self-heal by clearing the stale file.
  function checkLiveness() {
    if (!root.active || unitCheckProc.running) return
    unitCheckProc.running = true
  }

  function clearStaleState() {
    root.resetState()
    Quickshell.execDetached(["rm", "-f", root.statePath])
  }

  Process {
    id: unitCheckProc
    command: ["systemctl", "--user", "is-active", "--quiet", root.unitName]
    running: false
    onExited: function(exitCode) {
      if (exitCode !== 0) root.clearStaleState()
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("")
    onFileChanged: reload()
  }

  // Loaded independently of the cancel that triggers resetState(), so the
  // just-finished session is compared against sessions logged *before* it
  // rather than racing the CLI's own write to this same file.
  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    printErrors: false
    // While idle, keep the pre-session snapshot tracking the real history so
    // the next session starts from an up-to-date baseline. Once active, the
    // snapshot is frozen (see applyState) and this only updates historyData.
    onLoaded: {
      root.historyData = Model.parseHistory(text())
      if (!root.active) root.historySnapshot = root.historyData
    }
    onLoadFailed: {
      root.historyData = Model.parseHistory("")
      if (!root.active) root.historySnapshot = root.historyData
    }
    onFileChanged: reload()
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.recompute()
  }

  Timer {
    interval: 10000
    repeat: true
    running: root.active
    onTriggered: root.checkLiveness()
  }

  // FileView.watchChanges only tracks the inode of a file that exists when
  // the widget is built. The state file is created by `omarchy-stopwatch`
  // *after* the bar is already running (and is rm'd on cancel, then
  // recreated on the next start), so the inode watch is usually dead and
  // onLoaded never fires for a stopwatch started later. Poll for the file
  // while we think nothing is running; stops itself once applyState() flips
  // root.active. Cheap: a stat every 2s, only while idle.
  Timer {
    interval: 2000
    repeat: true
    running: !root.active
    onTriggered: stateFile.reload()
  }

  Timer {
    id: initialLivenessTimer
    interval: 2000
    repeat: false
    onTriggered: root.checkLiveness()
  }

  function startStopwatch(intervalMinutes, labelText) {
    Quickshell.execDetached([root.scriptPath, String(intervalMinutes), labelText])
  }

  function cancelStopwatch() {
    Quickshell.execDetached([root.scriptPath, "cancel"])
  }

  IpcHandler {
    target: "alteringux.stopwatch"

    function toggle(): void { root.togglePanel() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function cancel(): void { root.cancelStopwatch() }
    function status(): string {
      return JSON.stringify({ active: root.active, elapsedSeconds: root.elapsedSeconds, label: root.label })
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
