// Plain-node tests for the pure logic in Model.js. Run with:
//   node test/model.test.js
// Model.js has no module system of its own (it's loaded as a QML JS import),
// so it exposes a guarded `module.exports` at the bottom purely for this
// harness; that export is a no-op inside QML.
const assert = require("assert")
const Model = require("../Model.js")

function test(name, fn) {
  try {
    fn()
    console.log("ok - " + name)
  } catch (e) {
    console.error("FAIL - " + name)
    console.error(e)
    process.exitCode = 1
  }
}

const DAY = 86400000
// A fixed "now": 2026-09-01 13:20 local. Day math must be timezone-honest, so
// build reference instants with the same local Date the code uses.
const NOW = new Date(2026, 8, 1, 13, 20, 0).getTime()
function localMidnight(y, mIndex, d) {
  return new Date(y, mIndex, d, 0, 0, 0).getTime()
}

// ---------------------------------------------------------------- state basics

test("defaultState is an empty entry list", () => {
  assert.deepStrictEqual(Model.defaultState().entries, [])
})

test("parseState tolerates empty / garbage / wrong-shape input", () => {
  assert.deepStrictEqual(Model.parseState("").entries, [])
  assert.deepStrictEqual(Model.parseState("not json").entries, [])
  assert.deepStrictEqual(Model.parseState("{}").entries, [])
  assert.deepStrictEqual(Model.parseState('{"entries":"nope"}').entries, [])
})

test("parseState drops malformed entries but keeps valid ones and backfills ids", () => {
  const raw = JSON.stringify({
    version: 1,
    entries: [
      { id: "a", label: "good", targetEpoch: NOW + 10 * DAY, createdAt: 1000 },
      { id: "b", label: "   ", targetEpoch: NOW + DAY, createdAt: 2000 }, // blank label
      { id: "c", label: "no target", targetEpoch: 0, createdAt: 3000 },   // bad target
      { label: "id gets generated", targetEpoch: NOW + 5 * DAY, createdAt: 4000 }
    ]
  })
  const parsed = Model.parseState(raw)
  assert.strictEqual(parsed.entries.length, 2)
  assert.strictEqual(parsed.entries[0].label, "good")
  assert.strictEqual(parsed.entries[1].label, "id gets generated")
  assert.ok(typeof parsed.entries[1].id === "string" && parsed.entries[1].id.length > 0)
})

// ---------------------------------------------------------------- day math

test("targetEpochFor lands on local midnight N calendar days out", () => {
  assert.strictEqual(Model.targetEpochFor(0, NOW), localMidnight(2026, 8, 1))
  assert.strictEqual(Model.targetEpochFor(1, NOW), localMidnight(2026, 8, 2))
  assert.strictEqual(Model.targetEpochFor(21, NOW), localMidnight(2026, 8, 22))
  assert.strictEqual(Model.targetEpochFor(30, NOW), localMidnight(2026, 9, 1)) // rolls into October
})

test("daysRemaining counts whole calendar days regardless of time of day", () => {
  const t = Model.targetEpochFor(21, NOW)
  assert.strictEqual(Model.daysRemaining(t, NOW), 21)
  // later the same day -> still 21
  assert.strictEqual(Model.daysRemaining(t, NOW + 6 * 3600 * 1000), 21)
  // next local morning -> 20
  assert.strictEqual(Model.daysRemaining(t, new Date(2026, 8, 2, 7, 0, 0).getTime()), 20)
})

test("daysRemaining is 0 on the day itself and negative afterwards", () => {
  const t = Model.targetEpochFor(3, NOW)
  assert.strictEqual(Model.daysRemaining(t, new Date(2026, 8, 4, 9, 0, 0).getTime()), 0)
  assert.strictEqual(Model.daysRemaining(t, new Date(2026, 8, 6, 9, 0, 0).getTime()), -2)
})

// ---------------------------------------------------------------- add / remove

test("addEntry prepends, trims the label, and stores a midnight target", () => {
  let s = Model.defaultState()
  s = Model.addEntry(s, "  Visiting Disneyland  ", 21, NOW)
  s = Model.addEntry(s, "Move house", 90, NOW)
  assert.deepStrictEqual(s.entries.map(e => e.label), ["Move house", "Visiting Disneyland"])
  assert.strictEqual(s.entries[1].targetEpoch, localMidnight(2026, 8, 22))
})

