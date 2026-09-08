import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Pulse's bar face: a bell that carries an unread count and reddens / grows a
// pulsing dot when one of the alteringux.* plugins is waiting on you.
//
// This widget owns NO logic. ~/.local/bin/omarchy-pulse is the sole writer of
// alteringux-activity.jsonl / alteringux-attention.json / alteringux-pulse-state.json
// and the only thing that decides what "needs action". The widget watches those
// files, renders the feed through Panel.qml, and turns every user action back
// into an omarchy-pulse verb (or the stored action command).
BarWidget {
  id: root
  moduleName: "alteringux.pulse"

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-pulse"
  readonly property var guard: Kit.BugGuard.create("alteringux.pulse", function (argv) { Quickshell.execDetached(argv) })

  // ---- state, all written by omarchy-pulse ---------------------------
  Kit.Store {
    id: activityStore
    fileName: "alteringux-activity.jsonl"
    watch: true
    pollMs: 4000
    parse: function (raw) { return Model.parseActivity(raw, Date.now()) }
  }
  Kit.Store {
    id: attentionStore
    fileName: "alteringux-attention.json"
    watch: true
    pollMs: 2000
    parse: function (raw) { return Model.parseAttention(raw) }
  }
  Kit.Store {
    id: readStore
    fileName: "alteringux-pulse-state.json"
    watch: true
    pollMs: 3000
    parse: function (raw) { return Model.parseState(raw) }
  }

  readonly property var activityValue: activityStore.value || Model.defaultActivity()
  readonly property var attentionValue: attentionStore.value || Model.defaultAttention()
  readonly property var readValue: readStore.value || Model.defaultState()

  readonly property var summary: Model.summary(root.activityValue, root.attentionValue, root.readValue)
  readonly property string topLevel: root.summary.topLevel
  readonly property int unread: root.summary.unread
  readonly property int needAction: root.summary.needAction

  readonly property string displayText: {
    var head = root.needAction > 0 ? "󰂚" : "󰂜"   // bell / bell-outline
    if (root.unread > 0) head += " " + root.unread
    return head
  }

  readonly property color displayColor: {
    if (root.topLevel === "critical") return Kit.Palette.negative
    if (root.topLevel === "urgent") return Kit.Palette.urgent
    if (root.topLevel === "warning") return Kit.Palette.warning
    if (root.unread > 0) return Kit.Palette.info
    return root.bar ? Color.bar.text : "#ffffff"
  }

  // ---- the CLI bridge ---------------------------------------------
  Process {
    id: actionProc
    running: false
    onExited: { activityStore.reload(); attentionStore.reload(); readStore.reload() }
  }
  function runVerb(args) {
    guard.run("runVerb:" + args.join(" "), function () {
      if (actionProc.running) { Quickshell.execDetached([root.scriptPath].concat(args)); return }
      actionProc.command = [root.scriptPath].concat(args)
      actionProc.running = true
    })
  }

  function markRead() { runVerb(["read"]) }
  function clearAll() { runVerb(["clear", "--all"]) }
  function clearOne(plugin) { if (plugin) runVerb(["clear", String(plugin)]) }
  function actOn(plugin) { if (plugin) runVerb(["act", String(plugin)]) }
  function runAction(cmd) {
    guard.run("runAction", function () {
      var c = String(cmd || "").trim()
      if (c.length) Quickshell.execDetached(["sh", "-lc", c])
    })
  }

  // ---- IPC (Hyprland keybindings) --------------------------------
  IpcHandler {
    target: "alteringux.pulse"

    function toggle(): void { root.togglePanel() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function read(): void { root.markRead() }
    function status(): string {
      return root.guard.call("ipc.status", function () {
        var s = root.summary
        return JSON.stringify({
          unread: s.unread, total: s.total, needAction: s.needAction,
          topLevel: s.topLevel,
          nextAction: s.nextAction ? (s.nextAction.plugin + ": " + s.nextAction.label) : ""
        })
      }, "{}")
    }
  }

  // ---- feed panel -----------------------------------------------
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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    foreground: root.displayColor
    active: root.needAction > 0
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function (b) { root.togglePanel() }

    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.spaceReal(3)
      anchors.rightMargin: Style.spaceReal(2)
      active: root.needAction > 0
      level: root.topLevel.length ? root.topLevel : "warning"
    }
  }
}
