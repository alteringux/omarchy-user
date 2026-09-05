// Pure parse/format helpers for the alteringux.calendar widget + panel.
// All I/O (reading calendar-state.json, running the CLI, notify-send) lives
// in BarWidget.qml / Panel.qml; everything here is Node-testable (see
// test/model.test.js). The CLI (~/.local/bin/omarchy-calendar) is the sole
// writer of every file this reads — this plugin only ever calls its verbs
// and renders what comes back.

function defaultState() {
  return {
    version: 1,
    generatedAt: 0,
    date: "",
    today: { events: [], birthdays: [], holidays: [] },
    next: null
  }
}

// Merge a calendar-state.json string over defaultState(). Bad/missing fields
// fall back rather than throw.
function parseState(raw) {
  var s = defaultState()
  var obj = null
  try { obj = raw ? JSON.parse(raw) : null } catch (e) { obj = null }
  if (!obj || typeof obj !== "object") return s

  if (typeof obj.date === "string") s.date = obj.date
  if (isFiniteNumber(obj.generatedAt)) s.generatedAt = obj.generatedAt
  if (obj.today && typeof obj.today === "object") {
    s.today.events = Array.isArray(obj.today.events) ? obj.today.events : []
    s.today.birthdays = Array.isArray(obj.today.birthdays) ? obj.today.birthdays : []
    s.today.holidays = Array.isArray(obj.today.holidays) ? obj.today.holidays : []
  }
  s.next = (obj.next && typeof obj.next === "object") ? obj.next : null
  return s
}

function isFiniteNumber(n) { return typeof n === "number" && isFinite(n) }

// `omarchy-calendar month <ym> --json` -> { month, days: [{date, events, birthdays, holidays}] }
function parseMonthJson(raw) {
  var obj = null
  try { obj = raw ? JSON.parse(raw) : null } catch (e) { obj = null }
  if (!obj || !Array.isArray(obj.days)) return { month: "", days: [] }
  return { month: String(obj.month || ""), days: obj.days }
}

// `omarchy-calendar day <d> --json` -> { date, events, birthdays, holidays }
function parseDayJson(raw) {
  var obj = null
  try { obj = raw ? JSON.parse(raw) : null } catch (e) { obj = null }
  if (!obj || typeof obj !== "object") return { date: "", events: [], birthdays: [], holidays: [] }
  return {
    date: String(obj.date || ""),
    events: Array.isArray(obj.events) ? obj.events : [],
    birthdays: Array.isArray(obj.birthdays) ? obj.birthdays : [],
    holidays: Array.isArray(obj.holidays) ? obj.holidays : []
  }
}

// Build a fixed 6x7 (42-cell) grid for a month, Sunday-first, with leading/
// trailing days from neighbouring months blanked out (inMonth: false) rather
// than omitted, so the QML Repeater is always exactly 42 items.
function monthGridCells(monthJson, todayDate) {
  var days = (monthJson && Array.isArray(monthJson.days)) ? monthJson.days : []
  if (days.length === 0) return []

  var firstDate = days[0].date
  var firstDow = dayOfWeek(firstDate)
  var cells = []
  for (var i = 0; i < firstDow; i++) cells.push(blankCell())

  for (var d = 0; d < days.length; d++) {
    var day = days[d]
    cells.push({
      date: day.date,
      dayNum: parseInt(day.date.slice(8, 10), 10),
      hasEvent: (day.events || 0) > 0,
      hasBirthday: (day.birthdays || 0) > 0,
      hasHoliday: (day.holidays || 0) > 0,
      isToday: day.date === todayDate,
      inMonth: true
    })
  }
  while (cells.length % 7 !== 0 || cells.length < 42) cells.push(blankCell())
  return cells
}

function blankCell() {
  return { date: "", dayNum: 0, hasEvent: false, hasBirthday: false, hasHoliday: false, isToday: false, inMonth: false }
}

// 0 = Sunday .. 6 = Saturday, via Zeller-free Date() parse of "YYYY-MM-DD".
function dayOfWeek(ymd) {
  var m = String(ymd || "").match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!m) return 0
  return new Date(+m[1], +m[2] - 1, +m[3]).getDay()
}

function monthTitle(ym) {
  var m = String(ym || "").match(/^(\d{4})-(\d{2})$/)
  if (!m) return ""
  var names = ["January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"]
  return names[+m[2] - 1] + " " + m[1]
}

function shiftMonth(ym, delta) {
  var m = String(ym || "").match(/^(\d{4})-(\d{2})$/)
  if (!m) return ym
  var d = new Date(+m[1], +m[2] - 1 + delta, 1)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1)
}

function pad2(n) { return (n < 10 ? "0" : "") + n }

// Bar text: today's birthday/holiday take priority (they're the "you should
// know this" surprises), otherwise the next upcoming timed event/block.
function widgetLabel(state) {
  if (!state) return ""
  var bnames = (state.today && state.today.birthdays || []).map(function (b) { return b.name })
  if (bnames.length > 0) return bnames.length === 1 ? bnames[0] + "'s birthday" : bnames.length + " birthdays today"

  var hnames = (state.today && state.today.holidays) || []
  if (hnames.length > 0) return hnames[0]

  var n = state.next
  if (n && n.date === state.date && n.start) return n.start + " " + n.title
  if (n) return n.title
  return ""
}

function todayBadgeCount(state) {
  if (!state || !state.today) return 0
  return (state.today.events || []).length + (state.today.birthdays || []).length + (state.today.holidays || []).length
}

function entrySubtitle(e) {
  if (!e) return ""
  var time = e.start ? (e.start + (e.end ? "–" + e.end : "")) : "all day"
  var loc = (e.location && e.location.length > 0) ? "  ·  " + e.location : ""
  return time + loc
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    defaultState: defaultState,
    parseState: parseState,
    parseMonthJson: parseMonthJson,
    parseDayJson: parseDayJson,
    monthGridCells: monthGridCells,
    blankCell: blankCell,
    dayOfWeek: dayOfWeek,
    monthTitle: monthTitle,
    shiftMonth: shiftMonth,
    widgetLabel: widgetLabel,
    todayBadgeCount: todayBadgeCount,
    entrySubtitle: entrySubtitle
  }
}