test("addEntry rejects blank labels and day counts below 1", () => {
  let s = Model.addEntry(Model.defaultState(), "   ", 5, NOW)
  assert.strictEqual(s.entries.length, 0)
  s = Model.addEntry(s, "zero days", 0, NOW)
  assert.strictEqual(s.entries.length, 0)
  s = Model.addEntry(s, "negative", -4, NOW)
  assert.strictEqual(s.entries.length, 0)
})

test("addEntry gives every entry a distinct id", () => {
  let s = Model.defaultState()
  for (let i = 0; i < 20; i++) s = Model.addEntry(s, "e" + i, i + 1, NOW + i)
  assert.strictEqual(new Set(s.entries.map(e => e.id)).size, 20)
})

test("removeEntry deletes just the matching id; unknown id is a no-op", () => {
  let s = Model.defaultState()
  s = Model.addEntry(s, "keep", 5, NOW)
  s = Model.addEntry(s, "drop", 9, NOW)
  const dropId = s.entries[0].id
  s = Model.removeEntry(s, dropId)
  assert.deepStrictEqual(s.entries.map(e => e.label), ["keep"])
  s = Model.removeEntry(s, "nope")
  assert.strictEqual(s.entries.length, 1)
})

test("renameEntry retargets one label, keeps id/target/createdAt, rejects blank", () => {
  let s = Model.defaultState()
  s = Model.addEntry(s, "keep", 5, NOW)
  s = Model.addEntry(s, "typo", 9, NOW)
  const id = s.entries[0].id
  const targetBefore = s.entries[0].targetEpoch
  const createdBefore = s.entries[0].createdAt
  s = Model.renameEntry(s, id, "  Fixed  ")
  assert.strictEqual(s.entries[0].label, "Fixed") // trimmed
  assert.strictEqual(s.entries[0].id, id)
  assert.strictEqual(s.entries[0].targetEpoch, targetBefore)
  assert.strictEqual(s.entries[0].createdAt, createdBefore)
  assert.strictEqual(s.entries[1].label, "keep") // sibling untouched
  // blank label is a no-op, unknown id is a no-op
  s = Model.renameEntry(s, id, "   ")
  assert.strictEqual(s.entries[0].label, "Fixed")
  s = Model.renameEntry(s, "nope", "ghost")
  assert.deepStrictEqual(s.entries.map(e => e.label), ["Fixed", "keep"])
})

test("addEntryAt takes an absolute target, normalises to midnight, rejects past/today", () => {
  let s = Model.defaultState()
  // a messy mid-afternoon instant three days out -> stored at that day's midnight
  const messy = new Date(2026, 8, 4, 15, 42, 0).getTime()
  s = Model.addEntryAt(s, "Concert", messy, NOW)
  assert.strictEqual(s.entries.length, 1)
  assert.strictEqual(s.entries[0].targetEpoch, localMidnight(2026, 8, 4))
  // today and past are refused
  s = Model.addEntryAt(s, "today", localMidnight(2026, 8, 1), NOW)
  s = Model.addEntryAt(s, "past", localMidnight(2026, 7, 20), NOW)
  assert.strictEqual(s.entries.length, 1)
  // blank / bogus target refused
  s = Model.addEntryAt(s, "   ", NOW + 10 * DAY, NOW)
  s = Model.addEntryAt(s, "nan", NaN, NOW)
  assert.strictEqual(s.entries.length, 1)
})

// ---------------------------------------------------------------- calendar grid

test("dateKey / keyForEpoch / epochForKey round-trip a local day", () => {
  assert.strictEqual(Model.dateKey(2026, 8, 4), "2026-09-04")
  assert.strictEqual(Model.keyForEpoch(new Date(2026, 8, 4, 23, 0, 0).getTime()), "2026-09-04")
  assert.strictEqual(Model.epochForKey("2026-09-04"), localMidnight(2026, 8, 4))
  assert.strictEqual(Model.epochForKey("garbage"), 0)
})

test("todayKey / isFutureKey draw the line at the end of today", () => {
  assert.strictEqual(Model.todayKey(NOW), "2026-09-01")
  assert.strictEqual(Model.isFutureKey("2026-09-02", NOW), true)
  assert.strictEqual(Model.isFutureKey("2026-09-01", NOW), false) // today is not future
  assert.strictEqual(Model.isFutureKey("2026-08-31", NOW), false)
  assert.strictEqual(Model.isFutureKey("", NOW), false)
})

