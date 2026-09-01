// Plain-node tests for the pure logic in Model.js. Run with:
//   node test/model.test.js
// Model.js has no module system of its own (it's loaded as a QML JS
// import), so it exposes a guarded `module.exports` at the bottom purely
// for this test harness; that export is a no-op inside QML.
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

test("defaultState is an empty entry list", () => {
  const s = Model.defaultState()
  assert.deepStrictEqual(s.entries, [])
})

test("parseState tolerates empty / garbage input", () => {
  assert.deepStrictEqual(Model.parseState("").entries, [])
  assert.deepStrictEqual(Model.parseState("not json").entries, [])
  assert.deepStrictEqual(Model.parseState("{}").entries, [])
})

test("parseState drops malformed entries but keeps valid ones", () => {
  const raw = JSON.stringify({
    version: 1,
    entries: [
      { id: "a", label: "good", createdAt: 1000 },
      { id: "b", label: "   ", createdAt: 2000 }, // blank label
      { id: "c", label: "no time", createdAt: 0 }, // bad timestamp
      { label: "id gets generated", createdAt: 3000 }
    ]
  })
  const parsed = Model.parseState(raw)
  assert.strictEqual(parsed.entries.length, 2)
  assert.strictEqual(parsed.entries[0].label, "good")
  assert.strictEqual(parsed.entries[1].label, "id gets generated")
  assert.strictEqual(typeof parsed.entries[1].id, "string")
  assert.ok(parsed.entries[1].id.length > 0)
})

test("addEntry prepends (newest first) and stamps createdAt", () => {
  let s = Model.defaultState()
  s = Model.addEntry(s, "first", 1000)
  s = Model.addEntry(s, "second", 2000)
  assert.deepStrictEqual(s.entries.map(e => e.label), ["second", "first"])
  assert.strictEqual(s.entries[0].createdAt, 2000)
  assert.strictEqual(s.entries[1].createdAt, 1000)
})

test("addEntry trims the label and rejects blank input", () => {
  let s = Model.addEntry(Model.defaultState(), "  padded  ", 1000)
  assert.strictEqual(s.entries[0].label, "padded")
  const same = Model.addEntry(s, "   ", 2000)
  assert.strictEqual(same.entries.length, 1)
})

test("addEntry gives every entry a distinct id", () => {
  let s = Model.defaultState()
  for (let i = 0; i < 20; i++) s = Model.addEntry(s, "t" + i, 1000 + i)
  const ids = new Set(s.entries.map(e => e.id))
  assert.strictEqual(ids.size, 20)
})

test("removeEntry deletes just the matching id", () => {
  let s = Model.defaultState()
  s = Model.addEntry(s, "keep", 1000)
  s = Model.addEntry(s, "drop", 2000)
  const dropId = s.entries[0].id
  s = Model.removeEntry(s, dropId)
  assert.deepStrictEqual(s.entries.map(e => e.label), ["keep"])
})

test("removeEntry is a no-op for an unknown id", () => {
  let s = Model.addEntry(Model.defaultState(), "keep", 1000)
  s = Model.removeEntry(s, "nope")
  assert.strictEqual(s.entries.length, 1)
})

test("renameEntry retargets one label, keeps id/createdAt, rejects blank/unknown", () => {
  let s = Model.defaultState()
  s = Model.addEntry(s, "keep", 1000)
  s = Model.addEntry(s, "typo", 2000)
  const id = s.entries[0].id
  s = Model.renameEntry(s, id, "  Fixed  ")
  assert.strictEqual(s.entries[0].label, "Fixed") // trimmed
  assert.strictEqual(s.entries[0].id, id)
  assert.strictEqual(s.entries[0].createdAt, 2000) // elapsed clock untouched
  assert.strictEqual(s.entries[1].label, "keep") // sibling untouched
  s = Model.renameEntry(s, id, "   ") // blank -> no-op
  assert.strictEqual(s.entries[0].label, "Fixed")
  s = Model.renameEntry(s, "nope", "ghost") // unknown id -> no-op
  assert.deepStrictEqual(s.entries.map(e => e.label), ["Fixed", "keep"])
})

test("formatElapsed: seconds only under a minute", () => {
  assert.strictEqual(Model.formatElapsed(0), "0s")
  assert.strictEqual(Model.formatElapsed(42 * 1000), "42s")
  assert.strictEqual(Model.formatElapsed(59 * 1000), "59s")
})

