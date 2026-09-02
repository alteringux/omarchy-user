import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Bar widget for a Proton VPN free-tier connection with an IP rotator.
//
// Division of labour, same shape as alteringux.ttsplayer / .stopwatch:
//   ~/.local/bin/protonvpn-rotate  owns the mechanism — it drives the official
//     `protonvpn-cli`, verifies the exit IP moved, and publishes
//     ~/.local/state/omarchy/vpnrotate.json.
//   this widget  owns the policy — connect / disconnect / rotate-now buttons,
//     and an auto-rotate loop on a user-set interval. Auto-rotate is a plain
//     QML timer keyed off the status file's lastRotate epoch, so restarting
//     the shell mid-cycle doesn't reset the clock and there's no systemd unit
//     to babysit.
BarWidget {
  id: root
  moduleName: "alteringux.vpnrotate"

  readonly property string home: Quickshell.env("HOME")
  readonly property string scriptPath: home + "/.local/bin/protonvpn-rotate"

  // Latest parsed status file. Model.parseState() always returns a full shape.
  property var st: Model.parseState("")
  // Wall clock in seconds, ticked once a second — drives the countdown and the
  // auto-rotate check without waiting on a file write.
  property int nowSec: Math.floor(Date.now() / 1000)
  // Set the instant a button is pressed so the shield reacts before the
  // script has rewritten the file; cleared when the Process exits.
  property string pendingAction: ""
  // Epoch of the last auto-rotate we fired, so a slow script can't make the
  // 1 s tick trigger a second rotate on top of the first.
  property int lastAutoAt: 0

  readonly property var cfg: configStore.value || Model.defaultConfig()

  readonly property string effectiveAction: root.pendingAction !== "" ? root.pendingAction : root.st.action
  readonly property bool busy: root.effectiveAction === "connecting"
    || root.effectiveAction === "rotating"
    || root.effectiveAction === "disconnecting"
    || actionProc.running

  readonly property var viewState: ({
    connected: root.st.connected,
    action: root.effectiveAction,
    country: root.st.country,
    error: root.st.error
  })

  readonly property string icon: Model.iconFor(root.viewState)
  readonly property string label: Model.barLabel(root.viewState)
  readonly property string displayText: root.label.length > 0 ? (root.icon + "  " + root.label) : root.icon

  readonly property int secsToRotate: {
    var s = Model.secondsUntilNextRotation(root.st, root.cfg, root.nowSec)
    return s === null ? -1 : s
  }

  readonly property var guard: Kit.BugGuard.create("alteringux.vpnrotate", function (argv) { Quickshell.execDetached(argv) })

  // ── persistence ─────────────────────────────────────────────────────────
  // Status file: the script owns every write (create on first connect, rewrite
  // on each state change, never deleted). watch + a 2 s idle poll covers
  // FileView's watch-on-create blind spot the same way the other plugins do.
  Kit.Store {
    id: stateStore
    fileName: "vpnrotate.json"
    watch: true
    pollMs: 2000
    polling: true
    parse: function (raw) { return Model.parseState(raw) }
    onExternallyChanged: function (value) { root.applyState(value) }
  }

  // Widget-owned policy: { autoRotate, intervalSec, killSwitch }.
  Kit.Store {
    id: configStore
    fileName: "vpnrotate-config.json"
    seedOnCreate: true
    parse: function (raw) { return Model.parseConfig(raw) }
    serialize: function (v) { return JSON.stringify(Model.parseConfig(JSON.stringify(v)), null, 2) + "\n" }
  }

  function applyState(value) {
    guard.run("applyState", function () {
      root.st = value || Model.parseState("")
      // The file has caught up with (or overtaken) the optimistic guess.
      if (root.pendingAction !== "" && root.st.action === root.pendingAction)
        root.pendingAction = ""
    })
  }

  // ── the one action runner ───────────────────────────────────────────────
  Process {
    id: actionProc
    running: false
    onExited: function (code) {
      root.pendingAction = ""
      // Nudge a re-read in case the write landed a hair before the watch armed,
      // then reconcile against `protonvpn status` so a failed / partial verb
      // still leaves the widget showing reality.
      stateStore.reload()
      root.reconcile()
    }
  }

  function runVerb(verb, optimistic) {
    guard.run("runVerb:" + verb, function () {
      if (actionProc.running) return
      root.pendingAction = optimistic
      actionProc.command = [root.scriptPath, verb]
      actionProc.running = true
    })
  }

  function runConnect() { root.runVerb("connect", "connecting") }
  function runRotate() { root.runVerb("rotate", "rotating") }
  function runDisconnect() { root.runVerb("disconnect", "disconnecting") }

  // ── reconcile with ground truth ────────────────────────────────────────
  // The status file is only written by this widget's own verbs, so anything
  // that changes the tunnel out of band — a bare `protonvpn connect`, a
  // dropped WireGuard link, the GTK app, another terminal — would otherwise
  // leave the shield stale. `protonvpn-rotate refresh` re-derives the file
  // from `protonvpn status`; it's cheap unless the state actually moved.
  Process {
    id: reconcileProc
    command: [root.scriptPath, "refresh"]
    running: false
    onExited: function (code) { stateStore.reload() }
  }

  function reconcile() {
    guard.run("reconcile", function () {
      if (actionProc.running || reconcileProc.running) return
      reconcileProc.running = true
    })
  }

  Timer {
    interval: 20000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.reconcile()
  }

  // ── auto-rotate ─────────────────────────────────────────────────────────
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      root.nowSec = Math.floor(Date.now() / 1000)
      root.evaluateAutoRotate()
    }
  }

  function evaluateAutoRotate() {
    guard.run("evaluateAutoRotate", function () {
      if (!root.cfg.autoRotate) return
      if (!root.st.connected || root.busy) return
      if (root.secsToRotate > 0) return
      if (root.nowSec - root.lastAutoAt < 30) return   // debounce a slow script
      root.lastAutoAt = root.nowSec
      root.runRotate()
    })
  }

  // ── config setters (single writer, so no setter drops another's field) ──
  function patchConfig(patch) {
    guard.run("patchConfig", function () {
      var v = Model.parseConfig(JSON.stringify(root.cfg))
      for (var k in patch) v[k] = patch[k]
      configStore.value = Model.parseConfig(JSON.stringify(v))
      configStore.save()
    })
  }

  function setAutoRotate(on) { root.patchConfig({ autoRotate: !!on }) }
  function toggleAutoRotate() { root.setAutoRotate(!root.cfg.autoRotate) }
  function setIntervalSec(sec) { root.patchConfig({ intervalSec: Model.clampInterval(sec) }) }

  function setKillSwitch(on) {
    guard.run("setKillSwitch", function () {
      root.patchConfig({ killSwitch: !!on })
      Quickshell.execDetached([root.scriptPath, "killswitch", on ? "on" : "off"])
    })
  }
  function toggleKillSwitch() { root.setKillSwitch(!root.cfg.killSwitch) }

  Component.onCompleted: {
    if (root.cfg.killSwitch)
      Quickshell.execDetached([root.scriptPath, "killswitch", "on"])
  }

  // ── IPC (read-only status + the same verbs the panel exposes) ───────────
  IpcHandler {
    target: "alteringux.vpnrotate"

    function toggle(): void { root.togglePanel() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function connect(): void { root.runConnect() }
    function disconnect(): void { root.runDisconnect() }
    function rotate(): void { root.runRotate() }
    function autoOn(): void { root.setAutoRotate(true) }
    function autoOff(): void { root.setAutoRotate(false) }
    function status(): string {
      return guard.call("ipc.status", function () {
        return JSON.stringify({
          connected: root.st.connected,
          action: root.effectiveAction,
          server: root.st.server,
          exitIp: root.st.exitIp,
          country: root.st.country,
          city: root.st.city,
          org: root.st.org,
          since: root.st.since,
          lastRotate: root.st.lastRotate,
          error: root.st.error,
          autoRotate: root.cfg.autoRotate,
          intervalSec: root.cfg.intervalSec,
          killSwitch: root.cfg.killSwitch,
          secondsToRotate: root.secsToRotate
        })
      }, "{}")
    }
  }

  // ── panel wiring (mirrors alteringux.stopwatch) ────────────────────────
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

  implicitWidth: button.implicitWidth
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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function (b) { root.togglePanel() }
  }
}
