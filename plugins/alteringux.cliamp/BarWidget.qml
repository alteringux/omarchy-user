import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Bar widget for the cliamp terminal music player. It owns nothing about
// playback — cliamp does, behind its control socket. This widget only:
//
//   * polls `cliamp status --json` every 2 s for state + now-playing + position
//   * runs `cliamp visstream` while something is playing and paints its 10
//     spectrum bands as a little wave synthesiser (a synthesised travelling
//     sine drifts in its place while paused / stopped, so the strip is never
//     dead)
//   * fires `cliamp toggle|next|prev|stop|...` on click
//
// Hosted on alteringux.bottombar, so it must NOT also be listed in
// shell.json's top-bar layout or its IpcHandler double-registers.
BarWidget {
  id: root
  moduleName: "alteringux.cliamp"

  readonly property string cliampBin: "/usr/bin/cliamp"
  readonly property string termLauncher: "/usr/share/omarchy/bin/omarchy-launch-terminal"

  property var status: Model.emptyStatus()
  property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property real idlePhase: 0
  property bool visCooldown: false

  readonly property bool running: root.status && root.status.running === true
  readonly property bool playing: root.status && root.status.playing === true

  readonly property var guard: Kit.BugGuard.create("alteringux.cliamp", function (argv) { Quickshell.execDetached(argv) })

  Kit.PulseTint {
    id: pulseTint
    pluginId: "alteringux.cliamp"
  }

  readonly property string playGlyph: root.playing ? "" : ""   // nf-fa-pause / play
  readonly property string headGlyph: ""                              // nf-fa-music

  // ── status poll ──────────────────────────────────────────────────────
  Process {
    id: statusProc
    command: [root.cliampBin, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  function applyStatus(raw) {
    guard.run("applyStatus", function () {
      root.status = Model.parseStatus(raw, root.status)
    })
  }

  Timer {
    id: statusTimer
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!statusProc.running) statusProc.running = true
  }

  // A verb just landed — re-poll sooner than the 2 s cadence so the glyph and
  // labels catch up without a visible lag.
  Timer {
    id: quickPoll
    interval: 250
    repeat: false
    onTriggered: if (!statusProc.running) statusProc.running = true
  }
  function pollSoon() { quickPoll.restart() }

  // ── live spectrum: `cliamp visstream` while playing ──────────────────
  Process {
    id: visProc
    command: [root.cliampBin, "visstream", "--fps", "24"]
    running: root.playing && !root.visCooldown
    stdout: SplitParser {
      onRead: function (line) {
        var frame = Model.parseVisFrame(line)
        if (!frame) return
        root.bands = frame.bands
        // The frame's mode is the ground truth for the dropdown; keep it in
        // status so the 2 s poll can't wipe it out.
        if (frame.visualizer && root.status && frame.visualizer !== root.status.visualizer) {
          var s = Object.assign({}, root.status)
          s.visualizer = frame.visualizer
          root.status = s
        }
      }
    }
    // Only throttle a respawn when visstream itself died while we still
    // expect it to be running (root.playing still true) — a genuine
    // crash-loop guard. An ordinary stop/pause already flips `running` to
    // false via the `playing` term above, so it doesn't need this cooldown;
    // unconditionally setting visCooldown here on every exit (the previous
    // behaviour) froze the spectrum on idle bands for up to 1.5s after any
    // stop/pause immediately followed by resume, even though cliamp itself
    // was already back to playing.
    onExited: if (root.playing) root.visCooldown = true
  }

  Timer {
    id: visCooldownTimer
    interval: 1500
    repeat: false
    running: root.visCooldown
    onTriggered: root.visCooldown = false
  }

  // ── synthesised idle drift when nothing is streaming ─────────────────
  Timer {
    interval: 66
    repeat: true
    running: root.visible && !root.playing
    onTriggered: {
      root.idlePhase += 0.16
      root.bands = Model.idleBands(root.idlePhase, root.running ? 0.16 : 0.10)
    }
  }

  // ── position ticker (smooth progress between polls) ──────────────────
  Timer {
    interval: 1000
    repeat: true
    running: root.playing
    onTriggered: {
      var s = root.status
      if (s && s.total > 0 && s.position < s.total) {
        var next = Object.assign({}, s)
        next.position = s.position + 1
        root.status = next
      }
    }
  }

  // ── actions ─────────────────────────────────────────────────────────
  function runVerb(args) {
    guard.run("verb:" + args.join(" "), function () {
      Quickshell.execDetached([root.cliampBin].concat(args))
    })
  }

  function launch() {
    guard.run("launch", function () {
      Quickshell.execDetached([root.termLauncher, "cliamp"])
    })
  }

  function playPause() {
    if (!root.running) { root.launch(); return }
    root.runVerb(["toggle"]); root.pollSoon()
  }
  function next() { if (root.running) { root.runVerb(["next"]); root.pollSoon() } }
  function prev() { if (root.running) { root.runVerb(["prev"]); root.pollSoon() } }
  function stopPlayback() { if (root.running) { root.runVerb(["stop"]); root.pollSoon() } }
  function seekTo(seconds) { if (root.running) { root.runVerb(["seek", String(Math.round(seconds))]); root.pollSoon() } }
  function nudgeVolume(db) { if (root.running) root.runVerb(["volume", String(db)]) }
  function toggleShuffle() { if (root.running) { root.runVerb(["shuffle"]); root.pollSoon() } }
  function cycleRepeat() { if (root.running) { root.runVerb(["repeat"]); root.pollSoon() } }
  // Optimistically record the picked mode: the status JSON carries no
  // visualizer field, and visstream (the only other source) is stopped while
  // paused, so without this the next poll's parseStatus carries the *old*
  // mode forward and the dropdown snaps back. Mirrors visProc's frame handler.
  function setVis(name) {
    if (!root.running || !name) return
    if (root.status && root.status.visualizer !== name) {
      var s = Object.assign({}, root.status)
      s.visualizer = name
      root.status = s
    }
    root.runVerb(["vis", name])
    root.pollSoon()
  }

  // ── IPC ─────────────────────────────────────────────────────────────
  IpcHandler {
    target: "alteringux.cliamp"

    function toggle(): void { root.togglePanel() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function playpause(): void { root.playPause() }
    function play(): void { root.runVerb(["play"]); root.pollSoon() }
    function pause(): void { root.runVerb(["pause"]); root.pollSoon() }
    function next(): void { root.next() }
    function prev(): void { root.prev() }
    function stop(): void { root.stopPlayback() }
    function shuffle(): void { root.toggleShuffle() }
    function repeat(): void { root.cycleRepeat() }
    function vis(name: string): void { root.setVis(name) }
    function launch(): void { root.launch() }
    function status(): string {
      return root.guard.call("ipc.status", function () {
        var s = root.status || {}
        return JSON.stringify({
          running: s.running === true,
          state: s.state,
          title: s.title,
          artist: s.artist,
          position: s.position,
          total: s.total,
          visualizer: s.visualizer,
          shuffle: s.shuffle,
          repeat: s.repeat,
          streaming: visProc.running
        })
      }, "{}")
    }
  }

  // ── panel wiring (same contract as alteringux.score / .ttsplayer) ────
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = strip
    if ("hostWidget" in target) target.hostWidget = root
  }

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

  implicitWidth: strip.implicitWidth
  implicitHeight: root.barSize

  // ── the bar strip ───────────────────────────────────────────────────
  Row {
    id: strip
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    BarIconButton {
      id: prevBtn
      bar: root.bar
      text: ""          // nf-fa-step_backward
      tooltipText: "Previous"
      dimmed: !root.running
      onPressed: function (b) { root.prev() }
    }

    BarIconButton {
      id: playBtn
      bar: root.bar
      text: root.running ? root.playGlyph : ""
      tooltipText: root.running ? (root.playing ? "Pause" : "Play") : "Launch cliamp"
      onPressed: function (b) {
        if (b === Qt.MiddleButton) root.stopPlayback()
        else if (b === Qt.RightButton) root.togglePanel()
        else root.playPause()
      }
    }

    BarIconButton {
      id: nextBtn
      bar: root.bar
      text: ""          // nf-fa-step_forward
      tooltipText: "Next"
      dimmed: !root.running
      onPressed: function (b) { root.next() }
    }

    // Wave synthesiser + now-playing. Clicking anywhere here opens the panel.
    Item {
      id: vizSlot
      anchors.verticalCenter: parent.verticalCenter
      width: vizRow.width + titleText.width + (titleText.visible ? Style.space(8) : 0) + Style.space(10)
      height: root.barSize

      Row {
        id: vizRow
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Style.space(4)
        spacing: Style.spaceReal(2)
        readonly property real maxHeight: Math.round(root.barSize * 0.5)

        Repeater {
          model: Model.BAND_COUNT
          delegate: Rectangle {
            required property int index
            width: Style.spaceReal(2.5)
            radius: width / 2
            color: root.bar ? root.bar.barForeground : Color.bar.text
            opacity: root.playing ? 0.92 : 0.4
            anchors.verticalCenter: parent.verticalCenter
            height: Math.max(Style.spaceReal(2),
                             (root.bands[index] || 0) * vizRow.maxHeight)
            Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
          }
        }
      }

      Text {
        id: titleText
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: vizRow.right
        anchors.leftMargin: Style.space(8)
        visible: root.running && text.length > 0
        text: root.status.label || ""
        color: root.bar ? root.bar.barForeground : Color.bar.text
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        width: Math.min(implicitWidth, Style.space(170))
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: function (mouse) {
          if (mouse.button === Qt.MiddleButton) root.next()
          else root.togglePanel()
        }
        // Scroll the bar strip to nudge volume up/down without opening the
        // panel — mirrors the panel's own +/-2 dB buttons.
        onWheel: function (wheel) {
          if (!root.running) return
          root.nudgeVolume(wheel.angleDelta.y > 0 ? 2 : -2)
          wheel.accepted = true
        }
      }

      Kit.AttentionDot {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 2
        active: pulseTint.active
        level: pulseTint.level
      }
    }
  }
}
