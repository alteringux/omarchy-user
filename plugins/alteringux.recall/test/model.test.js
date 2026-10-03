"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const MIN = 60_000
const HOUR = 60 * MIN
const DAY = 24 * HOUR

function cfg(over) { return Object.assign(Model.defaultConfig(), { enabled: true }, over || {}) }
function state(over) { return Object.assign(Model.defaultState(), over || {}) }
function quiz(over) {
  return Object.assign({
    id: "q1", kind: "quiz", category: "custom", title: null, slides: null,
    front: "q", back: "a", image: null, linkedLessonId: null,
    createdAt: 0, ease: 2.5, intervalDays: 0, dueAt: 0, reps: 0, lapses: 0,
    lastGrade: null, shownAt: null
  }, over || {})
}
function lesson(over) {
  return Object.assign({
    id: "l1", kind: "lesson", category: "technique", title: "T", slides: ["a", "b"],
    front: null, back: null, image: null, linkedLessonId: null,
    createdAt: 0, ease: 2.5, intervalDays: 0, dueAt: 0, reps: 0, lapses: 0,
    lastGrade: null, shownAt: null
  }, over || {})
}

// ── tolerant parsing ────────────────────────────────────────────────────────

test("parseConfig: empty / garbage -> defaults", () => {
  assert.deepEqual(Model.parseConfig(""), Model.defaultConfig())
  assert.deepEqual(Model.parseConfig("not json"), Model.defaultConfig())
  assert.deepEqual(Model.parseConfig("[1,2,3]"), Model.defaultConfig())
})

test("parseConfig: adopts known keys, ignores unknown", () => {
  const c = Model.parseConfig(JSON.stringify({ baseIntervalMin: 30, bogus: 9 }))
  assert.equal(c.baseIntervalMin, 30)
  assert.equal(c.bogus, undefined)
  assert.equal(c.minIntervalMin, Model.defaultConfig().minIntervalMin)
})
test("parseConfig: normalizes invalid ranges, counts, and snoozes", () => {
  const c = Model.parseConfig(JSON.stringify({
    enabled: "false",
    baseIntervalMin: -4,
    minIntervalMin: 0,
    maxIntervalMin: 0,
    quizBatchSize: 0.5,
    overdueTakeoverHours: -1,
    dismissTakeoverStreak: 2.9,
    dailyNewLessonCap: -3,
    lessonGapHours: -8,
    snoozeMinutes: [0, -5, "30", 15.8, 15.8]
  }))
  assert.equal(c.enabled, false)
  assert.equal(c.minIntervalMin, 1)
  assert.equal(c.baseIntervalMin, 1)
  assert.equal(c.maxIntervalMin, 1)
  assert.equal(c.quizBatchSize, 1)
  assert.equal(c.overdueTakeoverHours, 0)
  assert.equal(c.dismissTakeoverStreak, 2)
  assert.equal(c.dailyNewLessonCap, 0)
  assert.equal(c.lessonGapHours, 0)
  assert.deepEqual(c.snoozeMinutes, [15])
})


test("parseCards: empty / garbage -> seeded defaults", () => {
  assert.deepEqual(Model.parseCards(""), Model.defaultCards())
  assert.deepEqual(Model.parseCards("nope"), Model.defaultCards())
})

test("parseCards: drops malformed entries and de-dupes ids, keeps the rest", () => {
  const raw = JSON.stringify({ cards: [quiz({ id: "a" }), quiz({ id: "a" }), quiz({ id: "b" }), { front: "no id" }] })
  const parsed = Model.parseCards(raw)
  const ids = parsed.cards.map((c) => c.id).sort()
  assert.deepEqual(ids, ["a", "b"])
})

test("parseCards: drops cards with empty quiz or lesson content", () => {
  const parsed = Model.parseCards(JSON.stringify({ cards: [
    quiz({ id: "good" }),
    quiz({ id: "empty-front", front: "   " }),
    quiz({ id: "empty-back", back: "" }),
    lesson({ id: "empty-title", title: " " }),
    lesson({ id: "empty-slides", slides: [] })
  ] }))
  assert.deepEqual(parsed.cards.map((c) => c.id), ["good"])
})

