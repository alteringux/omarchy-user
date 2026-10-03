const { test } = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("dateKey / keyForDate: zero-padded, stable identity", () => {
  assert.equal(Model.dateKey(2026, 0, 5), "2026-01-05")
  assert.equal(Model.dateKey(2026, 11, 31), "2026-12-31")
  assert.equal(Model.keyForDate(new Date(2026, 8, 8)), "2026-09-08")
})

test("normalizedWeekStart: name, abbreviation, index, and fallback", () => {
  assert.equal(Model.normalizedWeekStart("sunday", 1), 0)
  assert.equal(Model.normalizedWeekStart("mon", 0), 1)
  assert.equal(Model.normalizedWeekStart(6, 1), 6)
  // missing/nonsense falls back to the given locale default, not to Monday
  assert.equal(Model.normalizedWeekStart(undefined, 0), 0)
  assert.equal(Model.normalizedWeekStart("nonsense", 3), 3)
  // fallback itself nonsense lands on Monday
  assert.equal(Model.normalizedWeekStart(undefined, undefined), 1)
})

test("weekStartSettingName round-trips through normalizedWeekStart", () => {
  assert.equal(Model.weekStartSettingName(0), "sunday")
  assert.equal(Model.weekStartSettingName(6), "saturday")
})

test("toggledWeekStart: flips only the Sunday/Monday pair, others land on Monday", () => {
  assert.equal(Model.toggledWeekStart(1), 0)
  assert.equal(Model.toggledWeekStart(0), 1)
  assert.equal(Model.toggledWeekStart(6), 1)
})

test("weekdayOrder: seven entries starting at the configured day", () => {
  assert.deepEqual(Model.weekdayOrder(0), [0, 1, 2, 3, 4, 5, 6])
  assert.deepEqual(Model.weekdayOrder(1), [1, 2, 3, 4, 5, 6, 0])
  assert.deepEqual(Model.weekdayOrder(5), [5, 6, 0, 1, 2, 3, 4])
})

test("isoWeek: known reference points", () => {
  // 2026-01-01 is a Thursday, so ISO week 1 starts on it.
  assert.equal(Model.isoWeek(2026, 0, 1), 1)
  // Dec 31 2025 is a Wednesday in the same ISO week 1 as Jan 1 2026.
  assert.equal(Model.isoWeek(2025, 11, 31), 1)
  // Dec 31 2024 is a Tuesday, still week 1 of 2025 by the same rule.
  assert.equal(Model.isoWeek(2024, 11, 31), 1)
})

test("dayOfYear / daysInYear / yearProgress: boundaries", () => {
  assert.equal(Model.dayOfYear(2026, 0, 1), 1)
  assert.equal(Model.dayOfYear(2026, 11, 31), 365)
  assert.equal(Model.daysInYear(2024), 366) // leap year
  assert.equal(Model.daysInYear(2026), 365)
  assert.equal(Model.yearProgressPercent(2026, 0, 1), 0)
  assert.equal(Model.yearProgressPercent(2026, 11, 31), 100)
})

test("parseBirthYear: accepts a plausible 4-digit year, rejects the rest", () => {
  assert.equal(Model.parseBirthYear("1990", 2026), 1990)
  assert.equal(Model.parseBirthYear("  1990  ", 2026), 1990)
  assert.equal(Model.parseBirthYear("", 2026), 0)
  assert.equal(Model.parseBirthYear("abcd", 2026), 0)
  assert.equal(Model.parseBirthYear("2027", 2026), 0) // future
  assert.equal(Model.parseBirthYear(String(2026 - 120), 2026), 2026 - 120)
  assert.equal(Model.parseBirthYear(String(2026 - 121), 2026), 0) // too distant
})

test("ageFromBirthYear: whole years regardless of month/day", () => {
  assert.equal(Model.ageFromBirthYear(1979, 2026), 47)
  assert.equal(Model.ageFromBirthYear(0, 2026), 0)
})

test("parseAge / parseLifeExpectancy: bounds and default fallback", () => {
  assert.equal(Model.parseAge("47"), 47)
  assert.equal(Model.parseAge("0"), 0)
  assert.equal(Model.parseAge("-5"), 0)
  assert.equal(Model.parseAge("121"), 0)
  assert.equal(Model.parseLifeExpectancy(""), 90)
  assert.equal(Model.parseLifeExpectancy("0"), 90)
  assert.equal(Model.parseLifeExpectancy("85"), 85)
  assert.equal(Model.parseLifeExpectancy("151"), 90)
})

test("lifeProgress: 0 until both an age and an expectancy are set", () => {
  assert.equal(Model.lifeProgress(0, 90), 0)
  assert.equal(Model.lifeProgressPercent(45, 90), 50)
  assert.equal(Model.lifeProgress(100, 90), 1) // clamped, not >100%
})

test("monthGrid: always six rows of seven days, marks today and in-month", () => {
  var weeks = Model.monthGrid(2026, 8, 1, "2026-09-08") // September 2026, Monday start
  assert.equal(weeks.length, 6)
  weeks.forEach(function (week) { assert.equal(week.days.length, 7) })

  var flat = []
  weeks.forEach(function (week) { flat = flat.concat(week.days) })
  var todays = flat.filter(function (d) { return d.today })
  assert.equal(todays.length, 1)
  assert.equal(todays[0].key, "2026-09-08")

  var inMonth = flat.filter(function (d) { return d.inMonth })
  assert.equal(inMonth.length, 30) // September has 30 days
})

test("monthGrid: row week numbers follow the ISO Thursday-owner rule", () => {
  var weeks = Model.monthGrid(2026, 0, 1, "2026-01-01")
  assert.equal(weeks[0].week, 1)
})

test("stepMonth: steps within and across year boundaries", () => {
  assert.deepEqual(Model.stepMonth(2026, 8, 1), { year: 2026, month: 9 })
  assert.deepEqual(Model.stepMonth(2026, 11, 1), { year: 2027, month: 0 })
  assert.deepEqual(Model.stepMonth(2026, 0, -1), { year: 2025, month: 11 })
  assert.deepEqual(Model.stepMonth(2026, 0, 12), { year: 2027, month: 0 })
})

test("clockFormatRing: dedupes, keeps presets in order, appends the configured pair", () => {
  var ring = Model.clockFormatRing("HH:mm", "h:mm AP", ["dddd HH:mm", "HH:mm"])
  assert.deepEqual(ring, ["dddd HH:mm", "HH:mm", "h:mm AP"])
})

test("clockFormatRing: never returns an empty ring", () => {
  assert.deepEqual(Model.clockFormatRing("", "", []), ["HH:mm"])
})

test("nextClockFormat: wraps around, and an unknown current format restarts the walk", () => {
  var ring = ["a", "b", "c"]
  assert.equal(Model.nextClockFormat(ring, "a"), "b")
  assert.equal(Model.nextClockFormat(ring, "c"), "a")
  assert.equal(Model.nextClockFormat(ring, "not-in-ring"), "a")
  assert.equal(Model.nextClockFormat([], "a"), "")
})

test("formatUsesSeconds: follows unquoted Qt seconds tokens", () => {
  assert.equal(Model.formatUsesSeconds("dddd HH:mm"), false)
  assert.equal(Model.formatUsesSeconds("dddd h:mm:ss AP"), true)
  assert.equal(Model.formatUsesSeconds("'seconds' HH:mm"), false)
  assert.equal(Model.formatUsesSeconds(null), false)
})

test("isoWeekLiteral: two-digit, zero-padded", () => {
  assert.equal(Model.isoWeekLiteral(2026, 0, 1), "01")
})