test("stepMonth rolls over year boundaries both ways", () => {
  assert.deepStrictEqual(Model.stepMonth(2026, 11, 1), { year: 2027, month: 0 })
  assert.deepStrictEqual(Model.stepMonth(2026, 0, -1), { year: 2025, month: 11 })
})

test("monthGrid is 6 Monday-start rows covering the month plus spill days", () => {
  const grid = Model.monthGrid(2026, 8, 1) // September 2026
  assert.strictEqual(grid.length, 6)
  grid.forEach(w => assert.strictEqual(w.length, 7))
  // 1 Sep 2026 is a Tuesday -> Monday-start grid has exactly one leading day
  assert.strictEqual(grid[0][0].key, "2026-08-31")
  assert.strictEqual(grid[0][0].inMonth, false)
  assert.strictEqual(grid[0][1].key, "2026-09-01")
  assert.strictEqual(grid[0][1].inMonth, true)
  const first = grid.flat().find(d => d.key === "2026-09-15")
  assert.strictEqual(first.inMonth, true)
})

test("monthLabel is the full month name and year", () => {
  assert.strictEqual(Model.monthLabel(2026, 8), "September 2026")
  assert.strictEqual(Model.monthLabel(2027, 0), "January 2027")
})

test("isCurrentOrPastMonth gates the previous-month button", () => {
  assert.strictEqual(Model.isCurrentOrPastMonth(2026, 8, NOW), true)  // this month
  assert.strictEqual(Model.isCurrentOrPastMonth(2026, 7, NOW), true)  // earlier
  assert.strictEqual(Model.isCurrentOrPastMonth(2025, 11, NOW), true) // earlier year
  assert.strictEqual(Model.isCurrentOrPastMonth(2026, 9, NOW), false) // next month
  assert.strictEqual(Model.isCurrentOrPastMonth(2027, 0, NOW), false) // later year
})

// ---------------------------------------------------------------- sort / format

test("sortedBySoonest orders by target, newest-added breaking ties", () => {
  const entries = [
    { id: "a", label: "far", targetEpoch: NOW + 30 * DAY, createdAt: 1 },
    { id: "b", label: "near", targetEpoch: NOW + 2 * DAY, createdAt: 2 },
    { id: "c", label: "tie-old", targetEpoch: NOW + 10 * DAY, createdAt: 3 },
    { id: "d", label: "tie-new", targetEpoch: NOW + 10 * DAY, createdAt: 9 }
  ]
  assert.deepStrictEqual(Model.sortedBySoonest(entries).map(e => e.label),
    ["near", "tie-new", "tie-old", "far"])
})

test("formatRemaining phrasing", () => {
  assert.strictEqual(Model.formatRemaining(21), "21 days")
  assert.strictEqual(Model.formatRemaining(1), "Tomorrow")
  assert.strictEqual(Model.formatRemaining(0), "Today")
  assert.strictEqual(Model.formatRemaining(-1), "Yesterday")
  assert.strictEqual(Model.formatRemaining(-3), "3 days ago")
  assert.strictEqual(Model.formatRemaining(NaN), "")
})

test("formatShort is a signed day count with a d suffix", () => {
  assert.strictEqual(Model.formatShort(21), "21d")
  assert.strictEqual(Model.formatShort(0), "0d")
  assert.strictEqual(Model.formatShort(-3), "-3d")
})

test("formatTarget renders weekday day month year", () => {
  assert.strictEqual(Model.formatTarget(localMidnight(2026, 8, 22)), "Tue 22 Sep 2026")
})

test("marqueeText joins soonest-first segments with a bullet", () => {
  let s = Model.defaultState()
  s = Model.addEntry(s, "Disneyland", 21, NOW)
  s = Model.addEntry(s, "Dentist", 3, NOW)
  const m = Model.marqueeText(s.entries, NOW)
  assert.strictEqual(m.indexOf("3d · Dentist") < m.indexOf("21d · Disneyland"), true)
  assert.strictEqual(m.indexOf("•") > -1, true)
})