test("parseState: malformed prompt kinds and empty card ids are dropped", () => {
  assert.equal(Model.parseState(JSON.stringify({ prompt: { kind: "bogus", cardIds: ["x"] } })).prompt, null)
  assert.equal(Model.parseState(JSON.stringify({ prompt: { kind: "checkin", cardIds: [] } })).prompt, null)
  assert.equal(Model.parseState(JSON.stringify({ prompt: { kind: "lesson", cardIds: [null, ""] } })).prompt, null)
})

test("parseCards: unknown kind coerces to quiz, unknown category to custom", () => {
  const parsed = Model.parseCards(JSON.stringify({ cards: [{ id: "x", kind: "bogus", category: "bogus", front: "f", back: "b" }] }))
  assert.equal(parsed.cards[0].kind, "quiz")
  assert.equal(parsed.cards[0].category, "custom")
})

test("parseState: empty / garbage -> defaults, no prompt", () => {
  const s = Model.parseState("")
  assert.deepEqual(s, Model.defaultState())
  assert.equal(s.prompt, null)
})

test("parseState: a prompt missing cardIds is dropped, not trusted", () => {
  const s = Model.parseState(JSON.stringify({ prompt: { kind: "checkin" } }))
  assert.equal(s.prompt, null)
})

test("parseState: a lesson prompt's slideIndex survives the round-trip (shell-restart resume)", () => {
  const s = Model.parseState(JSON.stringify({ prompt: { kind: "lesson", cardIds: ["seed-loci"], reason: "daily", slideIndex: 2 } }))
  assert.equal(s.prompt.slideIndex, 2)
})

test("parseState: an invalid slideIndex (negative, non-number, missing) is dropped rather than trusted", () => {
  assert.equal(Model.parseState(JSON.stringify({ prompt: { kind: "lesson", cardIds: ["x"], slideIndex: -1 } })).prompt.slideIndex, undefined)
  assert.equal(Model.parseState(JSON.stringify({ prompt: { kind: "lesson", cardIds: ["x"], slideIndex: "2" } })).prompt.slideIndex, undefined)
  assert.equal(Model.parseState(JSON.stringify({ prompt: { kind: "lesson", cardIds: ["x"] } })).prompt.slideIndex, undefined)
})

// ── seed content ─────────────────────────────────────────────────────────

test("defaultCards: seeds technique lessons and a trivia starter deck", () => {
  const cards = Model.defaultCards().cards
  assert.ok(cards.some((c) => c.kind === "lesson"), "has at least one lesson")
  assert.ok(cards.some((c) => c.kind === "quiz" && c.category === "trivia"), "has trivia quiz cards")
  const ids = cards.map((c) => c.id)
  assert.equal(new Set(ids).size, ids.length, "seed ids are unique")
})

// ── grading (SM-2-lite) ──────────────────────────────────────────────────

test("grade 'again': resets reps, adds a lapse, drops ease, due soon (not days)", () => {
  const c = quiz({ reps: 3, ease: 2.5, intervalDays: 10, lapses: 0 })
  const g = Model.grade(c, "again", 1000)
  assert.equal(g.reps, 0)
  assert.equal(g.lapses, 1)
  assert.equal(g.intervalDays, 0)
  assert.ok(g.ease < c.ease)
  assert.ok(g.dueAt - 1000 < Model.HOUR, "re-due within the hour, not days out")
  assert.equal(g.lastGrade, "again")
})

test("grade never mutates the input card", () => {
  const c = quiz({})
  const before = JSON.stringify(c)
  Model.grade(c, "good", 1000)
  assert.equal(JSON.stringify(c), before)
})