test("formatElapsed: whole minutes from 1m to 59m", () => {
  assert.strictEqual(Model.formatElapsed(60 * 1000), "1m")
  assert.strictEqual(Model.formatElapsed(17 * 60 * 1000 + 40 * 1000), "17m")
  assert.strictEqual(Model.formatElapsed(59 * 60 * 1000), "59m")
})

test("formatElapsed: hours + zero-padded minutes under a day", () => {
  assert.strictEqual(Model.formatElapsed(60 * 60 * 1000), "1h 00m")
  assert.strictEqual(Model.formatElapsed((3 * 60 + 8) * 60 * 1000), "3h 08m")
  assert.strictEqual(Model.formatElapsed((23 * 60 + 59) * 60 * 1000), "23h 59m")
})

test("formatElapsed: days + zero-padded hours past a day", () => {
  assert.strictEqual(Model.formatElapsed(24 * 60 * 60 * 1000), "1d 00h")
  assert.strictEqual(Model.formatElapsed((2 * 24 + 5) * 60 * 60 * 1000), "2d 05h")
})

test("formatElapsed: negative / bogus input clamps to 0s", () => {
  assert.strictEqual(Model.formatElapsed(-5000), "0s")
  assert.strictEqual(Model.formatElapsed(NaN), "0s")
})

test("longestElapsedMs picks the oldest timer", () => {
  const entries = [
    { id: "a", label: "a", createdAt: 5000 },
    { id: "b", label: "b", createdAt: 1000 },
    { id: "c", label: "c", createdAt: 3000 }
  ]
  assert.strictEqual(Model.longestElapsedMs(entries, 10000), 9000)
  assert.strictEqual(Model.longestElapsedMs([], 10000), 0)
})

// ---------------------------------------------------------- pause / resume

test("legacy entry (no runningSince) elapses as now - createdAt and reads as running", () => {
  const e = { id: "a", label: "a", createdAt: 1000 }
  assert.strictEqual(Model.entryElapsedMs(e, 4000), 3000)
  assert.strictEqual(Model.isPaused(e), false)
})

test("addEntry stamps a running clock; entryElapsedMs tracks it", () => {
  const s = Model.addEntry(Model.defaultState(), "task", 1000)
  const e = s.entries[0]
  assert.strictEqual(e.accumulatedMs, 0)
  assert.strictEqual(e.runningSince, 1000)
  assert.strictEqual(Model.entryElapsedMs(e, 5000), 4000)
})

test("pauseEntry banks the live span and freezes elapsed", () => {
  let s = Model.addEntry(Model.defaultState(), "task", 1000)
  const id = s.entries[0].id
  s = Model.pauseEntry(s, id, 5000)
  const e = s.entries[0]
  assert.strictEqual(Model.isPaused(e), true)
  assert.strictEqual(e.accumulatedMs, 4000)
  assert.strictEqual(e.runningSince, 0)
  // frozen: time passing while paused does not advance elapsed
  assert.strictEqual(Model.entryElapsedMs(e, 999999), 4000)
})

test("resumeEntry opens a fresh span that adds onto the banked time", () => {
  let s = Model.addEntry(Model.defaultState(), "task", 1000)
  const id = s.entries[0].id
  s = Model.pauseEntry(s, id, 5000)   // banked 4000
  s = Model.resumeEntry(s, id, 10000) // running again from 10000
  const e = s.entries[0]
  assert.strictEqual(Model.isPaused(e), false)
  assert.strictEqual(Model.entryElapsedMs(e, 12000), 6000) // 4000 banked + 2000 live
})

test("pause/resume are no-ops in the wrong state or for an unknown id", () => {
  let s = Model.addEntry(Model.defaultState(), "task", 1000)
  const id = s.entries[0].id
  const running = s.entries[0]
  s = Model.resumeEntry(s, id, 3000) // already running
  assert.strictEqual(s.entries[0].runningSince, running.runningSince)
  s = Model.pauseEntry(s, "ghost", 3000)
  assert.strictEqual(s.entries[0].runningSince, running.runningSince)
  s = Model.pauseEntry(s, id, 5000)
  const paused = s.entries[0]
  s = Model.pauseEntry(s, id, 9000) // already paused
  assert.strictEqual(s.entries[0].accumulatedMs, paused.accumulatedMs)
})

