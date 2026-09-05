const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("parseState falls back to defaults on garbage", () => {
  const s = Model.parseState("not json")
  assert.equal(s.date, "")
  assert.deepEqual(s.today, { events: [], birthdays: [], holidays: [] })
  assert.equal(s.next, null)
})

test("parseState reads a well-formed snapshot", () => {
  const raw = JSON.stringify({
    version: 1, generatedAt: 100, date: "2026-09-10",
    today: { events: [{ id: 1 }], birthdays: [{ name: "Alice", age: 36 }], holidays: [] },
    next: { id: 1, title: "Dentist", date: "2026-09-10", start: "09:30" }
  })
  const s = Model.parseState(raw)
  assert.equal(s.date, "2026-09-10")
  assert.equal(s.today.birthdays[0].name, "Alice")
  assert.equal(s.next.title, "Dentist")
})

test("widgetLabel prioritizes today's birthday over the next event", () => {
  const s = Model.parseState(JSON.stringify({
    date: "2026-09-10",
    today: { events: [], birthdays: [{ name: "Alice", age: 36 }], holidays: [] },
    next: { id: 1, title: "Dentist", date: "2026-09-10", start: "09:30" }
  }))
  assert.equal(Model.widgetLabel(s), "Alice's birthday")
})

test("widgetLabel falls back to a holiday, then the next event", () => {
  const withHoliday = Model.parseState(JSON.stringify({
    date: "2026-01-01",
    today: { events: [], birthdays: [], holidays: ["New Year's Day"] },
    next: null
  }))
  assert.equal(Model.widgetLabel(withHoliday), "New Year's Day")

  const withNext = Model.parseState(JSON.stringify({
    date: "2026-09-05",
    today: { events: [], birthdays: [], holidays: [] },
    next: { id: 2, title: "Standup", date: "2026-09-06", start: "09:00" }
  }))
  assert.equal(Model.widgetLabel(withNext), "Standup")
})

test("widgetLabel shows next event's time only when it's today", () => {
  const s = Model.parseState(JSON.stringify({
    date: "2026-09-05",
    today: { events: [], birthdays: [], holidays: [] },
    next: { id: 2, title: "Standup", date: "2026-09-05", start: "09:00" }
  }))
  assert.equal(Model.widgetLabel(s), "09:00 Standup")
})

test("todayBadgeCount sums events + birthdays + holidays", () => {
  const s = Model.parseState(JSON.stringify({
    date: "2026-09-10",
    today: { events: [{}, {}], birthdays: [{}], holidays: [] },
    next: null
  }))
  assert.equal(Model.todayBadgeCount(s), 3)
})

test("parseMonthJson / monthGridCells builds a 42-cell Sunday-first grid", () => {
  process.env.TZ = "UTC"
  const days = []
  for (let d = 1; d <= 30; d++) {
    days.push({ date: `2026-09-${String(d).padStart(2, "0")}`, events: d === 10 ? 1 : 0, birthdays: 0, holidays: 0 })
  }
  const mj = Model.parseMonthJson(JSON.stringify({ month: "2026-09", days }))
  const cells = Model.monthGridCells(mj, "2026-09-10")
  assert.equal(cells.length % 7, 0)
  assert.ok(cells.length >= 35)

  // Sept 1 2026 is a Tuesday -> 2 leading blanks (Sun, Mon).
  assert.equal(cells[0].inMonth, false)
  assert.equal(cells[1].inMonth, false)
  assert.equal(cells[2].inMonth, true)
  assert.equal(cells[2].dayNum, 1)

  const tenth = cells.find((c) => c.date === "2026-09-10")
  assert.ok(tenth)
  assert.equal(tenth.hasEvent, true)
  assert.equal(tenth.isToday, true)
})

test("monthGridCells returns [] for an empty month", () => {
  assert.deepEqual(Model.monthGridCells({ month: "2026-09", days: [] }, "2026-09-10"), [])
})

test("monthTitle formats YYYY-MM", () => {
  assert.equal(Model.monthTitle("2026-09"), "September 2026")
  assert.equal(Model.monthTitle("bogus"), "")
})

test("shiftMonth moves forward and backward across year boundaries", () => {
  assert.equal(Model.shiftMonth("2026-09", 1), "2026-10")
  assert.equal(Model.shiftMonth("2026-12", 1), "2027-01")
  assert.equal(Model.shiftMonth("2026-01", -1), "2025-12")
})

test("entrySubtitle formats timed and all-day entries", () => {
  assert.equal(Model.entrySubtitle({ start: "09:30", end: "10:00", location: "Clinic" }), "09:30–10:00  ·  Clinic")
  assert.equal(Model.entrySubtitle({ start: null, end: null, location: "" }), "all day")
})
