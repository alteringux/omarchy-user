import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Bar widget for the Piper TTS transport. piper-tts publishes
// $XDG_RUNTIME_DIR/piper-tts/current.json for the job that currently holds
// the "one voice at a time" playback queue; this widget shows a speaker icon
// only while that file is present, and its panel drives pause / stop / speed
// / loop / mute through ~/Work/bin/tts-player-ctl. When the reading ends the
// file vanishes and the icon goes with it.
BarWidget {
  id: root
  moduleName: "alteringux.ttsplayer"

  readonly property string home: Quickshell.env("HOME")
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string ctlPath: home + "/Work/bin/tts-player-ctl"
  readonly property string piperTtsPath: home + "/.local/bin/piper-tts"

  // From current.json (event-driven, authoritative for "is anything speaking").
  property bool active: false
  property var state: null
  property int startedAt: 0

  // From the tts-player-ctl status poll (1 s while active).
  property int playedIndex: 0
  property bool paused: false
  property bool muted: false

  // Ticks every second while active so the elapsed read-out and the progress
  // estimate move without waiting on the status poll.
  property int elapsedSeconds: 0

  // Widget-owned config: Loop toggle + Speed multiplier for replays.
  readonly property bool loopEnabled: (configStore.value && configStore.value.loop) === true
  readonly property real speed: (configStore.value && configStore.value.speed > 0) ? configStore.value.speed : 1

  // Last reading we saw, kept so Loop / Restart can re-speak it after the job
  // that produced it has exited and taken current.json with it.
  property var lastReading: null

  readonly property var guard: Kit.BugGuard.create("alteringux.ttsplayer", function (argv) { Quickshell.execDetached(argv) })

  readonly property string icon: {
    if (root.muted) return "\uf026"   // nf-fa-volume_off
    if (root.paused) return "\uf04c"  // nf-fa-pause
    return "\uf0a1"                    // nf-fa-bullhorn
  }

  // ── current.json: appear / change / disappear ─────────────────────────
  Kit.Store {
    id: stateStore
    dir: root.runtimeDir + "/piper-tts/"
    fileName: "current.json"
    watch: true
    pollMs: 1500
    polling: !root.active
    parse: function (raw) { return Model.parseState(raw) }
    onExternallyChanged: function (value) { root.applyState(value) }
  }

  // ── widget-owned Loop + Speed ────────────────────────────────────────
  Kit.Store {
    id: configStore
    fileName: "ttsplayer.json"
    parse: function (raw) { return Model.parseConfig(raw) }
  }

  function applyState(value) {
    guard.run("applyState", function () {
      if (!value) {
        var wasActive = root.active
        var replay = root.lastReading
        root.active = false
        root.state = null
        root.startedAt = 0
        root.elapsedSeconds = 0
        root.playedIndex = 0
        root.paused = false
        root.muted = false
        if (wasActive && root.loopEnabled && replay && replay.text)
          loopTimer.restart()
        return
      }
      root.state = value
      root.startedAt = value.startedAt
      root.lastReading = { tag: value.tag, voice: value.voice, text: value.text }
      root.active = true
      root.recompute()
      if (!statusTimer.running) statusTimer.start()
    })
  }

  function recompute() {
    guard.run("recompute", function () {
      if (!root.active) return
      var now = Math.floor(Date.now() / 1000)
      root.elapsedSeconds = Math.max(0, now - root.startedAt)
    })
  }

  // ── tts-player-ctl status poll ──────────────────────────────────────
  Process {
    id: statusProc
    command: [root.ctlPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  function applyStatus(raw) {
    guard.run("applyStatus", function () {
      var s = Model.parseStatus(raw)
      if (!s.active) {
        // Poll and current.json agree the job is gone — clear even if the
        // file watch has not fired yet.
        if (root.active) root.applyState(null)
        return
      }
      // A status run that was already in flight when we cleared: drop it so it
      // can't re-bump elapsed/chunk state onto an idle widget.
      if (!root.active) return
      root.playedIndex = s.played
      root.paused = s.paused
      root.muted = s.muted
      if (s.elapsed > root.elapsedSeconds) root.elapsedSeconds = s.elapsed
    })
  }

  Timer {
    id: statusTimer
    interval: 1000
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: if (!statusProc.running) statusProc.running = true
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.active
    onTriggered: root.recompute()
  }

  // Small gap before a loop replay so a failed relaunch can't spin, and so
  // the queue lock from the finished job is definitely released.
  Timer {
    id: loopTimer
    interval: 450
    repeat: false
    onTriggered: root.replay()
  }

  // ── actions ────────────────────────────────────────────────────────
  function ctl(verb) {
    guard.run("ctl:" + verb, function () {
      Quickshell.execDetached([root.ctlPath, verb])
    })
  }

  // Flip the local state straight away so the panel toggles feel instant; the
  // 1 s status poll reasserts the real value right after.
  function togglePause() {
    root.paused = !root.paused
    root.ctl(root.paused ? "pause" : "resume")
  }
  function toggleMute() {
    root.muted = !root.muted
    root.ctl(root.muted ? "mute" : "unmute")
  }

  function stopPlayback() {
    guard.run("stopPlayback", function () {
      // Stop defeats Loop — otherwise the reading would immediately restart.
      root.setLoop(false)
      Quickshell.execDetached([root.ctlPath, "stop"])
    })
  }

  function setLoop(on) {
    guard.run("setLoop", function () {
      var v = configStore.value || { loop: false, speed: 1 }
      configStore.value = { loop: !!on, speed: v.speed > 0 ? v.speed : 1 }
      configStore.save()
    })
  }

  function toggleLoop() { root.setLoop(!root.loopEnabled) }

  function setSpeed(mult) {
    guard.run("setSpeed", function () {
      var v = configStore.value || { loop: false, speed: 1 }
      configStore.value = { loop: v.loop === true, speed: (mult > 0 ? mult : 1) }
      configStore.save()
    })
  }

  // Re-speak the last reading. Used by the Loop auto-restart and the panel's
  // "Restart at Nx" button.
  function replay() {
    guard.run("replay", function () {
      var r = root.lastReading
      if (!r || !r.text) return
      Quickshell.execDetached(Model.replayCommand(root.piperTtsPath, r, root.speed))
    })
  }

  // Restart the current reading now at the selected speed (stop, then replay).
  function restartAtSpeed() {
    guard.run("restartAtSpeed", function () {
      var r = root.lastReading
      if (!r || !r.text) return
      Quickshell.execDetached([root.ctlPath, "stop"])
      restartTimer.restart()
    })
  }

  Timer {
    id: restartTimer
    interval: 350
    repeat: false
    onTriggered: root.replay()
  }

  IpcHandler {
    target: "alteringux.ttsplayer"

    function toggle(): void { root.togglePanel() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function pause(): void { root.ctl("pause") }
    function resume(): void { root.ctl("resume") }
    function playpause(): void { root.togglePause() }
    function stop(): void { root.stopPlayback() }
    function mute(): void { root.ctl("mute") }
    function unmute(): void { root.ctl("unmute") }
    function loopToggle(): void { root.toggleLoop() }
    function status(): string {
      return guard.call("ipc.status", function () {
        return JSON.stringify({
          active: root.active,
          paused: root.paused,
          muted: root.muted,
          loop: root.loopEnabled,
          speed: root.speed,
          elapsedSeconds: root.elapsedSeconds,
          chunks: root.state ? root.state.chunks : 0,
          played: root.playedIndex,
          tag: root.state ? root.state.tag : ""
        })
      }, "{}")
    }
  }

  // ── panel wiring (mirrors alteringux.stopwatch) ─────────────────────
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

  onBarChanged: injectPanel()

  // The whole point: no slot in the bar unless something is speaking.
  visible: root.active
  implicitWidth: root.active ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

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

  // Close the panel if it is open when playback ends, so it can't linger with
  // dead controls.
  onActiveChanged: if (!root.active && root.opened) root.close()

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function (b) { root.togglePanel() }
  }
}