test("togglePause flips between paused and running", () => {
  let s = Model.addEntry(Model.defaultState(), "task", 1000)
  const id = s.entries[0].id
  s = Model.togglePause(s, id, 5000)
  assert.strictEqual(Model.isPaused(s.entries[0]), true)
  s = Model.togglePause(s, id, 6000)
  assert.strictEqual(Model.isPaused(s.entries[0]), false)
})

test("parseState round-trips accumulatedMs / runningSince and honours an explicit pause", () => {
  const raw = JSON.stringify({
    version: 1,
    entries: [
      { id: "run", label: "running", createdAt: 1000, accumulatedMs: 500, runningSince: 2000 },
      { id: "pau", label: "paused", createdAt: 1000, accumulatedMs: 7000, runningSince: 0 },
      { id: "leg", label: "legacy", createdAt: 1000 }
    ]
  })
  const p = Model.parseState(raw)
  assert.strictEqual(p.entries.length, 3)
  assert.strictEqual(Model.isPaused(p.entries[1]), true)
  assert.strictEqual(Model.entryElapsedMs(p.entries[1], 999999), 7000)
  assert.strictEqual(p.entries[2].runningSince, 1000) // legacy fallback
})

test("renameEntry preserves the elapsed clock fields", () => {
  let s = Model.addEntry(Model.defaultState(), "typo", 1000)
  const id = s.entries[0].id
  s = Model.pauseEntry(s, id, 4000) // banked 3000
  s = Model.renameEntry(s, id, "fixed")
  assert.strictEqual(s.entries[0].label, "fixed")
  assert.strictEqual(s.entries[0].accumulatedMs, 3000)
  assert.strictEqual(s.entries[0].runningSince, 0)
})

// ---------------------------------------------------------- total today

test("totalActiveMs sums elapsed across running and paused timers", () => {
  let s = Model.addEntry(Model.defaultState(), "a", 1000)   // runs 1000->
  s = Model.addEntry(s, "b", 3000)                          // runs 3000->
  const bId = s.entries[0].id
  s = Model.pauseEntry(s, bId, 5000)                        // b banked 2000
  // at now=6000: a = 5000, b = 2000 (frozen)
  assert.strictEqual(Model.totalActiveMs(s.entries, 6000), 7000)
})

test("completedTodayMs only counts completions that ended today", () => {
  const now = new Date("2026-09-01T12:00:00").getTime()
  const earlierToday = new Date("2026-09-01T08:00:00").getTime()
  const yesterday = new Date("2026-08-31T23:00:00").getTime()
  const completed = [
    { label: "x", startedAt: 1, endedAt: earlierToday, durationMs: 600000 },
    { label: "y", startedAt: 1, endedAt: yesterday, durationMs: 999999 },
    { label: "z", startedAt: 1, endedAt: earlierToday, durationMs: 300000 }
  ]
  assert.strictEqual(Model.completedTodayMs(completed, now), 900000)
})

test("formatTotals omits a zero side and returns '' when nothing to show", () => {
  assert.strictEqual(Model.formatTotals([], [], 1000), "")
  const s = Model.addEntry(Model.defaultState(), "a", 1000)
  assert.strictEqual(Model.formatTotals(s.entries, [], 61000), "1m running")
})

test("formatBadge: icon + word when nothing is running", () => {
  assert.strictEqual(Model.formatBadge([]), "  Timers")
})

test("formatBadge: icon + count only, never elapsed time", () => {
  const entries = [
    { id: "a", label: "a", createdAt: 10000 },
    { id: "b", label: "b", createdAt: 1000 }
  ]
  assert.strictEqual(Model.formatBadge(entries), "  2")
})

// ---------------------------------------------------------- self-improvement

test("defaultHistory / parseHistory tolerate empty and garbage", () => {
  assert.deepStrictEqual(Model.defaultHistory().completed, [])
  assert.deepStrictEqual(Model.parseHistory("").completed, [])
  assert.deepStrictEqual(Model.parseHistory("nonsense").completed, [])
  assert.deepStrictEqual(Model.parseHistory('{"completed":"nope"}').completed, [])
})

test("parseHistory drops malformed completions and caps the list", () => {
  const many = []
  for (let i = 0; i < 250; i++) {
    many.push({ label: "x", startedAt: 1000 + i, endedAt: 2000 + i, durationMs: 1000 })
  }
  many.push({ label: "  ", startedAt: 1, endedAt: 2, durationMs: 1 }) // blank -> dropped
  const parsed = Model.parseHistory(JSON.stringify({ version: 1, completed: many }))
  assert.strictEqual(parsed.completed.length, Model.HISTORY_CAP)
})

