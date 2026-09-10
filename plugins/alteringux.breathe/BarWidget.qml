import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Guided breathing for the bar: shows the live phase and its countdown, hosts
// both breath guides (the fullscreen overlay and the compact one in the panel),
// and exposes IPC so Hyprland keybindings and omarchy-conductor rituals can
// drive a session.
//
// This widget is a thin view. ~/.local/bin/omarchy-breathe and its
// `systemd --user` daemon own every transition and every write to
// breathe-session/-stats/-history.json, so a session keeps running with the
// panel closed and survives the shell restarting
// (../../docs/adr/0006-cli-first-plugins.md). What is computed here is only
// the *frame*: `live` reconstructs the exact breath position from the session's
// savedAtMs between the daemon's heartbeat writes, which is why a smooth orb
// needs no per-second subprocess.
BarWidget {
  id: root
  moduleName: "alteringux.breathe"

  // State lives under ~/.local/state/omarchy/ (via Kit.Store), deliberately NOT
  // inside the plugin's own source directory: that tree is watched by the
  // shell's plugin-file watcher, and writing our own state there triggers a
  // "local plugin changed" reload that tears down an open panel
  // mid-interaction.
  property alias config: configStore.value
  property alias stats: statsStore.value
  property alias history: historyStore.value
  readonly property bool configLoaded: configStore.loaded

  readonly property var session: sessionStore.value || Model.defaultSession()

  // Resolved from the catalogue plus the user's own patterns, so a custom
  // technique drives the guides exactly like a built-in.
  readonly property var technique: Model.techniqueById(root.session.techniqueId, root.config)

  readonly property string state: root.session.state || "IDLE"
  readonly property bool running: root.state === "RUNNING"
  readonly property bool paused: root.state === "PAUSED"
  readonly property bool idle: root.state === "IDLE"
  readonly property bool done: root.state === "DONE"

  // Ticks only while a session is live — an idle plugin costs nothing.
  property double nowMs: Date.now()

  // The whole animated surface of the plugin, recomputed each tick. Both
  // guides read this rather than resolving separately, so they cannot drift.
  readonly property var live: Model.resolve(root.session, root.technique, root.nowMs)

  readonly property color barForeground: root.bar ? Color.bar.text : Color.foreground

  // The technique's semantic colour, resolved once here so the bar fill, the
  // orb and the panel cards all agree.
  readonly property color toneColor: {
    var tone = root.technique ? root.technique.tone : "neutral"
    if (tone === "positive") return Kit.Palette.positive
    if (tone === "negative") return Kit.Palette.negative
    if (tone === "warning") return Kit.Palette.warning
    if (tone === "info") return Kit.Palette.info
    return root.barForeground
  }

  readonly property var guard: Kit.BugGuard.create("alteringux.breathe", function (argv) { Quickshell.execDetached(argv) })

  Kit.Usage { id: usageTracker; pluginId: "alteringux.breathe" }
  readonly property alias usage: usageTracker

  Kit.PulseTint { id: pulseTint; pluginId: "alteringux.breathe" }

  // ---- persistence -----------------------------------------------------
  // config stays widget-owned (defaults, sounds, nudge policy and the user's
  // custom patterns — edited from the panel AND by hand). session / stats /
  // history are written only by omarchy-breathe, so those run in watch mode.
  Kit.Store {
    id: configStore
    fileName: "breathe-config.json"
    parse: function (raw) { return Model.parseConfig(raw) }
    serialize: function (value) { return Model.serializeConfig(value) }
    seedOnCreate: true
  }

  Kit.Store {
    id: sessionStore
    fileName: "breathe-session.json"
    watch: true
    pollMs: 1200
    parse: function (raw) { return Model.parseSession(raw) }
    // Re-baseline the display clock the moment the daemon heartbeats, so the
    // orb never jumps when a write lands mid-phase.
    onExternallyChanged: root.nowMs = Date.now()
  }

  Kit.Store {
    id: statsStore
    fileName: "breathe-stats.json"
    watch: true
    pollMs: 4000
    parse: function (raw) { return Model.parseStats(raw) }
  }

  Kit.Store {
    id: historyStore
    fileName: "breathe-history.json"
    watch: true
    pollMs: 4000
    parse: function (raw) { return Model.parseHistory(raw) }
  }

  // ---- the CLI that owns the session -----------------------------------
  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-breathe"

  Process {
    id: actionProc
    running: false
    onExited: { sessionStore.reload(); statsStore.reload(); historyStore.reload() }
  }

  function runVerb(args) {
    guard.run("runVerb:" + args.join(" "), function () {
      var argv = [root.scriptPath].concat(args)
      // A second action arriving mid-write goes out detached rather than
      // being dropped or clobbering the in-flight one.
      if (actionProc.running) { Quickshell.execDetached(argv); return }
      actionProc.command = argv
      actionProc.running = true
    })
  }

  // Once, on load: let the CLI reconcile a session persisted across a restart
  // or reboot, and respawn the daemon if one is still legitimately live.
  Component.onCompleted: Qt.callLater(function () { Quickshell.execDetached([root.scriptPath, "restore"]) })

  // ---- display clock ---------------------------------------------------
  // Advances the breath position between the daemon's heartbeats. It never
  // transitions anything; the daemon owns every real phase change. 16ms while
  // the overlay is up so the orb animates smoothly, a lazier 250ms when only
  // the bar countdown is watching.
  Timer {
    interval: root.guideVisible ? 16 : 250
    repeat: true
    running: root.running
    onTriggered: root.nowMs = Date.now()
  }

  // ---- actions ---------------------------------------------------------
  function startSession(techniqueId, cycles, silent) {
    var args = ["start"]
    if (techniqueId) args.push(techniqueId)
    if (cycles) args = args.concat(["--cycles", String(cycles)])
    if (silent) args.push("--silent")
    usage.record("start:" + (techniqueId || "default"))
    root.runVerb(args)
  }

  function toggleSession() { usage.record("toggle"); root.runVerb(["toggle"]) }
  function pauseSession()  { usage.record("pause");  root.runVerb(["pause"]) }
  function resumeSession() { usage.record("resume"); root.runVerb(["resume"]) }
  function stopSession()   { usage.record("stop");   root.runVerb(["stop"]) }
  function resetSession()  { usage.record("reset");  root.runVerb(["reset"]) }

  // ---- the fullscreen guide -------------------------------------------
  property bool guideVisible: false

  function showGuide() { usage.record("guide:show"); root.guideVisible = true }
  function hideGuide() { root.guideVisible = false }
  function toggleGuide() { if (root.guideVisible) root.hideGuide(); else root.showGuide() }

  // Raise the overlay when a session actually starts, not when the panel asks
  // for one: a keybind, a conductor ritual and a panel button then all behave
  // identically. Dropping to IDLE (a reset) takes it back down; DONE leaves it
  // up so the completion state can be read.
  onRunningChanged: {
    if (root.running && root.configLoaded && root.config.overlayOnStart) root.guideVisible = true
  }
  onIdleChanged: { if (root.idle) root.guideVisible = false }

  // The overlay is a real layer-shell window, so it exists only while wanted.
  LazyLoader {
    active: root.guideVisible
    Guide { hostWidget: root }
  }

  // ---- config writes ---------------------------------------------------
  // Deep-merges so a patch touching one nudge field cannot drop the others,
  // and customTechniques is never collateral damage of a settings toggle.
  function updateConfig(patch) {
    guard.run("updateConfig", function () {
      if (!configStore.loaded) return
      var next = JSON.parse(JSON.stringify(root.config))
      for (var key in patch) {
        if (key === "nudge" && patch.nudge && typeof patch.nudge === "object") {
          if (!next.nudge) next.nudge = {}
          for (var nk in patch.nudge) next.nudge[nk] = patch.nudge[nk]
        } else {
          next[key] = patch[key]
        }
      }
      root.config = next
      configStore.save()
    })
  }

  function saveCustomTechnique(technique) {
    guard.run("saveCustomTechnique", function () {
      if (!technique || !technique.id) return
      var list = (root.config.customTechniques || []).slice()
      var replaced = false
      for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].id === technique.id) { list[i] = technique; replaced = true; break }
      }
      if (!replaced) list.push(technique)
      root.usage.record("custom:save")
      root.updateConfig({ customTechniques: list })
    })
  }

  function deleteCustomTechnique(id) {
    guard.run("deleteCustomTechnique", function () {
      var list = []
      var stored = root.config.customTechniques || []
      for (var i = 0; i < stored.length; i++) {
        if (stored[i] && stored[i].id !== id) list.push(stored[i])
      }
      root.usage.record("custom:delete")
      root.updateConfig({ customTechniques: list })
    })
  }

  IpcHandler {
    target: "alteringux.breathe"

    function start(techniqueId: string): void { root.startSession(techniqueId, 0, false) }
    function toggle(): void { root.toggleSession() }
    function pause(): void { root.pauseSession() }
    function resume(): void { root.resumeSession() }
    function stop(): void { root.stopSession() }
    function reset(): void { root.resetSession() }
    function guide(): void { root.toggleGuide() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function panel(): void { root.togglePanel() }
    function status(): string {
      return root.guard.call("ipc.status", function () {
        var l = root.live
        return JSON.stringify({
          state: root.state,
          techniqueId: root.session.techniqueId,
          techniqueName: root.technique ? root.technique.name : "",
          phaseKind: l.phaseKind,
          phaseLabel: l.phaseLabel,
          phaseRemainingMs: Math.round(l.phaseRemainingMs),
          cycleIndex: l.cycleIndex,
          cycleCount: l.cycleCount,
          sessionFraction: l.sessionFraction,
          guideVisible: root.guideVisible,
          streak: Model.streakOf(root.stats).current
        })
      }, "{}")
    }
  }

  // ---- Popup panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
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

  // ---- the bar label ---------------------------------------------------
  readonly property string displayText: {
    if (root.idle) return Model.PLUGIN_GLYPH + "  Breathe"
    if (root.done) return Model.PLUGIN_GLYPH + "  Done"

    var l = root.live
    var text = Model.phaseGlyph(l.phaseKind) + "  " + l.phaseLabel
    if (root.configLoaded && root.config.showBarCountdown) {
      // A hold counts UP: during a hold the interesting number is how long you
      // have lasted, not how long is left.
      text += " " + Model.formatClock(l.isHold ? l.phaseElapsedMs : l.phaseRemainingMs)
    }
    if (l.breathCount) text += " " + (l.breathIndex + 1) + "/" + l.breathCount
    else text += "  " + (l.cycleIndex + 1) + "/" + l.cycleCount
    if (root.paused) text += " "   // fa-pause
    return text
  }

  readonly property bool showProgress: !root.idle
  readonly property real progressFraction: root.showProgress ? root.live.sessionFraction : 0

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function (b) { root.togglePanel() }

    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 2
      active: pulseTint.active
      level: pulseTint.level
    }

    // ---- session progress ------------------------------------------
    // A hairline under the label tracking how far through the whole session
    // we are. A paused fill dims rather than disappears, so a stopped session
    // still reads at a glance.
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
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        radius: height / 2
        width: Math.round(track.width * Math.max(0, Math.min(1, root.progressFraction)))
        color: root.done ? Kit.Palette.positive : root.toneColor
        opacity: root.paused ? 0.4 : 1

        // The fraction already advances every tick, so this only needs to
        // smooth the coarser 250ms steps when the overlay is down.
        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.Linear } }
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      }
    }
  }
}
