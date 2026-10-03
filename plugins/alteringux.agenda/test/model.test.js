// Pin the timezone so the local-day / clock assertions are deterministic
// wherever this runs. Must be set before the first Date use.
process.env.TZ = "UTC"

const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const DAY = 86400
const HOUR = 3600

function utc(y, mo, d, hh, mi) {
  return Math.floor(Date.UTC(y, mo - 1, d, hh || 0, mi || 0, 0) / 1000)
}

function ics(events) {
  const body = events.map((e) => [
    "BEGIN:VEVENT",
    "UID:" + (e.uid || "u-" + e.summary),
    "SUMMARY:" + e.summary,
    e.location ? "LOCATION:" + e.location : null,
    e.rrule ? "RRULE:FREQ=WEEKLY" : null,
    e.status ? "STATUS:" + e.status : null,
    "DTSTART:" + e.start,
    e.end ? "DTEND:" + e.end : null,
    e.duration ? "DURATION:" + e.duration : null,
  ].filter(Boolean).join("\r\n") + "\r\nEND:VEVENT").join("\r\n")
  return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" + body + "\r\nEND:VCALENDAR\r\n"
}

test("parseConfig falls back to defaults on junk", () => {
  assert.deepEqual(Model.parseConfig(""), Model.defaultConfig())
  assert.deepEqual(Model.parseConfig("not json"), Model.defaultConfig())
  assert.deepEqual(Model.parseConfig("[]"), Model.defaultConfig())
})

test("parseConfig merges valid fields, ignores bad ones", () => {
  const cfg = Model.parseConfig(JSON.stringify({
    calendarDirs: ["~/cal", 42, ""],
    leadMinutes: 25,
    pollSeconds: 3, // below the floor -> ignored
  }))
  assert.deepEqual(cfg.calendarDirs, ["~/cal"])
  assert.equal(cfg.leadMinutes, 25)
  assert.equal(cfg.pollSeconds, Model.defaultConfig().pollSeconds)
})

test("unfoldLines joins continuation lines (RFC 5545: fold whitespace is dropped)", () => {
  const lines = Model.unfoldLines("SUMMARY:Long ti\r\n tle here\r\nUID:1")
  assert.deepEqual(lines, ["SUMMARY:Long title here", "UID:1"])
})

test("splitProperty separates name, params, value", () => {
  const p = Model.splitProperty("DTSTART;TZID=Europe/Berlin;VALUE=DATE-TIME:20260830T140000")
  assert.equal(p.name, "DTSTART")
  assert.equal(p.params.TZID, "Europe/Berlin")
  assert.equal(p.params.VALUE, "DATE-TIME")
  assert.equal(p.value, "20260830T140000")
})

test("unescapeText handles the RFC escapes", () => {
  assert.equal(Model.unescapeText("a\\, b\\; c\\nd\\\\e"), "a, b; c\nd\\e")
})

test("parseIcsDate: UTC, date-only, and floating", () => {
  assert.deepEqual(Model.parseIcsDate("20260830T140000Z", {}), { epoch: utc(2026, 8, 30, 14, 0), allDay: false })
  const dOnly = Model.parseIcsDate("20260830", {})
  assert.equal(dOnly.allDay, true)
  const valueDate = Model.parseIcsDate("20260830", { VALUE: "DATE" })
  assert.equal(valueDate.allDay, true)
  assert.equal(Model.parseIcsDate("nope", {}), null)
})
test("parseIcsDate resolves TZID wall clocks deterministically", () => {
  const parsed = Model.parseIcsDate("20260830T140000", { TZID: "Europe/Berlin" })
  assert.equal(parsed.epoch, utc(2026, 8, 30, 12, 0))
  assert.equal(parsed.allDay, false)
})