test("grade 'good' on a new card graduates to a short first interval and advances dueAt", () => {
  const c = quiz({})
  const g = Model.grade(c, "good", 1000)
  assert.equal(g.reps, 1)
  assert.ok(g.intervalDays >= 1)
  assert.equal(g.dueAt, 1000 + g.intervalDays * Model.DAY)
})

test("grade: easy grows the interval faster than good, which grows faster than hard", () => {
  let easyCard = quiz({}), goodCard = quiz({}), hardCard = quiz({})
  // graduate all three through two successful reps so interval math (rep 3+) is comparable
  for (const g of ["good", "good"]) {
    easyCard = Model.grade(easyCard, g, 0)
    goodCard = Model.grade(goodCard, g, 0)
    hardCard = Model.grade(hardCard, g, 0)
  }
  const easyNext = Model.grade(easyCard, "easy", 0)
  const goodNext = Model.grade(goodCard, "good", 0)
  const hardNext = Model.grade(hardCard, "hard", 0)
  assert.ok(easyNext.intervalDays > goodNext.intervalDays, "easy grows faster than good")
  assert.ok(goodNext.intervalDays > hardNext.intervalDays, "good grows faster than hard")
})

test("grade: ease is clamped to [1.3, 3.0] however many lapses/eases pile up", () => {
  let c = quiz({ ease: 1.35 })
  for (let i = 0; i < 20; i++) c = Model.grade(c, "again", i)
  assert.ok(c.ease >= 1.3)
  let d = quiz({ ease: 2.9 })
  for (let i = 0; i < 20; i++) d = Model.grade(d, "easy", i * Model.DAY)
  assert.ok(d.ease <= 3.0)
})

// ── due queues ───────────────────────────────────────────────────────────

test("dueQuizzes: only quiz cards at or before now, oldest due first", () => {
  const cards = [
    quiz({ id: "a", dueAt: 5000 }),
    quiz({ id: "b", dueAt: 1000 }),
    quiz({ id: "c", dueAt: 20000 }),
    lesson({ id: "d", dueAt: 0 })
  ]
  const due = Model.dueQuizzes(cards, 10000)
  assert.deepEqual(due.map((c) => c.id), ["b", "a"])
})

test("unseenLessons: only lessons with shownAt == null", () => {
  const cards = [lesson({ id: "a", shownAt: null }), lesson({ id: "b", shownAt: 5 }), quiz({ id: "c" })]
  assert.deepEqual(Model.unseenLessons(cards).map((c) => c.id), ["a"])
})

// ── the decision engine ──────────────────────────────────────────────────

test("decide: disabled config never prompts", () => {
  const d = Model.decide(cfg({ enabled: false }), state(), [quiz({ dueAt: 0 })], 100000)
  assert.equal(d.prompt, null)
})

test("decide: paused state never prompts until pauseUntilMs", () => {
  const d = Model.decide(cfg(), state({ pauseUntilMs: 200000 }), [quiz({ dueAt: 0 })], 100000)
  assert.equal(d.prompt, null)
})

test("decide: a brand-new, never-graded due card does NOT force a takeover", () => {
  // regression: seeded cards start at dueAt 0 (epoch); a naive 'now - dueAt'
  // overdue check would read that as ~decades overdue and always escalate.
  const cards = [quiz({ id: "a", dueAt: 0, reps: 0, lapses: 0 })]
  const d = Model.decide(cfg({ overdueTakeoverHours: 8 }), state(), cards, Date.now())
  assert.ok(d.prompt === null || d.prompt.kind !== "takeover", "new cards alone never trigger takeover")
})

test("decide: a previously-graded card overdue past the threshold escalates to takeover", () => {
  const now = 1_000_000_000_000
  const cards = [quiz({ id: "a", reps: 3, lapses: 0, dueAt: now - 9 * HOUR })]
  const d = Model.decide(cfg({ overdueTakeoverHours: 8, baseIntervalMin: 1 }), state({ lastPromptMs: 0 }), cards, now)
  assert.equal(d.prompt.kind, "takeover")
  assert.equal(d.prompt.reason, "overdue")
})

