"use strict"
const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../Model.js")

const DAY = M.DAY

test("parseConfig fills defaults and clamps", () => {
  const d = M.parseConfig("not json")
  assert.equal(d.enabled, false)
  assert.equal(d.poolSize, 24)
  assert.ok(Array.isArray(d.wallhaven.queries) && d.wallhaven.queries.length > 0)

  const c = M.parseConfig(JSON.stringify({ enabled: true, poolSize: 5, wallhaven: { categories: "111" }, visionQuestions: true }))
  assert.equal(c.enabled, true)
  assert.equal(c.poolSize, 5)
  assert.equal(c.wallhaven.categories, "111")
  assert.equal(c.wallhaven.purity, "100")   // untouched default kept
  assert.equal(c.visionQuestions, true)
})

test("parseState is total and parses a round", () => {
  const s = M.parseState("{bad")
  assert.equal(s.round, null)
  assert.equal(s.session.level, 3)

  const s2 = M.parseState(JSON.stringify({
    round: { id: "r1", truth: [{ x: 0.5, y: 0.5, w: 0.1, h: 0.1 }], clicks: [{ x: 0.5, y: 0.5 }], sessionType: "scheduled", cardId: "s1" },
    session: { type: "drill", level: 12 }
  }))
  assert.equal(s2.round.id, "r1")
  assert.equal(s2.round.truth.length, 1)
  assert.equal(s2.round.sessionType, "scheduled")
  assert.equal(s2.session.level, M.MAX_LEVEL)   // clamped
})

test("parseCards dedupes and drops id-less", () => {
  const c = M.parseCards(JSON.stringify({ cards: [
    { id: "a", sceneId: "x1" }, { id: "a", sceneId: "x2" }, { sceneId: "x3" }
  ] }))
  assert.equal(c.cards.length, 1)
  assert.equal(c.cards[0].sceneId, "x1")
})

test("levelParams ramps exposure down and changes up", () => {
  const lo = M.levelParams(1)
  const hi = M.levelParams(8)
  assert.ok(lo.exposureMs > hi.exposureMs)
  assert.equal(lo.changeCount, 1)
  assert.equal(hi.changeCount, 4)
  assert.equal(M.levelParams(4).changeCount, 2)
})

test("nextLevel moves on grade and clamps", () => {
  assert.equal(M.nextLevel(3, "good"), 4)
  assert.equal(M.nextLevel(3, "easy"), 4)
  assert.equal(M.nextLevel(3, "hard"), 3)
  assert.equal(M.nextLevel(3, "again"), 2)
  assert.equal(M.nextLevel(8, "good"), 8)
  assert.equal(M.nextLevel(1, "again"), 1)
})

test("scoreHits: exact hit, miss, and extra-click penalty", () => {
  const truth = [
    { x: 0.2, y: 0.2, w: 0.08, h: 0.08 },
    { x: 0.7, y: 0.7, w: 0.08, h: 0.08 }
  ]
  // one dead-centre hit, one far miss
  const r = M.scoreHits(truth, [{ x: 0.24, y: 0.24 }, { x: 0.05, y: 0.9 }])
  assert.equal(r.hits, 1)
  assert.equal(r.total, 2)
  assert.equal(r.extraClicks, 1)
  assert.equal(r.clickResults[0].hit, true)
  assert.equal(r.clickResults[1].hit, false)
  // accuracy = 1/2 - 0.5*(1/2) = 0.25
  assert.ok(Math.abs(r.accuracy - 0.25) < 1e-9)
  assert.deepEqual(r.missedTruth, [1])
})

test("scoreHits: both found -> easy grade", () => {
  const truth = [
    { x: 0.2, y: 0.2, w: 0.1, h: 0.1 },
    { x: 0.7, y: 0.6, w: 0.1, h: 0.1 }
  ]
  const r = M.scoreHits(truth, [{ x: 0.25, y: 0.25 }, { x: 0.75, y: 0.65 }])
  assert.equal(r.hits, 2)
  assert.equal(r.accuracy, 1)
  assert.equal(r.grade, "easy")
})

test("scoreHits: one click cannot match two truths", () => {
  const truth = [
    { x: 0.5, y: 0.5, w: 0.1, h: 0.1 },
    { x: 0.52, y: 0.52, w: 0.1, h: 0.1 }
  ]
  const r = M.scoreHits(truth, [{ x: 0.51, y: 0.51 }])
  assert.equal(r.hits, 1)
})

test("gradeForAccuracy thresholds", () => {
  assert.equal(M.gradeForAccuracy(0.95), "easy")
  assert.equal(M.gradeForAccuracy(0.7), "good")
  assert.equal(M.gradeForAccuracy(0.4), "hard")
  assert.equal(M.gradeForAccuracy(0.1), "again")
})

test("grade: SM-2 lapse resets, success compounds, tracks bestAccuracy", () => {
  const now = 1_000_000_000_000
  const card = M.parseCard({ id: "s1", sceneId: "x", reps: 3, intervalDays: 10, ease: 2.5, bestAccuracy: 0.4 })

  const again = M.grade(card, "again", now, 0.2)
  assert.equal(again.reps, 0)
  assert.equal(again.lapses, 1)
  assert.equal(again.dueAt, now + 10 * M.MINUTE)
  assert.ok(again.ease < card.ease)
  assert.equal(again.bestAccuracy, 0.4)   // a worse round doesn't lower the best

  const good = M.grade(card, "good", now, 0.8)
  assert.equal(good.reps, 4)
  assert.ok(good.dueAt > now + 5 * DAY)
  assert.equal(good.bestAccuracy, 0.8)
})