test("parseIcsDuration parses RFC 5545 dur-values", () => {
  assert.equal(Model.parseIcsDuration("PT90M"), 90 * 60)
  assert.equal(Model.parseIcsDuration("PT1H30M"), 5400)
  assert.equal(Model.parseIcsDuration("PT45S"), 45)
  assert.equal(Model.parseIcsDuration("P1D"), DAY)
  assert.equal(Model.parseIcsDuration("P1DT12H"), DAY + 12 * HOUR)
  assert.equal(Model.parseIcsDuration("P2W"), 14 * DAY)
  assert.equal(Model.parseIcsDuration("+PT5M"), 300)
  assert.equal(Model.parseIcsDuration("-PT5M"), -300)
  // Year/month components have no fixed length -> rejected.
  assert.equal(Model.parseIcsDuration("P1M"), null)
  assert.equal(Model.parseIcsDuration("P1Y2M"), null)
  // Bare P / PT and garbage are unparseable.
  assert.equal(Model.parseIcsDuration("P"), null)
  assert.equal(Model.parseIcsDuration("PT"), null)
  assert.equal(Model.parseIcsDuration("nope"), null)
})

test("parseEvents pulls fields and defaults the end", () => {
  const events = Model.parseEvents(ics([
    { summary: "Standup", start: "20260830T140000Z", location: "HQ" },
  ]))
  assert.equal(events.length, 1)
  assert.equal(events[0].summary, "Standup")
  assert.equal(events[0].location, "HQ")
  assert.equal(events[0].start, utc(2026, 8, 30, 14, 0))
  assert.equal(events[0].end, utc(2026, 8, 30, 14, 0) + HOUR)
  assert.equal(events[0].allDay, false)
})

test("parseEvents ignores VALARM sub-component properties", () => {
  const cal =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" +
    "BEGIN:VEVENT\r\nUID:u1\r\nSUMMARY:Standup\r\nLOCATION:HQ\r\n" +
    "DTSTART:20260830T140000Z\r\n" +
    "BEGIN:VALARM\r\nACTION:DISPLAY\r\nSUMMARY:Alarm summary\r\n" +
    "DESCRIPTION:Beep\r\nTRIGGER:-PT10M\r\nEND:VALARM\r\n" +
    "END:VEVENT\r\nEND:VCALENDAR\r\n"
  const events = Model.parseEvents(cal)
  assert.equal(events.length, 1)
  assert.equal(events[0].summary, "Standup")
  assert.equal(events[0].location, "HQ")
})

test("parseEvents uses DURATION when DTEND is absent", () => {
  const events = Model.parseEvents(ics([
    { summary: "Sprint", start: "20260830T140000Z", duration: "PT90M" },
  ]))
  assert.equal(events.length, 1)
  assert.equal(events[0].end, utc(2026, 8, 30, 14, 0) + 90 * 60)
})

test("parseEvents prefers DTEND over DURATION", () => {
  const events = Model.parseEvents(ics([
    { summary: "Both", start: "20260830T140000Z", end: "20260830T150000Z", duration: "PT90M" },
  ]))
  assert.equal(events[0].end, utc(2026, 8, 30, 15, 0))
})

test("parseEvents falls back to the default end when DURATION is invalid", () => {
  const events = Model.parseEvents(ics([
    { summary: "Bad", start: "20260830T140000Z", duration: "P1M" }, // months: no fixed length
  ]))
  assert.equal(events[0].end, utc(2026, 8, 30, 14, 0) + HOUR)
})

test("computeAgenda picks the soonest not-yet-ended timed event as next", () => {
  const now = utc(2026, 8, 30, 12, 0)
  const cal = ics([
    { summary: "Past", start: "20260830T090000Z", end: "20260830T100000Z" },
    { summary: "Ongoing", start: "20260830T113000Z", end: "20260830T123000Z" },
    { summary: "Soon", start: "20260830T140000Z" },
    { summary: "Later", start: "20260830T160000Z" },
  ])
  const agenda = Model.computeAgenda([cal], now, {})
  // "Ongoing" started before now but hasn't ended -> still the next thing.
  assert.equal(agenda.next.summary, "Ongoing")
  assert.equal(agenda.upcoming.map((e) => e.summary).join(","), "Ongoing,Soon,Later")
})
test("computeAgenda expands a weekly recurrence to its next occurrence", () => {
  const now = utc(2026, 8, 30, 12, 0)
  const cal = ics([
    { uid: "weekly", summary: "Weekly", start: "20260824T140000Z", end: "20260824T150000Z", rrule: true },
  ])
  const agenda = Model.computeAgenda([cal], now, {})
  assert.equal(agenda.next.summary, "Weekly")
  assert.equal(agenda.next.start, utc(2026, 8, 31, 14, 0))
  assert.equal(agenda.next.recurring, true)
})