test("decide: dismissStreak at the threshold escalates the next prompt to takeover", () => {
  const now = 1_000_000_000_000
  const cards = [quiz({ id: "a", dueAt: now - MIN })]
  const d = Model.decide(cfg({ dismissTakeoverStreak: 3, baseIntervalMin: 1 }), state({ dismissStreak: 3, lastPromptMs: 0 }), cards, now)
  assert.equal(d.prompt.kind, "takeover")
  assert.equal(d.prompt.reason, "dismissed")
})

test("decide: due cards but interval not yet elapsed since lastPromptMs -> no prompt", () => {
  const now = 1_000_000_000_000
  const cards = [quiz({ id: "a", dueAt: now - MIN })]
  const d = Model.decide(cfg({ baseIntervalMin: 45 }), state({ lastPromptMs: now - MIN }), cards, now)
  assert.equal(d.prompt, null)
  assert.equal(d.reason, "not-yet")
})

test("decide: a non-escalated checkin batches at most quizBatchSize cards", () => {
  const now = 1_000_000_000_000
  const cards = Array.from({ length: 10 }, (_, i) => quiz({ id: "q" + i, dueAt: now - MIN }))
  const d = Model.decide(cfg({ quizBatchSize: 5, baseIntervalMin: 0 }), state({ lastPromptMs: 0 }), cards, now)
  assert.equal(d.prompt.kind, "checkin")
  assert.equal(d.prompt.cardIds.length, 5)
})

test("decide: an unseen lesson always wins over a due quiz, and always takes over", () => {
  const now = 1_000_000_000_000
  const cards = [quiz({ id: "q", dueAt: now - HOUR }), lesson({ id: "l", shownAt: null })]
  const d = Model.decide(cfg({ baseIntervalMin: 0 }), state({ lastPromptMs: 0 }), cards, now)
  assert.equal(d.prompt.kind, "lesson")
  assert.deepEqual(d.prompt.cardIds, ["l"])
})

test("decide: lesson rationed by dailyNewLessonCap", () => {
  const now = 1_000_000_000_000
  const cards = [lesson({ id: "l1", shownAt: null }), lesson({ id: "l2", shownAt: null })]
  const d = Model.decide(cfg({ dailyNewLessonCap: 1 }), state({ lessonsToday: 1 }), cards, now)
  assert.notEqual(d.reason, "new-lesson")
})

test("decide: lesson rationed by lessonGapHours since the last one", () => {
  const now = 1_000_000_000_000
  const cards = [lesson({ id: "l1", shownAt: null })]
  const d = Model.decide(cfg({ lessonGapHours: 20 }), state({ lastLessonMs: now - HOUR }), cards, now)
  assert.notEqual(d.reason, "new-lesson")
})

// ── lesson -> companion quiz linking ──────────────────────────────────────

test("markLessonSeen: sets shownAt and spins up a linked companion quiz due tomorrow", () => {
  const now = 1_000_000_000_000
  const cards = [lesson({ id: "l1", title: "Chunking", slides: ["a", "final slide"] })]
  const out = Model.markLessonSeen(cards, "l1", now)
  const l = out.find((c) => c.id === "l1")
  assert.equal(l.shownAt, now)
  const companion = out.find((c) => c.linkedLessonId === "l1")
  assert.ok(companion, "companion quiz card was created")
  assert.equal(companion.kind, "quiz")
  assert.equal(companion.back, "final slide")
  assert.equal(companion.dueAt, now + DAY)
})

test("markLessonSeen: calling it twice does not duplicate the companion card", () => {
  const now = 1_000_000_000_000
  let cards = [lesson({ id: "l1", title: "Chunking", slides: ["x"] })]
  cards = Model.markLessonSeen(cards, "l1", now)
  cards = Model.markLessonSeen(cards, "l1", now + MIN)
  const companions = cards.filter((c) => c.linkedLessonId === "l1")
  assert.equal(companions.length, 1)
})

