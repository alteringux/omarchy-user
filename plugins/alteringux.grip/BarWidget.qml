import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Grip's bar face: an open/overdue task counter that reddens with age and
// pulses while a prompt is pending. Left-click opens the triage panel.
//
// This widget owns NO logic. ~/.local/bin/omarchy-grip (+ its systemd --user
// daemon) is the sole writer of grip-state.json / grip-tasks.json and the only
// thing that decides when a check-in is due or things have escalated to a
// takeover. The widget watches those files, renders the current prompt through
// Prompt.qml, and turns every user action back into an omarchy-grip verb.
BarWidget {
  id: root
  moduleName: "alteringux.grip"

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-grip"
  readonly property var guard: Kit.BugGuard.create("alteringux.grip", function (argv) { Quickshell.execDetached(argv) })

  // Per-plugin usage analytics — every user action is recorded so the panel
  // can reorder its nudge buttons toward what this user actually reaches for.
  Kit.Usage { id: usage; pluginId: "alteringux.grip" }

  // ---- state, all written by omarchy-grip -----------------------------
  Kit.Store {
    id: tasksStore
    fileName: "grip-tasks.json"
    watch: true
    pollMs: 3000
    parse: function (raw) { return Model.parseTasks(raw) }
  }
  Kit.Store {
    id: stateStore
    fileName: "grip-state.json"
    watch: true
    pollMs: 1500
    parse: function (raw) { return Model.parseState(raw) }
  }
  Kit.Store {
    id: configStore
    fileName: "grip-config.json"
    watch: true
    pollMs: 8000
    parse: function (raw) { return Model.parseConfig(raw) }
  }

  readonly property var tasksValue: tasksStore.value || Model.defaultTasks()
  readonly property var stateValue: stateStore.value || Model.defaultState()
  readonly property var configValue: configStore.value || Model.defaultConfig()

  // A slow clock so "overdue" and the age-based colour re-evaluate without a
  // file change.
  property double nowMs: Date.now()
  Timer { interval: 20000; repeat: true; running: true; onTriggered: root.nowMs = Date.now() }

  readonly property var summary: Model.summary(root.tasksValue, root.stateValue, root.nowMs)
  readonly property string promptKind: (root.stateValue.prompt && root.stateValue.prompt.kind) ? root.stateValue.prompt.kind : ""

  readonly property string displayText: {
    var s = root.summary
    if (s.tone === "off") return "󰔐"                       // nf-md-bell_off
    if (s.tone === "paused") return "󰒲 " + s.open           // nf-md-sleep
    if (s.tone === "clear") return "󰄺"                      // nf-md-check_all
    var head = "󰔲 " + s.open                               // nf-md-clipboard_text
    if (s.overdue > 0) head += "  󰔣 " + s.overdue          // nf-md-alert
    return head
  }

  readonly property color displayColor: {
    var s = root.summary
    if (s.tone === "prompt") return Kit.Palette.urgent
    if (s.tone === "overdue") return Kit.Palette.negative
    if (s.tone === "paused" || s.tone === "off") return Kit.Palette.faint
    return root.bar ? Color.bar.text : "#ffffff"
  }

  // ---- the CLI bridge -----------------------------------------------
  Process {
    id: actionProc
    running: false
    onExited: { stateStore.reload(); tasksStore.reload() }
  }
  function runVerb(args) {
    guard.run("runVerb:" + args.join(" "), function () {
      if (actionProc.running) { Quickshell.execDetached([root.scriptPath].concat(args)); return }
      actionProc.command = [root.scriptPath].concat(args)
      actionProc.running = true
    })
  }

  function forceCheckin() { usage.record("checkin"); runVerb(["checkin"]) }
  function pauseFor(minutes) { usage.record("pause"); runVerb(["pause", String(Math.max(1, Math.round(minutes))) + "m"]) }
  function resume() { usage.record("resume"); runVerb(["resume"]) }
  function setEnabled(on) { usage.record(on ? "enable" : "disable"); runVerb([on ? "on" : "off"]) }
  function addTask(text) { if (text && text.trim().length) { usage.record("add"); runVerb(["add", text.trim()]) } }
  function completeTask(id) { if (id) { usage.record("complete"); runVerb(["done", String(id)]) } }
  function dropTask(id) { if (id) { usage.record("drop"); runVerb(["drop", String(id)]) } }

  function ackDismiss() { usage.record("dismiss"); runVerb(["ack", root.promptKind || "checkin"]) }
  function ackSnooze(minutes) { usage.record("snooze"); runVerb(["ack", root.promptKind || "checkin", "--snooze", String(Math.max(1, Math.round(minutes))) + "m"]) }
  function ackDid(id) { usage.record("did"); runVerb(["ack", root.promptKind || "checkin", "--did", String(id)]) }
  function ackHear() { usage.record("ack"); runVerb(["ack", "takeover"]) }

  // ---- IPC (Hyprland keybindings) ----------------------------------
  IpcHandler {
    target: "alteringux.grip"

    function checkin(): void { root.forceCheckin() }
    function pause(minutes: string): void { root.pauseFor(parseInt(minutes) || 30) }
    function resume(): void { root.resume() }
    function toggle(): void { root.togglePanel() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function status(): string {
      return root.guard.call("ipc.status", function () {
        var s = root.summary
        return JSON.stringify({
          enabled: root.stateValue.enabled, prompt: root.promptKind,
          open: s.open, overdue: s.overdue, tone: s.tone,
          usage: usage.topActions(6)
        })
      }, "{}")
    }
  }

  // ---- triage panel ------------------------------------------------
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { usage.record("panel"); if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { usage.record("panel"); if (panelLoader.item) panelLoader.item.toggle() }

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

  // The intrusion surface lives in its own layer-shell window, instantiated
  // only while a prompt is up (mirrors newsbar's add-source modal). It reads
  // everything from this widget via `hostWidget`.
  LazyLoader {
    active: root.promptKind !== ""
    Prompt { hostWidget: root }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    foreground: root.displayColor
    active: root.promptKind !== ""
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function (b) { root.togglePanel() }

    // A pulsing dot pinned to the corner while a prompt waits unanswered.
    // Shared shape — see Kit.AttentionDot / alteringux.pulse.
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