test("listText is one soonest-first line per countdown", () => {
  let s = Model.defaultState()
  s = Model.addEntry(s, "Disneyland", 21, NOW)
  s = Model.addEntry(s, "Dentist", 2, NOW)
  assert.strictEqual(Model.listText(s.entries, NOW), "2 days — Dentist\n21 days — Disneyland")
})

test("formatBadge: word when empty, icon + count otherwise", () => {
  assert.strictEqual(Model.formatBadge([]), "  Countdown")
  assert.strictEqual(Model.formatBadge([{}, {}]), "  2")
})

test("soonestDays returns the nearest day count, or null when empty", () => {
  assert.strictEqual(Model.soonestDays([], NOW), null)
  let s = Model.defaultState()
  s = Model.addEntry(s, "a", 40, NOW)
  s = Model.addEntry(s, "b", 4, NOW)
  assert.strictEqual(Model.soonestDays(s.entries, NOW), 4)
})

// ---------------------------------------------------------------- history

test("parseHistory tolerates empty, garbage, and the old plugin's schema", () => {
  assert.deepStrictEqual(Model.defaultHistory().added, [])
  assert.deepStrictEqual(Model.parseHistory("").added, [])
  assert.deepStrictEqual(Model.parseHistory("nonsense").added, [])
  // old spoken-countdown history was a bare array of {mode,duration,...}
  assert.deepStrictEqual(Model.parseHistory('[{"mode":"minutes","duration":5}]').added, [])
})

test("parseHistory drops malformed rows and caps the list", () => {
  const many = []
  for (let i = 0; i < 250; i++) many.push({ label: "x", days: 5, addedAt: 1000 + i })
  many.push({ label: "  ", days: 1, addedAt: 1 }) // blank -> dropped
  const parsed = Model.parseHistory(JSON.stringify({ version: 1, added: many }))
  assert.strictEqual(parsed.added.length, Model.HISTORY_CAP)
})

test("recordAdd prepends and caps at HISTORY_CAP", () => {
  let h = Model.defaultHistory()
  h = Model.recordAdd(h, "Disneyland", 21, 5000)
  assert.deepStrictEqual(h.added[0], { label: "Disneyland", days: 21, addedAt: 5000 })
  for (let i = 0; i < Model.HISTORY_CAP + 20; i++) h = Model.recordAdd(h, "t" + i, 3, 6000)
  assert.strictEqual(h.added.length, Model.HISTORY_CAP)
  assert.strictEqual(h.added[0].label, "t" + (Model.HISTORY_CAP + 19))
})

test("recordAdd ignores a row with no usable label", () => {
  const h = Model.recordAdd(Model.defaultHistory(), "   ", 5, 1)
  assert.strictEqual(h.added.length, 0)
})

test("forgetLabel drops every row for one label, case-insensitively, keeps the rest", () => {
  const h = { version: 1, added: [
    { label: "trip", days: 14, addedAt: 8 },
    { label: "gym", days: 2, addedAt: 7 },
    { label: " TRIP ", days: 20, addedAt: 6 }
  ] }
  const out = Model.forgetLabel(h, "trip")
  assert.deepStrictEqual(out.added.map(r => r.label), ["gym"])
  // blank label is a no-op that still returns a well-formed history
  assert.strictEqual(Model.forgetLabel(h, "   ").added.length, 3)
})

test("rankLabels: frequency then recency, excludes active labels, prefills last day count", () => {
  // newest-first log: trip x3 (last days 14), gym x2 (last days 2), spa x1
  const added = [
    { label: "spa", days: 30, addedAt: 9 },
    { label: "trip", days: 14, addedAt: 8 },
    { label: "gym", days: 2, addedAt: 7 },
    { label: "trip", days: 20, addedAt: 6 },
    { label: "gym", days: 5, addedAt: 5 },
    { label: "trip", days: 25, addedAt: 4 }
  ]
  const ranked = Model.rankLabels(added, [], 4)
  assert.deepStrictEqual(ranked.map(r => r.label), ["trip", "gym", "spa"])
  assert.strictEqual(ranked[0].days, 14) // most recent "trip" day count
  // an active "TRIP" (case-insensitive) drops it from the chips
  assert.deepStrictEqual(Model.rankLabels(added, [{ label: "TRIP" }], 4).map(r => r.label), ["gym", "spa"])
})