// ── mutation helpers ─────────────────────────────────────────────────────

test("addQuizCard / dropCard round-trip", () => {
  const r = Model.addQuizCard([], { front: "f", back: "b", category: "trivia" }, { id: "x", now: 1 })
  assert.equal(r.cards.length, 1)
  assert.equal(r.cards[0].front, "f")
  assert.equal(Model.dropCard(r.cards, "x").length, 0)
})

test("addLessonCard stores slides in order", () => {
  const r = Model.addLessonCard([], { title: "T", slides: ["1", "2", "3"] }, { id: "x", now: 1 })
  assert.deepEqual(r.cards[0].slides, ["1", "2", "3"])
})

// ── daily bookkeeping ────────────────────────────────────────────────────

test("rollDaily: resets lessonsToday on a new day, keeps it on the same day", () => {
  const now = Date.parse("2026-09-05T10:00:00Z")
  const s1 = Model.rollDaily(state({ lessonsToday: 1, lessonsTodayDate: "2026-09-04" }), now)
  assert.equal(s1.lessonsToday, 0)
  const s2 = Model.rollDaily(state({ lessonsToday: 1, lessonsTodayDate: "2026-09-05" }), now)
  assert.equal(s2.lessonsToday, 1)
})

test("rollDaily: streakDays increments on a consecutive day, resets otherwise", () => {
  const now = Date.parse("2026-09-05T10:00:00Z")
  const consecutive = Model.rollDaily(state({ streakDays: 4, lastActiveDate: "2026-09-04" }), now)
  assert.equal(consecutive.streakDays, 5)
  const gap = Model.rollDaily(state({ streakDays: 4, lastActiveDate: "2026-09-01" }), now)
  assert.equal(gap.streakDays, 1)
})

test("rollDaily keys on the LOCAL calendar day (regression: dateKey was UTC via toISOString)", () => {
  // 00:30 local on 1 Jan — its UTC date is 31 Dec for any observer east of
  // UTC (the AEST dev box), which the old toISOString() dateKey returned.
  // Built from local parts so the expectation is the runner's own local day.
  const d = new Date(2026, 0, 1, 0, 30, 0)
  const today = Model.dateKey(d.getTime())
  assert.equal(today, "2026-01-01")
  assert.equal(Model.prevDateKey(today), "2025-12-31")
  const s = Model.rollDaily(state({ streakDays: 2, lastActiveDate: "2025-12-31" }), d.getTime())
  assert.equal(s.streakDays, 3)
  assert.equal(s.lastActiveDate, "2026-01-01")
})

// ── trivia seed + merge ────────────────────────────────────────────────

test("triviaSeedCards: a non-empty, offline, unique-id trivia set", () => {
  const cards = Model.triviaSeedCards()
  assert.ok(cards.length > 0)
  assert.ok(cards.every((c) => c.kind === "quiz" && c.category === "trivia"))
  const ids = cards.map((c) => c.id)
  assert.equal(new Set(ids).size, ids.length)
})

test("mergeCards: appends only additions whose id isn't already present", () => {
  const existing = [quiz({ id: "a" }), quiz({ id: "b" })]
  const additions = [quiz({ id: "b" }), quiz({ id: "c" })]
  const r = Model.mergeCards(existing, additions)
  assert.equal(r.addedCount, 1)
  assert.deepEqual(r.cards.map((c) => c.id), ["a", "b", "c"])
})

test("mergeCards: re-applying the same trivia seed twice is a no-op the second time", () => {
  const seed = Model.triviaSeedCards()
  const first = Model.mergeCards([], seed)
  assert.equal(first.addedCount, seed.length)
  const second = Model.mergeCards(first.cards, Model.triviaSeedCards())
  assert.equal(second.addedCount, 0)
  assert.equal(second.cards.length, first.cards.length)
})

// ── multiple-choice clue ─────────────────────────────────────────────────

