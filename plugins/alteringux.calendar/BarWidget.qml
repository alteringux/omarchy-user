import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Birthdays, holidays, events and time blocks — a thin view over
// ~/.local/bin/omarchy-calendar (docs/adr/0006-cli-first-plugins.md). The CLI
// is the sole writer of calendar-state.json and the ICS export that
// alteringux.agenda already watches for timed-event lead-time notifications;
// this widget only reads calendar-state.json and calls CLI verbs.
BarWidget {
  id: root
  moduleName: "alteringux.calendar"

  readonly property string icon: ""   // nf-fa-calendar

  property alias state: stateStore.value
  readonly property bool stateLoaded: stateStore.loaded

  readonly property string displayText: root.stateLoaded ? Model.widgetLabel(root.state) : ""
  readonly property int todayCount: root.stateLoaded ? Model.todayBadgeCount(root.state) : 0
  readonly property bool hasTodaySurprise: root.stateLoaded
    && ((root.state.today.birthdays || []).length > 0 || (root.state.today.holidays || []).length > 0)

  readonly property var guard: Kit.BugGuard.create("alteringux.calendar", function (argv) { Quickshell.execDetached(argv) })
  Kit.Usage { id: usage; pluginId: "alteringux.calendar" }

  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-calendar"

  property string lastError: ""
  property int dayRequestSerial: 0
  property int dayProcessSerial: 0
  property string dayProcessDate: ""
  property string pendingDay: ""

  function tail(text, fallback) {
    var lines = String(text || "").split("\n").map(function (line) { return line.trim() }).filter(Boolean)
    return lines.length > 0 ? lines[lines.length - 1] : fallback
  }
  property var pendingVerb: []

  Kit.Store {
    id: stateStore
    fileName: "calendar-state.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseState(raw) }
  }

  // ---- verb runner: one serialising Process, with visible failures -------
  Process {
    id: actionProc
    running: false
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function (exitCode) {
      root.lastError = exitCode === 0 ? "" : ("Calendar command failed: " + root.tail(actionErr.text, "exit " + exitCode))
      stateStore.reload()
      if (root.pendingVerb.length > 0) {
        var queued = root.pendingVerb
        actionProc.command = queued[0]
        root.pendingVerb = queued.slice(1)
        actionProc.running = true
      }
    }
  }

  function runVerb(args) {
    guard.run("runVerb:" + args.join(" "), function () {
      var cmd = [root.scriptPath].concat(args)
      if (actionProc.running) { root.pendingVerb = root.pendingVerb.concat([cmd]); return }
      root.lastError = ""
      actionProc.command = cmd
      actionProc.running = true
    })
  }

  function refreshState() { root.runVerb(["status", "--write"]) }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshState()
  }

  // ---- month + day data for the panel (pull, not watched) ---------------
  property string currentMonth: ""
  property var monthCells: []

  property string pendingMonth: ""
  property string monthProcessMonth: ""
  property var dayDetail: ({ date: "", events: [], birthdays: [], holidays: [] })

  Process {
    id: monthProc
    running: false
    stderr: StdioCollector { id: monthErr; waitForEnd: true }
    stdout: StdioCollector {
      id: monthOut
      waitForEnd: true
      onStreamFinished: guard.run("monthProc.onStreamFinished", function () {
        var mj = Model.parseMonthJson(monthOut.text)
        if (mj.month === root.monthProcessMonth && root.currentMonth === mj.month) {
          root.monthCells = Model.monthGridCells(mj, root.state.date || "")
        }
        // Keep the title and grid paired after rapid navigation. Do not retry
        // an empty response forever when the helper failed.
        if (root.currentMonth && mj.month && root.currentMonth !== mj.month) root.loadMonth(root.currentMonth)
      })
    }
    onExited: function (exitCode) {
      root.lastError = exitCode === 0 ? "" : ("Calendar month failed: " + root.tail(monthErr.text, "exit " + exitCode))
      if (root.pendingMonth) {
        var nextMonth = root.pendingMonth
        root.pendingMonth = ""
        root.loadMonth(nextMonth)
      }
    }
  }

  function loadMonth(ym) {
    guard.run("loadMonth", function () {
      root.currentMonth = ym
      if (monthProc.running) {
        root.pendingMonth = ym
        return
      }
      root.lastError = ""
      root.monthProcessMonth = ym
      monthProc.command = [root.scriptPath, "month", ym, "--json"]
      monthProc.running = true
    })
  }

  Process {
    id: dayProc
    running: false
    stderr: StdioCollector { id: dayErr; waitForEnd: true }
    stdout: StdioCollector {
      id: dayOut
      waitForEnd: true
      onStreamFinished: guard.run("dayProc.onStreamFinished", function () {
        var detail = Model.parseDayJson(dayOut.text)
        if (Model.shouldApplyDayResult(root.dayProcessSerial, root.dayRequestSerial, detail.date, root.dayProcessDate)) {
          root.dayDetail = detail
        }
      })
    }
    onExited: function (exitCode) {
      if (exitCode !== 0) root.lastError = "Calendar day failed: " + root.tail(dayErr.text, "exit " + exitCode)
      if (root.pendingDay) root.startDayRequest()
    }
  }

  function startDayRequest() {
    if (!root.pendingDay || dayProc.running) return
    var ymd = root.pendingDay
    root.pendingDay = ""
    root.dayProcessDate = ymd
    root.dayProcessSerial = root.dayRequestSerial
    root.lastError = ""
    dayProc.command = [root.scriptPath, "day", ymd, "--json"]
    dayProc.running = true
  }

  function loadDay(ymd) {
    guard.run("loadDay", function () {
      if (!ymd) return
      root.dayRequestSerial += 1
      root.pendingDay = ymd
      root.startDayRequest()
    })
  }

  function addBlock(ymd, start, end, activity) {
    guard.run("addBlock", function () {
      root.runVerb(["block", "add", ymd, start, end, activity])
      usage.record("block.add")
      refreshTimer.restart()
    })
  }

  function removeEntry(id) {
    guard.run("removeEntry", function () {
      root.runVerb(["event", "rm", String(id)])
      usage.record("event.rm")
      refreshTimer.restart()
    })
  }

  // A short debounce after a mutation so the CLI's own rebuild finishes
  // before we re-pull the month/day/state views.
  Timer {
    id: refreshTimer
    interval: 600
    onTriggered: {
      root.refreshState()
      if (root.currentMonth) root.loadMonth(root.currentMonth)
      if (root.dayDetail.date) root.loadDay(root.dayDetail.date)
    }
  }

  // ---- Ask AI -------------------------------------------------------------
  property bool aiBusy: false
  property string aiAnswer: ""
  readonly property string aiScriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-calendar-ai"

  Process {
    id: aiProc
    running: false
    stderr: StdioCollector { id: aiErr; waitForEnd: true }
    stdout: StdioCollector {
      id: aiOut
      waitForEnd: true
      onStreamFinished: guard.run("aiProc.onStreamFinished", function () {
        root.aiBusy = false
        root.aiAnswer = aiOut.text.trim() || "(no answer)"
        refreshTimer.restart()
      })
    }
    onExited: function (exitCode) {
      if (exitCode === 0) return
      root.aiBusy = false
      root.aiAnswer = "Ask AI failed: " + root.tail(aiErr.text, "exit " + exitCode)
      root.lastError = root.aiAnswer
    }
  }

  function askAi(prompt) {
    guard.run("askAi", function () {
      if (!prompt || prompt.trim().length === 0 || aiProc.running) return
      root.lastError = ""
      root.aiBusy = true
      root.aiAnswer = ""
      aiProc.command = [root.aiScriptPath, prompt]
      aiProc.running = true
      usage.record("ai.ask")
    })
  }

  Component.onCompleted: root.loadMonth(Qt.formatDate(new Date(), "yyyy-MM"))

  // ---- IPC ----------------------------------------------------------
  IpcHandler {
    target: "alteringux.calendar"

    function refresh(): void { root.refreshState() }

    function status(): string {
      return guard.call("ipc.status", function () {
        return JSON.stringify({
          date: root.state.date,
          today: root.state.today,
          next: root.state.next,
          usage: usage.topActions(6)
        })
      }, "{}")
    }

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // ---- panel ------------------------------------------------------
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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText.length > 0 ? (root.icon + "  " + root.displayText) : root.icon
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function (b) {
      if (b === Qt.RightButton) root.refreshState()
      else root.togglePanel()
    }

    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 2
      active: root.hasTodaySurprise
      level: "info"
    }
  }
}