test("decide: disabled / paused / not-yet / due / takeover", () => {
  const cfg = M.defaultConfig()
  cfg.enabled = true
  const now = 2_000_000_000_000

  assert.equal(M.decide(M.defaultConfig(), M.defaultState(), [], now).reason, "disabled")

  const paused = M.parseState(JSON.stringify({ pauseUntilMs: now + M.HOUR }))
  assert.equal(M.decide(cfg, paused, [], now).reason, "paused")

  const dueCard = M.parseCard({ id: "s1", sceneId: "x", dueAt: now - M.HOUR, reps: 2, intervalDays: 3 })

  // cadence not elapsed yet
  const fresh = M.parseState(JSON.stringify({ lastPromptMs: now - M.MINUTE }))
  assert.equal(M.decide(cfg, fresh, [dueCard], now).reason, "not-yet")

  // cadence elapsed -> a plain check-in
  const stale = M.parseState(JSON.stringify({ lastPromptMs: now - 40 * M.HOUR }))
  const d1 = M.decide(cfg, stale, [dueCard], now)
  assert.equal(d1.prompt.kind, "checkin")
  assert.equal(d1.prompt.cardIds[0], "s1")

  // badly overdue reviewed card -> takeover
  const overdue = M.parseCard({ id: "s2", sceneId: "y", dueAt: now - 10 * DAY, reps: 4, intervalDays: 6 })
  const d2 = M.decide(cfg, stale, [overdue], now)
  assert.equal(d2.prompt.kind, "takeover")
  assert.equal(d2.reason, "overdue")

  // dismiss streak -> takeover
  const dismissed = M.parseState(JSON.stringify({ lastPromptMs: now - 40 * M.HOUR, dismissStreak: 3 }))
  assert.equal(M.decide(cfg, dismissed, [dueCard], now).prompt.kind, "takeover")
})

test("decide: a brand-new card is due but never forces a takeover", () => {
  const cfg = M.defaultConfig(); cfg.enabled = true
  const now = 2_000_000_000_000
  const newCard = M.parseCard({ id: "s1", sceneId: "x", dueAt: 0, reps: 0, lapses: 0 })
  const stale = M.parseState(JSON.stringify({ lastPromptMs: now - 40 * M.HOUR }))
  assert.equal(M.decide(cfg, stale, [newCard], now).prompt.kind, "checkin")
})

test("rollDaily resets today counter and bumps streak", () => {
  const now = Date.parse("2026-09-06T09:00:00Z")
  const y = M.prevDateKey(M.dateKey(now))
  const s = M.parseState(JSON.stringify({ roundsToday: 5, roundsTodayDate: y, streakDays: 4, lastActiveDate: y }))
  const r = M.rollDaily(s, now)
  assert.equal(r.roundsToday, 0)
  assert.equal(r.streakDays, 5)

  const gap = M.parseState(JSON.stringify({ streakDays: 4, lastActiveDate: M.dateKey(now - 3 * DAY) }))
  assert.equal(M.rollDaily(gap, now).streakDays, 1)
})

test("rollDaily keys on the LOCAL calendar day (regression: dateKey was UTC via toISOString)", () => {
  // 00:30 local on 1 Jan — its UTC date is 31 Dec for any observer east of
  // UTC (the AEST dev box), which the old toISOString() dateKey returned.
  const d = new Date(2026, 0, 1, 0, 30, 0)
  const today = M.dateKey(d.getTime())
  assert.equal(today, "2026-01-01")
  assert.equal(M.prevDateKey(today), "2025-12-31")
  const s = M.parseState(JSON.stringify({ streakDays: 2, lastActiveDate: "2025-12-31" }))
  const r = M.rollDaily(s, d.getTime())
  assert.equal(r.streakDays, 3)
  assert.equal(r.lastActiveDate, "2026-01-01")
})

test("startRound assembles from a spec", () => {
  const spec = { cardId: "s1", sceneId: "abc", imageA: "file://a", imageB: "file://b",
    truth: [{ x: 0.1, y: 0.1, w: 0.1, h: 0.1 }, { x: 0.4, y: 0.4, w: 0.1, h: 0.1 }] }
  const r = M.startRound(spec, "scheduled", 5, M.defaultConfig(), 1234567890)
  assert.equal(r.sessionType, "scheduled")
  assert.equal(r.cardId, "s1")
  assert.equal(r.level, 5)
  assert.equal(r.changeCount, 2)
  assert.equal(r.truth.length, 2)
  assert.equal(r.clicks.length, 0)
})

test("addCardFromRound appends a due card", () => {
  const round = M.parseRound({ id: "r1", sceneId: "abc", imageA: "file://a", imageB: "file://b",
    truth: [{ x: 0.1, y: 0.1, w: 0.1, h: 0.1 }], level: 4 })
  const now = 5_000_000_000_000
  const r = M.addCardFromRound([], round, now)
  assert.equal(r.cards.length, 1)
  assert.equal(r.cards[0].sceneId, "abc")
  assert.equal(r.cards[0].dueAt, now + DAY)
})