test("computeAgenda skips CANCELLED and de-dupes by uid+start", () => {
  const now = utc(2026, 8, 30, 12, 0)
  const cal = ics([
    { uid: "x", summary: "Dupe", start: "20260830T140000Z" },
    { uid: "x", summary: "Dupe", start: "20260830T140000Z" },
    { uid: "y", summary: "Axed", start: "20260830T150000Z", status: "CANCELLED" },
  ])
  const agenda = Model.computeAgenda([cal], now, {})
  assert.equal(agenda.upcoming.length, 1)
  assert.equal(agenda.upcoming[0].summary, "Dupe")
})

test("computeAgenda falls back to an all-day event when nothing is timed", () => {
  const now = utc(2026, 8, 30, 12, 0)
  const cal = ics([{ summary: "Holiday", start: "20260831" }])
  const agenda = Model.computeAgenda([cal], now, {})
  assert.equal(agenda.next.summary, "Holiday")
  assert.equal(agenda.next.allDay, true)
})

test("shouldNotify fires once inside the lead window, then dedupes", () => {
  const start = utc(2026, 8, 30, 14, 0)
  const agenda = { next: { uid: "e1", summary: "Standup", start, allDay: false }, today: [] }

  const early = Model.shouldNotify(agenda, start - 20 * 60, 10 * 60, [])
  assert.equal(early.notify, false)

  const inWindow = Model.shouldNotify(agenda, start - 8 * 60, 10 * 60, early.keys)
  assert.equal(inWindow.notify, true)
  assert.equal(inWindow.minutesUntil, 8)
  assert.ok(inWindow.keys.includes("e1@" + start))

  const again = Model.shouldNotify(agenda, start - 5 * 60, 10 * 60, inWindow.keys)
  assert.equal(again.notify, false)
})

test("shouldNotify ignores all-day events", () => {
  const start = utc(2026, 8, 30, 0, 0)
  const agenda = { next: { uid: "h", summary: "Holiday", start, allDay: true }, today: [] }
  assert.equal(Model.shouldNotify(agenda, start - 60, 10 * 60, []).notify, false)
})

test("pruneKeys drops entries older than a day", () => {
  const now = utc(2026, 8, 30, 12, 0)
  const kept = Model.pruneKeys(
    ["old@" + (now - 2 * DAY), "fresh@" + (now - HOUR), "malformed"],
    now
  )
  assert.deepEqual(kept, ["fresh@" + (now - HOUR)])
})

test("formatRelative reads naturally across ranges", () => {
  assert.equal(Model.formatRelative(10), "now")
  assert.equal(Model.formatRelative(8 * 60), "in 8 min")
  assert.equal(Model.formatRelative(65 * 60), "in 1 h 5 min")
  assert.equal(Model.formatRelative(2 * HOUR), "in 2 h")
  assert.equal(Model.formatRelative(2 * DAY), "in 2 d")
})

test("formatClock returns HH:MM", () => {
  assert.match(Model.formatClock(utc(2026, 8, 30, 14, 5)), /^\d{2}:\d{2}$/)
})

test("stateJson shape for a pending timed event", () => {
  const now = utc(2026, 8, 30, 12, 0)
  const agenda = Model.computeAgenda([ics([
    { summary: "Review", start: "20260830T140000Z", location: "Room 2" },
  ])], now, {})
  const state = Model.stateJson(agenda, now)
  assert.equal(state.version, 1)
  assert.equal(state.generated_at, now)
  assert.equal(state.next.summary, "Review")
  assert.equal(state.next.location, "Room 2")
  assert.equal(state.next.start_epoch, utc(2026, 8, 30, 14, 0))
  assert.equal(state.next.all_day, false)
  assert.equal(state.today_count, 1)
})

test("stateJson tolerates an empty agenda", () => {
  const state = Model.stateJson({ next: null, today: [] }, 0)
  assert.equal(state.next, null)
  assert.equal(state.today_count, 0)
})
