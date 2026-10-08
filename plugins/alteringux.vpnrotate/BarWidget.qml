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
//     `protonvpn` CLI, verifies the exit IP moved, and publishes
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
  // NetworkManager wifi link state, re-read off the 20 s reconcile timer via a
  // cheap `nmcli` call and parsed by Model.parseWifiState (pure — no fork on
  // this side beyond the one Process). "connected" | "disconnected" |
  // "unavailable" | "unknown". The VPN only connects over wifi: on a wired link
  // the tunnel would still come up but leave the Ethernet IP uncovered, which
  // is the leak the gate below closes. "unknown" (no wifi device / no nmcli) is
  // allowed through — the script is the backstop.
  property string wifiState: "unknown"
  readonly property bool wifiBlocksConnect: root.wifiState === "disconnected" || root.wifiState === "unavailable"
  // Set the instant a button is pressed so the shield reacts before the
  // script has rewritten the file; cleared when the Process exits.
  property string pendingAction: ""
  // Epoch of the last auto-rotate we fired, so a slow script can't make the
  // 1 s tick trigger a second rotate on top of the first.
  property int lastAutoAt: 0

  // "I want a tunnel up" intent, separate from whether one is up right now.
  // Set only when a tunnel is actually *observed* up (a successful connect, or
  // the shell restarting while connected); cleared when the user disconnects.
  // The watchdog uses it to auto-reconnect a tunnel that dropped on its own.
  // It is deliberately NOT set optimistically when a connect is merely
  // attempted — a failed attempt used to leave this armed and the watchdog
  // spinning forever.
  property bool keepUp: false
  // An intentional disconnect is a user command, not a dropped tunnel. Keep
  // this separate from keepUp because a stale connected-state reload can
  // arrive after the disconnect process exits and otherwise re-arm the
  // watchdog before the next tick.
  property bool intentionalDisconnect: false
  // True once a tunnel has been up at least once this session. The kill switch
  // being armed in config is only treated as "keep a tunnel up" intent after
  // this — otherwise a signed-out box with killSwitch:true in its config file
  // reconnect-loops on every shell start.
  property bool everConnected: false
  // Seeded to "now" so the watchdog holds off for its first debounce window
  // after load — lets the startup state read and the kill-switch sync settle
  // before it considers reconnecting.
  property int lastKeepUpAt: Math.floor(Date.now() / 1000)
  // Consecutive watchdog/connect failures. Drives exponential backoff and,
  // past watchdogMaxFails, parks the watchdog until a manual connect or a
  // sign-in. Reset to 0 the moment a tunnel is observed up.
  property int watchdogFails: 0
  readonly property int watchdogMaxFails: 5

  // proton-vpn-cli refuses connect / kill-switch changes while signed out. The
  // watchdog must not spin against that. Probed cheaply by authProc below.
  property bool signedOut: false

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
    error: (root.signedOut && !root.st.connected)
      ? "Not signed in — run: protonvpn signin"
      : root.st.error
  })

  readonly property string icon: Model.iconFor(root.viewState)
  readonly property string label: Model.barLabel(root.viewState)
  readonly property string displayText: root.label.length > 0 ? (root.icon + "  " + root.label) : root.icon

  readonly property int secsToRotate: {
    var s = Model.secondsUntilNextRotation(root.st, root.cfg, root.nowSec)
    return s === null ? -1 : s
  }

  readonly property var guard: Kit.BugGuard.create("alteringux.vpnrotate", function (argv) { Quickshell.execDetached(argv) })

  // Cross-plugin signal: protonvpn-rotate pushes connection errors onto the
  // shared alteringux.pulse attention feed; this widget lights up from that
  // shared state rather than re-deriving the condition itself.
  Kit.PulseTint {
    id: pulseTint
    pluginId: "alteringux.vpnrotate"
  }

  // ── persistence ─────────────────────────────────────────────────────────
  // Status file: the script owns every write (create on first connect, rewrite
  // on each state change, never deleted). watch + a 60 s fallback poll covers
  // FileView's watch-on-create blind spot the same way the other plugins do.
  Kit.Store {
    id: stateStore
    fileName: "vpnrotate.json"
    watch: true
    pollMs: 60000
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

  // Metrics sidecar: server load / protocol / exit latency / tunnel byte
  // counters + rotation tallies. The script owns the writes (`metrics` verb on
  // the poll below, plus connect/rotate for the counters); the widget just
  // reads and derives the live throughput rate from successive samples.
  property var metrics: Model.parseMetrics("")
  property real rxRate: 0
  property real txRate: 0
  property int prevRxBytes: 0
  property int prevTxBytes: 0
  property int prevBytesAt: 0

  Kit.Store {
    id: metricsStore
    fileName: "vpnrotate-metrics.json"
    watch: true
    pollMs: 60000
    polling: true
    parse: function (raw) { return Model.parseMetrics(raw) }
    onExternallyChanged: function (value) { root.applyMetrics(value) }
  }

  function applyMetrics(value) {
    guard.run("applyMetrics", function () {
      var m = value || Model.parseMetrics("")
      if (root.st.connected && m.bytesAt > 0 && root.prevBytesAt > 0 && m.bytesAt !== root.prevBytesAt) {
        root.rxRate = Model.throughput(m.rxBytes, m.bytesAt, root.prevRxBytes, root.prevBytesAt)
        root.txRate = Model.throughput(m.txBytes, m.bytesAt, root.prevTxBytes, root.prevBytesAt)
      } else if (!root.st.connected) {
        root.rxRate = 0; root.txRate = 0
      }
      root.prevRxBytes = m.bytesAt > 0 ? m.rxBytes : 0
      root.prevTxBytes = m.bytesAt > 0 ? m.txBytes : 0
      root.prevBytesAt = m.bytesAt
      root.metrics = m
    })
  }

  // Ask the script to refresh the volatile metrics while a tunnel is up. Each
  // run spawns `protonvpn status` (a Python CLI), so 60 s keeps the box quiet
  // while still giving a live-enough throughput readout; the latency probe
  // inside rate-limits itself further to ~25 s. Only runs while the panel is
  // open or auto-rotate needs the numbers — no point polling for a hidden UI.
  Process {
    id: metricsProc
    command: [root.scriptPath, "metrics"]
    running: false
    onExited: function (code) { metricsStore.reload() }
  }

  Timer {
    interval: 60000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      if (!root.st.connected || metricsProc.running || actionProc.running) return
      if (!root.opened && !root.cfg.autoRotate) return
      // vpnrotate-metrics.json is shared by every instance (top bar renders
      // per screen). Skip if another instance refreshed it < 8s ago.
      if (root.metrics && (Date.now() / 1000 - Number(root.metrics.updated || 0)) < 8) return
      metricsProc.running = true
    }
  }

  function applyState(value) {
    guard.run("applyState", function () {
      var next = value || Model.parseState("")
      // Multiple bar instances watch the same file. File-watch delivery can
      // be out of order, so never let an older connected snapshot overwrite a
      // newer disconnected one and re-arm the keep-up watchdog.
      if (root.st && root.st.updated > 0 && next.updated > 0
          && next.updated < root.st.updated)
        return
      root.st = next
      // The file has caught up with (or overtaken) the optimistic guess.
      if (root.pendingAction !== "" && root.st.action === root.pendingAction)
        root.pendingAction = ""
      // Observed a live tunnel we didn't just tear down → adopt "keep it up"
      // intent, so a later unexpected drop gets auto-reconnected. A shell
      // restart while connected lands here too. This is the ONLY place keepUp
      // and everConnected get set, and a live tunnel clears the failure count.
      if (root.st.connected && root.pendingAction !== "disconnecting"
          && !root.intentionalDisconnect) {
        root.keepUp = true
        root.everConnected = true
        root.watchdogFails = 0
        root.signedOut = false
      }
    })
  }

  // ── the one action runner ───────────────────────────────────────────────
  Process {
    id: actionProc
    running: false
    onExited: function (code) {
      root.pendingAction = ""
      // Exit-code taxonomy from protonvpn-rotate: 0 ok, 1 transient, 2 wifi
      // gate, 3 not possible (signed out / free-plan) — stop auto-retrying.
      if (code === 3) {
        root.signedOut = true
        root.watchdogFails = root.watchdogMaxFails   // park the watchdog until sign-in
      } else if (code === 1) {
        root.watchdogFails = Math.min(root.watchdogFails + 1, root.watchdogMaxFails)
      }
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

  function runConnect() {
    // WiFi-only: don't even spawn the script off WiFi (it would refuse with
    // rc=2 anyway). "unknown" is allowed through — the script is the backstop.
    // Signed out: don't spawn either — the script refuses with rc=3 and the
    // watchdog is already parked, this just avoids the fork.
    if (root.wifiBlocksConnect) return
    if (root.signedOut) return
    // A new explicit connect is the user clearing an intentional disconnect.
    root.intentionalDisconnect = false
    root.runVerb("connect", "connecting")
  }
  function runRotate() { root.runVerb("rotate", "rotating") }
  function runDisconnect() {
    root.intentionalDisconnect = true
    root.keepUp = false
    root.everConnected = false
    root.runVerb("disconnect", "disconnecting")
  }

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
      // shared vpnrotate.json; skip if fresh (another instance just reconciled)
      if (root.st && (Date.now() / 1000 - Number(root.st.updated || 0)) < 15) return
      reconcileProc.running = true
    })
  }

  // ── wifi link probe (feeds the WiFi-only connect gate) ─────────────────
  Process {
    id: wifiProc
    command: ["nmcli", "-t", "-f", "TYPE,STATE", "dev"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyWifi(text)
    }
  }

  function applyWifi(raw) {
    guard.run("applyWifi", function () {
      root.wifiState = Model.parseWifiState(raw)
    })
  }

  function refreshWifi() {
    if (!wifiProc.running) wifiProc.running = true
  }

  // `protonvpn-rotate auth` uses the same bounded CLI wrapper as every other
  // VPN operation, so a stale Proton daemon cannot leave this Process stuck.
  // It still emits the Account line shape consumed by applyAuth below.
  //
  Process {
    id: authProc
    command: [root.scriptPath, "auth"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAuth(text)
    }
  }

  function applyAuth(raw) {
    guard.run("applyAuth", function () {
      var none = /account:\s*'?none'?/i.test(raw)
      var hasAccount = /account:\s*'?[^'\s]/i.test(raw)
      var out = none || !hasAccount
      // A fresh sign-in should let the watchdog try again immediately.
      if (root.signedOut && !out && root.watchdogFails >= root.watchdogMaxFails)
        root.watchdogFails = 0
      root.signedOut = out
    })
  }

  function refreshAuth() {
    if (!authProc.running) authProc.running = true
  }

  Timer {
    interval: 60000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: { root.reconcile(); root.refreshWifi() }
  }

  Timer {
    interval: 60000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refreshAuth()
  }

  // ── auto-rotate ─────────────────────────────────────────────────────────
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      root.nowSec = Math.floor(Date.now() / 1000)
      root.evaluateWatchdog()
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

  // Keep-up watchdog: the user wants a tunnel (a tunnel was observed up this
  // session, or the kill switch is armed *and* we've connected at least once)
  // but the status file says there isn't one and nothing is in flight.
  // Reconnect — with exponential backoff (90 s, 3 m, 6 m, 12 m, 24 m, capped
  // at 1 h) and a hard stop after watchdogMaxFails so a genuinely unreachable
  // free pool, or a signed-out box, is never hammered.
  function evaluateWatchdog() {
    guard.run("evaluateWatchdog", function () {
      if (!(root.keepUp || (root.cfg.killSwitch && root.everConnected))) return
      if (root.st.connected || root.busy) return
      if (root.signedOut) return
      if (root.watchdogFails >= root.watchdogMaxFails) return   // parked; needs a manual connect / sign-in
      if (killSwitchProc.running || killSwitchSyncProc.running || reconcileProc.running) return
      if (root.effectiveAction === "disconnecting") return   // don't fight a user disconnect
      // Off WiFi there's nothing to reconnect to — hold the intent (keepUp
      // stays set) but don't burn the debounce window, so the reconnect fires
      // on the next tick once WiFi is back rather than a backoff later.
      if (root.wifiBlocksConnect) return
      var wait = Math.min(90 * Math.pow(2, root.watchdogFails), 3600)
      if (root.nowSec - root.lastKeepUpAt < wait) return
      root.lastKeepUpAt = root.nowSec
      root.runConnect()
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

  // The underlying `protonvpn` killswitch verb can fail (signed out, older CLI
  // version, missing permission) and protonvpn-rotate reports that with a
  // non-zero exit — execDetached() throws that away, so a failed call used
  // to leave the toggle showing "on" (and its reassuring "no leak" copy)
  // while the tunnel was in fact wide open. Run it as a tracked Process and
  // only persist the config flip once the script confirms it landed.
  property string killSwitchError: ""

  Process {
    id: killSwitchProc
    running: false
    property bool pendingOn: false
    onExited: function (code) {
      if (code === 0) {
        root.killSwitchError = ""
        root.patchConfig({ killSwitch: killSwitchProc.pendingOn })
      } else if (code === 3) {
        root.killSwitchError = "kill switch needs sign-in — run: protonvpn signin"
        root.signedOut = true
      } else {
        root.killSwitchError = "kill switch " + (killSwitchProc.pendingOn ? "on" : "off") + " failed — check protonvpn"
      }
    }
  }

  function runKillSwitch(on) {
    if (killSwitchProc.running) return
    killSwitchProc.pendingOn = !!on
    killSwitchProc.command = [root.scriptPath, "killswitch", on ? "on" : "off"]
    killSwitchProc.running = true
  }

  function setKillSwitch(on) {
    guard.run("setKillSwitch", function () { root.runKillSwitch(on) })
  }
  function toggleKillSwitch() { root.setKillSwitch(!root.cfg.killSwitch) }

  // Startup reconciliation. Probe sign-in first, then let `killswitch sync`
  // reconcile the CLI's real setting to the widget config flag — the script
  // now no-ops that quietly when signed out, so this can't spam the CLI the
  // way the old unconditional `killswitch on` did.
  Process {
    id: killSwitchSyncProc
    command: [root.scriptPath, "killswitch", "sync"]
    running: false
    onExited: function (code) {
      if (code !== 0 && code !== 3)
        root.killSwitchError = "kill switch sync failed — check protonvpn"
      stateStore.reload()
    }
  }

  Component.onCompleted: {
    root.refreshAuth()
    killSwitchSyncProc.running = true
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
          error: root.viewState.error,
          signedOut: root.signedOut,
          wifiState: root.wifiState,
          autoRotate: root.cfg.autoRotate,
          intervalSec: root.cfg.intervalSec,
          killSwitch: root.cfg.killSwitch,
          killSwitchError: root.killSwitchError,
          secondsToRotate: root.secsToRotate,
          load: root.metrics.load,
          protocol: root.metrics.protocol,
          latencyMs: root.metrics.latencyMs,
          rxBytes: root.metrics.rxBytes,
          txBytes: root.metrics.txBytes,
          rxRate: Math.round(root.rxRate),
          txRate: Math.round(root.txRate),
          rotations: root.metrics.rotations,
          rotationsToday: root.metrics.rotationsToday,
          distinctIps: root.metrics.distinctIps,
          ipChangedCount: root.metrics.ipChangedCount,
          failures: root.metrics.failures
        })
      }, "{}")
    }
  }

  // ── panel wiring (mirrors alteringux.stopwatch) ────────────────────────
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  // Refresh the metrics the moment the panel opens so the numbers aren't stale
  // for up to a poll interval (the timer only runs while the panel is open).
  onOpenedChanged: {
    if (root.opened && root.st.connected && !metricsProc.running && !actionProc.running)
      metricsProc.running = true
  }

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
    // Left click opens the panel (unchanged). Right / middle click is a
    // shortcut for the panel's Disconnect button — a one-click teardown
    // without opening the panel first, mirroring score's / ttsplayer's
    // bar-widget shortcuts.
    onPressed: function (b) {
      if ((b === Qt.RightButton || b === Qt.MiddleButton) && root.st.connected && !root.busy) {
        root.runDisconnect()
        return
      }
      root.togglePanel()
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
