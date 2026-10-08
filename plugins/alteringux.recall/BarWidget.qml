import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Recall's bar face: a due-review counter that reddens with backlog, plus a
// takeover indicator while a lesson/quiz prompt is up. Left-click opens the
// deck panel.
//
// This widget owns NO logic. ~/.local/bin/omarchy-recall (+ its systemd
// --user daemon) is the sole writer of recall-cards.json / recall-state.json
// / recall-config.json and the only thing that decides when a lesson is
// ready, a check-in is due, or things have escalated to a takeover. The
// widget watches those files, renders the current prompt through Prompt.qml,
// and turns every user action back into an omarchy-recall verb.
BarWidget {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.recall"

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-recall"
  readonly property var guard: Kit.BugGuard.create("alteringux.recall", function (argv) { Quickshell.execDetached(argv) })
  property string actionStatus: ""
  property bool actionFailed: false
  property int actionGeneration: 0
  property string choicesError: ""
  signal actionFeedback(string message)
  signal choicesFeedback(string message)
  function reportActionStatus(message, failed) {
    actionStatus = message
    actionFailed = failed === true
    actionFeedback(message)
  }
  function reportChoicesError(message) {
    choicesError = message
    choicesFeedback(message)
  }

  // ---- state, all written by omarchy-recall ---------------------------
  Kit.Store {
    id: cardsStore
    fileName: "recall-cards.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseCards(raw) }
  }
  Kit.Store {
    id: stateStore
    fileName: "recall-state.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseState(raw) }
  }
  Kit.Store {
    id: configStore
    fileName: "recall-config.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseConfig(raw) }
  }

  readonly property var cardsValue: cardsStore.value || Model.defaultCards()
  readonly property var stateValue: stateStore.value || Model.defaultState()
  readonly property var configValue: configStore.value || Model.defaultConfig()

  // A slow clock so the due count re-evaluates without a file change.
  property double nowMs: Date.now()
  Timer { interval: 20000; repeat: true; running: true; onTriggered: root.nowMs = Date.now() }

  readonly property int dueCount: Model.dueQuizzes(root.cardsValue.cards, root.nowMs).length
  readonly property string promptKind: (root.stateValue.prompt && root.stateValue.prompt.kind) ? root.stateValue.prompt.kind : ""

  readonly property string displayText: {
    if (!root.configValue.enabled) return "󰧑"
    if (root.nowMs < root.stateValue.pauseUntilMs) return "󰧑 󰏤"
    if (root.promptKind === "lesson") return "󰧑 󰂽"
    if (root.dueCount === 0) return "󰧑 ✓"
    return "󰧑 " + root.dueCount
  }

  readonly property color displayColor: {
    if (root.promptKind === "takeover") return _webPalette.barNegative
    if (root.promptKind !== "") return _webPalette.barUrgent
    if (!root.configValue.enabled || root.nowMs < root.stateValue.pauseUntilMs) return _webPalette.barMuted
    return root.bar ? _webPalette.barForeground : _webPalette.foreground
  }

  // ---- the CLI bridge -----------------------------------------------
  Process {
    id: actionProc
    property int feedbackGeneration: -1
    property bool feedbackStarted: false
    running: false
    onStarted: feedbackStarted = true
    onRunningChanged: {
      if (!running && !feedbackStarted && feedbackGeneration === root.actionGeneration) {
        feedbackGeneration = -1
        root.reportActionStatus("Recall helper unavailable. Check ~/.local/bin/omarchy-recall is installed and executable.", true)
      }
    }
    onExited: function(code, status) {
      stateStore.reload(); cardsStore.reload(); configStore.reload()
      var generation = feedbackGeneration
      feedbackGeneration = -1
      if (generation !== root.actionGeneration) return
      root.reportActionStatus(code === 0 && status === 0
        ? "Recall command completed."
        : "Recall command failed (exit " + code + "). Try again; check the Recall helper if it persists.", code !== 0 || status !== 0)
    }
  }
  function runVerb(args) {
    guard.run("runVerb:" + args.join(" "), function () {
      root.actionGeneration++
      try {
        var cmd = [root.scriptPath].concat(args)
        if (actionProc.running || actionProc.feedbackGeneration >= 0) {
          Quickshell.execDetached(cmd)
          root.reportActionStatus("Request sent. Completion cannot be confirmed while another Recall command is running.", false)
          return
        }
        actionProc.feedbackGeneration = root.actionGeneration
        actionProc.feedbackStarted = false
        actionProc.command = cmd
        root.actionFailed = false
        root.actionStatus = "Working…"
        root.actionFeedback(root.actionStatus)
        actionProc.running = true
      } catch (error) {
        actionProc.feedbackGeneration = -1
        root.reportActionStatus("Recall request could not be sent. Try again; check the Recall helper if it persists.", true)
        throw error
      }
    })
  }

  // ---- multiple-choice clue lookup (read-only, doesn't touch state) --
  property var lastChoices: []
  property string lastChoicesForId: ""

  Process {
    id: choicesProc
    property bool started: false
    property bool attempted: false
    running: false
    onStarted: started = true
    onRunningChanged: {
      if (running) { started = false; attempted = true }
      else if (attempted && !started) {
        attempted = false
        root.reportChoicesError("Clue options unavailable. Check ~/.local/bin/omarchy-recall is installed and executable.")
      }
    }
    onExited: function(code, status) {
      started = false
      attempted = false
      if (code !== 0 || status !== 0)
        root.reportChoicesError("Clue options unavailable (exit " + code + ").")
    }
    property string forId: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data
        try { data = JSON.parse(text || "{}") } catch (e) {
          root.reportChoicesError("Clue options could not be read. Try again.")
          return
        }
        if (!data || !Array.isArray(data.options)) {
          root.reportChoicesError("No clue options are available for this card.")
          return
        }
        // forId must land before lastChoices: Prompt.qml's onLastChoicesChanged
        // fires synchronously off the assignment below and reads forId in the
        // same tick, so the old order left it comparing against the stale id.
        root.lastChoicesForId = choicesProc.forId
        root.lastChoices = Array.isArray(data.options) ? data.options : []
      }
    }
  }
  function fetchChoices(id) {
    if (!id || choicesProc.running) return
    root.choicesError = ""
    choicesProc.forId = String(id)
    choicesProc.command = [root.scriptPath, "choices", String(id), "4"]
    choicesProc.running = true
  }

  function setEnabled(on) { runVerb([on ? "on" : "off"]) }
  function forceCheckin() { runVerb(["checkin"]) }
  function pauseFor(minutes) { runVerb(["pause", String(Math.max(1, Math.round(minutes))) + "m"]) }
  function resume() { runVerb(["resume"]) }

  function addQuiz(front, back, category) {
    if (!front || !front.trim().length || !back || !back.trim().length) return
    runVerb(["add-quiz", front.trim(), back.trim(), "--category", category || "custom"])
  }
  function dropCard(id) { if (id) runVerb(["drop", String(id)]) }
  function gradeCard(id, gradeName) { if (id) runVerb(["grade", String(id), String(gradeName)]) }
  function lessonSeen(id) { if (id) runVerb(["lesson-seen", String(id)]) }
  function setLessonSlide(idx) { runVerb(["lesson-progress", String(Math.max(0, Math.round(idx)))]) }

  function ackLesson() { runVerb(["ack", "lesson"]) }
  function ackReview(kind, engaged) {
    var args = ["ack", kind]
    if (engaged) args.push("--engaged")
    runVerb(args)
  }
  function ackSnooze(kind, minutes) {
    runVerb(["ack", kind, "--snooze", String(Math.max(1, Math.round(minutes))) + "m"])
  }

  // ---- IPC (Hyprland keybindings) ------------------------------------
  IpcHandler {
    target: "alteringux.recall"

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
          dueCount: root.dueCount, streakDays: root.stateValue.streakDays
        })
      }, "{}")
    }
  }

  // ---- deck panel -----------------------------------------------------
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

  // The intrusion surface lives in its own layer-shell window, instantiated
  // only while a prompt is up (mirrors alteringux.grip's Prompt).
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