test("parseHistory backfills a missing durationMs from the timestamps", () => {
  const raw = JSON.stringify({ completed: [{ label: "x", startedAt: 1000, endedAt: 5000 }] })
  assert.strictEqual(Model.parseHistory(raw).completed[0].durationMs, 4000)
})

test("recordCompletion prepends a completion and caps at HISTORY_CAP", () => {
  let h = Model.defaultHistory()
  h = Model.recordCompletion(h, { label: "code review", createdAt: 1000 }, 4000)
  assert.strictEqual(h.completed.length, 1)
  assert.deepStrictEqual(h.completed[0], {
    label: "code review", startedAt: 1000, endedAt: 4000, durationMs: 3000
  })
  for (let i = 0; i < Model.HISTORY_CAP + 20; i++) {
    h = Model.recordCompletion(h, { label: "t" + i, createdAt: 1000 }, 2000)
  }
  assert.strictEqual(h.completed.length, Model.HISTORY_CAP)
  assert.strictEqual(h.completed[0].label, "t" + (Model.HISTORY_CAP + 19)) // newest kept
})

test("recordCompletion ignores an entry with no usable label", () => {
  let h = Model.recordCompletion(Model.defaultHistory(), { label: "   ", createdAt: 1 }, 2)
  assert.strictEqual(h.completed.length, 0)
})

test("rankLabels orders by frequency, then most-recent use", () => {
  // newest-first log: alpha x3, beta x2, gamma x1
  const completed = [
    { label: "gamma", startedAt: 1, endedAt: 2, durationMs: 1 },
    { label: "alpha", startedAt: 1, endedAt: 2, durationMs: 1 },
    { label: "beta", startedAt: 1, endedAt: 2, durationMs: 1 },
    { label: "alpha", startedAt: 1, endedAt: 2, durationMs: 1 },
    { label: "beta", startedAt: 1, endedAt: 2, durationMs: 1 },
    { label: "alpha", startedAt: 1, endedAt: 2, durationMs: 1 }
  ]
  assert.deepStrictEqual(Model.rankLabels(completed, [], 4), ["alpha", "beta", "gamma"])
})

test("rankLabels excludes labels that already have a live timer, and respects the limit", () => {
  const completed = [
    { label: "a", startedAt: 1, endedAt: 2, durationMs: 1 },
    { label: "b", startedAt: 1, endedAt: 2, durationMs: 1 },
    { label: "c", startedAt: 1, endedAt: 2, durationMs: 1 }
  ]
  assert.deepStrictEqual(Model.rankLabels(completed, [{ label: "B" }], 4), ["a", "c"])
  assert.strictEqual(Model.rankLabels(completed, [], 2).length, 2)
})

test("median handles odd, even, and empty inputs", () => {
  assert.strictEqual(Model.median([5, 1, 3]), 3)
  assert.strictEqual(Model.median([1, 2, 3, 4]), 2.5)
  assert.strictEqual(Model.median([]), 0)
})

test("baselineFor is null below the sample threshold, else the median duration", () => {
  const completed = [
    { label: "review", startedAt: 0, endedAt: 0, durationMs: 600000 },
    { label: "review", startedAt: 0, endedAt: 0, durationMs: 1800000 },
    { label: "review", startedAt: 0, endedAt: 0, durationMs: 1200000 },
    { label: "solo", startedAt: 0, endedAt: 0, durationMs: 999 }
  ]
  assert.strictEqual(Model.baselineFor(completed, "solo"), null)
  assert.strictEqual(Model.baselineFor(completed, "never"), null)
  const b = Model.baselineFor(completed, "review")
  assert.strictEqual(b.samples, 3)
  assert.strictEqual(b.median, 1200000)
})

test("isRunningLong compares elapsed against median * LONG_FACTOR", () => {
  const baseline = { median: 1000, samples: 3 }
  assert.strictEqual(Model.isRunningLong(1000 * Model.LONG_FACTOR - 1, baseline), false)
  assert.strictEqual(Model.isRunningLong(1000 * Model.LONG_FACTOR + 1, baseline), true)
  assert.strictEqual(Model.isRunningLong(999999, null), false)
  assert.strictEqual(Model.isRunningLong(999999, { median: 0, samples: 3 }), false)
})
