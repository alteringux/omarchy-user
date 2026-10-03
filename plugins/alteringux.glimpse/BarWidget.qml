import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Glimpse's bar face: a due-review counter that reddens with backlog, plus a
// live-round indicator while an exercise overlay is up. Left-click opens the
// panel.
//
// This widget owns NO logic. ~/.local/bin/omarchy-glimpse (+ its systemd
// --user daemon) is the sole writer of glimpse-cards.json / glimpse-state.json
// / glimpse-config.json, fetches + alters the scene images, and decides when
// a scheduled review is due or has escalated. The widget watches those files,
// runs the round through Overlay.qml, and turns every user action back into
// an omarchy-glimpse verb.
BarWidget {
  id: root
  moduleName: "alteringux.glimpse"

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-glimpse"
  readonly property var guard: Kit.BugGuard.create("alteringux.glimpse", function (argv) { Quickshell.execDetached(argv) })

  // ---- state, all written by omarchy-glimpse ------------------------------
  Kit.Store {
    id: cardsStore
    fileName: "glimpse-cards.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseCards(raw) }
  }
  Kit.Store {
    id: stateStore
    fileName: "glimpse-state.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseState(raw) }
  }
  Kit.Store {
    id: configStore
    fileName: "glimpse-config.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseConfig(raw) }
  }

  readonly property var cardsValue: cardsStore.value || Model.defaultCards()
  readonly property var stateValue: stateStore.value || Model.defaultState()
  readonly property var configValue: configStore.value || Model.defaultConfig()

  property double nowMs: Date.now()
  Timer { interval: 20000; repeat: true; running: true; onTriggered: root.nowMs = Date.now() }

  readonly property int dueCount: Model.dueCards(root.cardsValue.cards, root.nowMs).length
  readonly property string promptKind: (root.stateValue.prompt && root.stateValue.prompt.kind) ? root.stateValue.prompt.kind : ""
  readonly property bool roundActive: root.stateValue.round !== null && root.stateValue.round !== undefined
  readonly property bool overlayUp: root.promptKind !== "" || root.roundActive

  readonly property string displayText: {
    if (!root.configValue.enabled) return "👁"
    if (root.nowMs < root.stateValue.pauseUntilMs) return "👁 ⏸"
    if (root.roundActive) return "👁 ●"
    if (root.promptKind !== "") return "👁 !"
    if (root.dueCount === 0) return "👁 ✓"
    return "👁 " + root.dueCount
  }

  readonly property color displayColor: {
    if (root.promptKind === "takeover") return Kit.Palette.negative
    if (root.overlayUp) return Kit.Palette.urgent
    if (!root.configValue.enabled || root.nowMs < root.stateValue.pauseUntilMs) return Kit.Palette.faint
    return root.bar ? Color.bar.text : "#ffffff"
  }

  // ---- the CLI bridge --------------------------------------------------
  // A verb fired while one was already running used to fall back to
  // Quickshell.execDetached() — a second, untracked `omarchy-glimpse`
  // process racing the first one's read-modify-write of glimpse-state.json
  // (and never reloading the stores on its own completion, so its effect
  // could sit unreflected until the next poll). Grading a round twice in a
  // quick double-click is the easy way to hit this: two concurrent `finish`
  // calls scoring the same round against the SM-2 schedule. Queue instead —
  // one pending slot, last call wins, always serialized through actionProc.
  readonly property bool busy: actionProc.running
  property var pendingVerb: null

  Process {
    id: actionProc
    running: false
    onExited: {
      stateStore.reload(); cardsStore.reload(); configStore.reload()
      if (root.pendingVerb) {
        var next = root.pendingVerb
        root.pendingVerb = null
        root.runVerb(next)
      }
    }
  }
  function runVerb(args) {
    guard.run("runVerb:" + args.join(" "), function () {
      if (actionProc.running) { root.pendingVerb = args; return }
      actionProc.command = [root.scriptPath].concat(args)
      actionProc.running = true
    })
  }

  function setEnabled(on) { runVerb([on ? "on" : "off"]) }
  function startDrill() { runVerb(["next-round", "--drill"]) }
  function startScheduled(cardId) { runVerb(cardId ? ["next-round", "--scheduled", "--card", String(cardId)] : ["next-round", "--scheduled"]) }
  function finishRound(gradeName, accuracy, clicksJson) {
    var args = ["finish", String(gradeName), String(accuracy)]
    if (clicksJson) { args.push("--clicks"); args.push(clicksJson) }
    runVerb(args)
  }
  function abandonRound() { runVerb(["abandon"]) }
  function ackPrompt(kind, snoozeMin) {
    var args = ["ack", kind]
    if (snoozeMin) { args.push("--snooze"); args.push(String(Math.max(1, Math.round(snoozeMin))) + "m") }
    runVerb(args)
  }
  function forceCheckin() { runVerb(["checkin"]) }
  function pauseFor(minutes) { runVerb(["pause", String(Math.max(1, Math.round(minutes))) + "m"]) }
  function resume() { runVerb(["resume"]) }
  function dropCard(id) { if (id) runVerb(["drop", String(id)]) }
  function fetchScenes(n) { runVerb(["fetch", String(Math.max(1, Math.round(n || 4)))]) }
  function promoteScenes(n) { runVerb(["promote", String(Math.max(1, Math.round(n || 2)))]) }

  // ---- IPC (Hyprland keybindings) -----------------------------------------
  IpcHandler {
    target: "alteringux.glimpse"

    function drill(): void { root.startDrill() }
    function checkin(): void { root.forceCheckin() }
    function pause(minutes: string): void { root.pauseFor(parseInt(minutes) || 30) }
    function resume(): void { root.resume() }
    function toggle(): void { root.togglePanel() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function status(): string {
      return root.guard.call("ipc.status", function () {
        return JSON.stringify({
          enabled: root.configValue.enabled, prompt: root.promptKind,
          round: root.roundActive, dueCount: root.dueCount,
          drillLevel: root.stateValue.session ? root.stateValue.session.level : 3,
          streakDays: root.stateValue.streakDays,
          busy: root.busy
        })
      }, "{}")
    }
  }

  // ---- panel --------------------------------------------------------------
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  // The exercise surface lives in its own layer-shell window, instantiated
  // only while a prompt or a live round is up (mirrors alteringux.recall).
  LazyLoader {
    active: root.overlayUp
    Overlay { hostWidget: root }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    foreground: root.displayColor
    active: root.overlayUp
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function (b) { root.togglePanel() }

    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.spaceReal(3)
      anchors.rightMargin: Style.spaceReal(2)
      active: root.promptKind !== ""
      level: root.promptKind === "takeover" ? "critical" : "urgent"
    }
  }
}
