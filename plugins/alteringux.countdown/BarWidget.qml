import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget for the `omarchy-countdown` spoken-countdown script. The
// script (a systemd --user unit) owns the actual timing and speech; this
// widget only reads its JSON state file to display remaining time and
// offers a panel to start/cancel it, mirroring alteringux.pomodoro's
// bar-widget + click-panel shape.
BarWidget {
  id: root
  moduleName: "alteringux.countdown"

  readonly property string home: Quickshell.env("HOME")
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string statePath: runtimeDir + "/omarchy-countdown/state"
  readonly property string scriptPath: home + "/.local/bin/omarchy-countdown"
  // Same "pluginDir" convention as alteringux.stocks / alteringux.dashboard,
  // so bundled helper scripts under bin/ are referenced from one place.
  readonly property string pluginDir: home + "/.config/omarchy/plugins/alteringux.countdown"
  readonly property string logScript: pluginDir + "/bin/omarchy-countdown-log"

  property bool active: false
  property int endEpoch: 0
  property string label: ""
  property int remainingSeconds: 0

  readonly property string displayText: {
    if (!root.active) return "⏱ Countdown"
    var time = Model.formatRemaining(root.remainingSeconds)
    return root.label.length > 0 ? ("⏱ " + time + " " + root.label) : ("⏱ " + time)
  }

  function applyState(raw) {
    var state = Model.parseState(raw)
    if (!state) {
      root.active = false
      root.endEpoch = 0
      root.label = ""
      return
    }
    root.endEpoch = state.end_epoch
    root.label = state.label || ""
    root.active = true
    root.recompute()
  }

  function recompute() {
    if (!root.active) return
    var now = Math.floor(Date.now() / 1000)
    root.remainingSeconds = root.endEpoch - now
    if (root.remainingSeconds <= 0) {
      root.active = false
      root.remainingSeconds = 0
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

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.recompute()
  }

  // FileView.watchChanges only tracks the inode of a file that exists when
  // the widget is built. `omarchy-countdown` creates the state file *after*
  // the bar is already running (and removes it on cancel/finish), so the
  // inode watch is usually dead and onLoaded never fires for a countdown
  // started later. Poll for the file while nothing is running; stops itself
  // once applyState() flips root.active. Cheap: a stat every 2s while idle.
  Timer {
    interval: 2000
    repeat: true
    running: !root.active
    onTriggered: stateFile.reload()
  }

  function startCountdown(mode, duration, labelText, loop) {
    var args = [root.scriptPath]
    if (mode === Model.MODE_SECONDS) args.push("--seconds")
    args.push(String(duration))
    args.push(labelText)
    if (loop) args.push("--loop")
    Quickshell.execDetached(args)

    // Fire-and-forget usage log, feeding Panel.qml's frequency-ranked
    // one-tap presets. Never on the critical path for starting a timer.
    Quickshell.execDetached([root.logScript, mode, String(duration), labelText])
  }

  function cancelCountdown() {
    Quickshell.execDetached([root.scriptPath, "cancel"])
  }

  IpcHandler {
    target: "alteringux.countdown"

    function toggle(): void { root.togglePanel() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function cancel(): void { root.cancelCountdown() }
    function status(): string {
      return JSON.stringify({ active: root.active, remainingSeconds: root.remainingSeconds, label: root.label })
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