test("buildChoices: includes the correct answer, exactly once, at correctIndex", () => {
  const target = quiz({ id: "t", back: "Correct", category: "trivia" })
  const pool = [
    target,
    quiz({ id: "d1", back: "Wrong A", category: "trivia" }),
    quiz({ id: "d2", back: "Wrong B", category: "trivia" }),
    quiz({ id: "d3", back: "Wrong C", category: "misc" })
  ]
  const r = Model.buildChoices(target, pool, 4, () => 0.5)
  assert.equal(r.options.filter((o) => o === "Correct").length, 1)
  assert.equal(r.options[r.correctIndex], "Correct")
  assert.equal(r.options.length, 4)
})

test("buildChoices: never duplicates a distractor's text, even across categories", () => {
  const target = quiz({ id: "t", back: "Correct", category: "trivia" })
  const pool = [
    target,
    quiz({ id: "d1", back: "Same Text", category: "trivia" }),
    quiz({ id: "d2", back: "Same Text", category: "misc" }),
    quiz({ id: "d3", back: "Unique", category: "misc" })
  ]
  const r = Model.buildChoices(target, pool, 4, () => 0.5)
  const counts = {}
  r.options.forEach((o) => { counts[o] = (counts[o] || 0) + 1 })
  assert.ok(Object.values(counts).every((n) => n === 1), "no option repeats")
})

test("buildChoices: degrades to fewer options (never throws) when the deck is too small", () => {
  const target = quiz({ id: "t", back: "Correct" })
  const r = Model.buildChoices(target, [target], 4, () => 0.5)
  assert.equal(r.options.length, 1)
  assert.equal(r.options[0], "Correct")
  assert.equal(r.correctIndex, 0)
})

test("buildChoices: prefers same-category distractors when there are enough", () => {
  const target = quiz({ id: "t", back: "Correct", category: "trivia" })
  const pool = [
    target,
    quiz({ id: "d1", back: "Same-cat A", category: "trivia" }),
    quiz({ id: "d2", back: "Same-cat B", category: "trivia" }),
    quiz({ id: "d3", back: "Other-cat", category: "misc" })
  ]
  const r = Model.buildChoices(target, pool, 3, () => 0)
  assert.ok(r.options.includes("Same-cat A") || r.options.includes("Same-cat B"))
  assert.ok(!r.options.includes("Other-cat"), "same-category distractors are preferred over other-category ones")
})

// ── due-time formatting ──────────────────────────────────────────────────

test("formatDue: rounds up into the next unit instead of showing the top of the unit below (regression)", () => {
  // 1ms under an hour used to round to "60m overdue" / "in 60m" instead of
  // bucketing into hours; 1ms under a day used to do the same at "24h".
  assert.equal(Model.formatDue(-(HOUR - 1), 0), "1h overdue")
  assert.equal(Model.formatDue(-(DAY - 1), 0), "1d overdue")
  assert.equal(Model.formatDue(HOUR - 1, 0), "in 1h")
  assert.equal(Model.formatDue(DAY - 1, 0), "in 1d")
})

test("formatDue: ordinary values stay in their natural unit", () => {
  assert.equal(Model.formatDue(0, 0), "due now")
  assert.equal(Model.formatDue(-5 * MIN, 0), "5m overdue")
  assert.equal(Model.formatDue(-3 * HOUR, 0), "3h overdue")
  assert.equal(Model.formatDue(-2 * DAY, 0), "2d overdue")
  assert.equal(Model.formatDue(5 * MIN, 0), "in 5m")
  assert.equal(Model.formatDue(3 * HOUR, 0), "in 3h")
})

// ── stats ────────────────────────────────────────────────────────────────

test("stats: retentionRate is null with no reviews yet, else success fraction", () => {
  assert.equal(Model.stats([quiz({})], state()).retentionRate, null)
  const cards = [quiz({ id: "a", reps: 1, lastGrade: "good" }), quiz({ id: "b", reps: 1, lastGrade: "again" })]
  assert.equal(Model.stats(cards, state()).retentionRate, 0.5)
})
