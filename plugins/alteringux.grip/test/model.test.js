"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const MIN = 60_000
const HOUR = 60 * MIN

function cfg(over) {
  return Object.assign(Model.defaultConfig(), over || {})
}
function state(over) {
  return Object.assign(Model.defaultState(), over || {})
}
function tasksOf(list) {
  return { version: 1, tasks: list }
}
function task(over) {
  return Object.assign(
    { id: "t1", text: "thing", source: "typed", due: null, hard: false, done: false, created: 0 },
    over || {}
  )
}

// ── tolerant parsing ────────────────────────────────────────────────────────

test("parseConfig: empty / garbage → defaults", () => {
  assert.deepEqual(Model.parseConfig(""), Model.defaultConfig())
  assert.deepEqual(Model.parseConfig("not json"), Model.defaultConfig())
  assert.deepEqual(Model.parseConfig("[1,2,3]"), Model.defaultConfig())
})

test("parseConfig: adopts known keys, ignores unknown, keeps sane types", () => {
  const c = Model.parseConfig(JSON.stringify({ baseIntervalMin: 30, bogus: 9, routines: [{ id: "m", text: "Meds" }] }))
  assert.equal(c.baseIntervalMin, 30)
  assert.equal(c.bogus, undefined)
  assert.equal(c.routines.length, 1)
  assert.equal(c.minIntervalMin, Model.defaultConfig().minIntervalMin)
})

test("parseConfig: a non-array routines value degrades to []", () => {
  assert.deepEqual(Model.parseConfig(JSON.stringify({ routines: "nope" })).routines, [])
})

test("parseState: empty / garbage → defaults (disabled, no prompt)", () => {
  const s = Model.parseState("")
  assert.equal(s.enabled, false)
  assert.equal(s.prompt, null)
  assert.deepEqual(Model.parseState("{{{"), s)
})

test("parseState: an unknown prompt kind is dropped", () => {
  assert.equal(Model.parseState(JSON.stringify({ prompt: { kind: "wat" } })).prompt, null)
  assert.equal(Model.parseState(JSON.stringify({ prompt: { kind: "takeover", since: 5 } })).prompt.kind, "takeover")
})

test("parseTasks: empty / garbage → { version, tasks: [] }", () => {
  assert.deepEqual(Model.parseTasks(""), { version: 1, tasks: [] })
  assert.deepEqual(Model.parseTasks("nope"), { version: 1, tasks: [] })
  assert.deepEqual(Model.parseTasks(JSON.stringify({ tasks: "x" })), { version: 1, tasks: [] })
})

test("parseTasks: rows are normalised, unusable rows dropped", () => {
  const parsed = Model.parseTasks(
    JSON.stringify({
      tasks: [
        { id: "a", text: "keep", due: 123, hard: 1 },
        { text: "no id" },
        { id: "b" },
        "garbage",
        { id: "c", text: "  ", done: true },
      ],
    })
  )
  assert.deepEqual(parsed.tasks.map((t) => t.id), ["a"])
  assert.equal(parsed.tasks[0].hard, true)
  assert.equal(parsed.tasks[0].done, false)
  assert.equal(parsed.tasks[0].source, "typed")
})

// ── task queries ───────────────────────────────────────────────────────────

test("openTasks: only not-done", () => {
  const t = tasksOf([task({ id: "a" }), task({ id: "b", done: true })])
  assert.deepEqual(Model.openTasks(t).map((x) => x.id), ["a"])
})

test("overdueTasks: open + past due only", () => {
  const now = 10 * HOUR
  const t = tasksOf([
    task({ id: "past", due: now - MIN }),
    task({ id: "future", due: now + MIN }),
    task({ id: "nodue", due: null }),
    task({ id: "done", due: now - HOUR, done: true }),
  ])
  assert.deepEqual(Model.overdueTasks(t, now).map((x) => x.id), ["past"])
})

test("topTasks: hard first, then soonest due, then oldest; nulls last", () => {
  const now = 10 * HOUR
  const t = tasksOf([
    task({ id: "soft-soon", due: now + MIN, created: 5 }),
    task({ id: "hard-late", due: now + 5 * HOUR, hard: true, created: 5 }),
    task({ id: "soft-nodue-old", due: null, created: 1 }),
    task({ id: "soft-nodue-new", due: null, created: 9 }),
    task({ id: "done", done: true }),
  ])
  assert.deepEqual(Model.topTasks(t, now, 3).map((x) => x.id), ["hard-late", "soft-soon", "soft-nodue-old"])
})

// ── adaptive cadence ───────────────────────────────────────────────────────

test("nextIntervalMinutes: clear wall → max interval", () => {
  assert.equal(Model.nextIntervalMinutes(cfg(), state(), tasksOf([]), 0), cfg().maxIntervalMin)
})

test("nextIntervalMinutes: open tasks, calm → base interval", () => {
  const t = tasksOf([task({ due: null })])
  assert.equal(Model.nextIntervalMinutes(cfg(), state(), t, 0), cfg().baseIntervalMin)
})

test("nextIntervalMinutes: an overdue task collapses to the min interval", () => {
  const now = 10 * HOUR
  const t = tasksOf([task({ due: now - MIN })])
  assert.equal(Model.nextIntervalMinutes(cfg(), state(), t, now), cfg().minIntervalMin)
})

test("nextIntervalMinutes: a dismissal streak shortens the interval, floored at min", () => {
  const t = tasksOf([task({ due: null })])
  const a = Model.nextIntervalMinutes(cfg(), state({ dismissStreak: 2 }), t, 0)
  const b = Model.nextIntervalMinutes(cfg(), state({ dismissStreak: 3 }), t, 0)
  assert.ok(a < cfg().baseIntervalMin)
  assert.ok(b < a)
  assert.ok(b >= cfg().minIntervalMin)
  assert.equal(Model.nextIntervalMinutes(cfg(), state({ dismissStreak: 50 }), t, 0), cfg().minIntervalMin)
})

// ── escalation ─────────────────────────────────────────────────────────────

test("escalationReason: none when nothing is wrong", () => {
  assert.equal(Model.escalationReason(cfg(), state(), tasksOf([task({ due: null })]), 0), null)
})

test("escalationReason: a hard task at/after its due time → 'deadline'", () => {
  const now = 10 * HOUR
  const t = tasksOf([task({ hard: true, due: now })])
  assert.equal(Model.escalationReason(cfg(), state(), t, now), "deadline")
  // not yet due → no deadline escalation
  assert.equal(Model.escalationReason(cfg(), state(), tasksOf([task({ hard: true, due: now + MIN })]), now), null)
})

test("escalationReason: a task overdue past the takeover window → 'overdue'", () => {
  const now = 10 * HOUR
  const c = cfg({ overdueTakeoverHours: 2 })
  assert.equal(Model.escalationReason(c, state(), tasksOf([task({ due: now - 3 * HOUR })]), now), "overdue")
  assert.equal(Model.escalationReason(c, state(), tasksOf([task({ due: now - HOUR })]), now), null)
})

test("escalationReason: too many dismissals in a row → 'dismissed'", () => {
  const c = cfg({ dismissTakeoverStreak: 3 })
  assert.equal(Model.escalationReason(c, state({ dismissStreak: 3 }), tasksOf([task({ due: null })]), 0), "dismissed")
  assert.equal(Model.escalationReason(c, state({ dismissStreak: 2 }), tasksOf([task({ due: null })]), 0), null)
})

test("escalationReason: deadline outranks overdue outranks dismissed", () => {
  const now = 10 * HOUR
  const c = cfg({ overdueTakeoverHours: 2, dismissTakeoverStreak: 3 })
  const t = tasksOf([task({ id: "d", hard: true, due: now - 3 * HOUR })])
  assert.equal(Model.escalationReason(c, state({ dismissStreak: 5 }), t, now), "deadline")
})

// ── the decision ───────────────────────────────────────────────────────────

test("decide: disabled → never prompts", () => {
  const now = 10 * HOUR
  const t = tasksOf([task({ hard: true, due: now - HOUR })])
  assert.equal(Model.decide(cfg(), state({ enabled: false, lastPromptMs: 0 }), t, now).prompt, null)
})

test("decide: paused → never prompts", () => {
  const now = 10 * HOUR
  const s = state({ enabled: true, lastPromptMs: 0, pauseUntilMs: now + HOUR })
  assert.equal(Model.decide(cfg(), s, tasksOf([task({ due: now - 5 * HOUR })]), now).prompt, null)
})

test("decide: an already-pending prompt is preserved verbatim", () => {
  const now = 10 * HOUR
  const s = state({ enabled: true, prompt: { kind: "checkin", since: 1 }, lastPromptMs: now })
  const d = Model.decide(cfg(), s, tasksOf([task({ hard: true, due: now - HOUR })]), now)
  assert.deepEqual(d.prompt, "checkin") // not upgraded to takeover mid-flight
})

test("decide: before the interval elapses → no prompt", () => {
  const now = 10 * HOUR
  const c = cfg({ baseIntervalMin: 20 })
  const s = state({ enabled: true, lastPromptMs: now - 5 * MIN })
  assert.equal(Model.decide(c, s, tasksOf([task({ due: null })]), now).prompt, null)
})

test("decide: an empty wall never prompts, even with the interval long elapsed", () => {
  const now = 10 * HOUR
  const s = state({ enabled: true, lastPromptMs: 0 })
  assert.equal(Model.decide(cfg(), s, tasksOf([]), now).prompt, null)
  assert.equal(Model.decide(cfg(), s, tasksOf([task({ done: true })]), now).prompt, null)
})

test("decide: a pending prompt survives the wall being cleared", () => {
  const now = 10 * HOUR
  const s = state({ enabled: true, prompt: { kind: "takeover", since: 1 }, lastPromptMs: now })
  assert.equal(Model.decide(cfg(), s, tasksOf([]), now).prompt, "takeover")
})

test("decide: interval elapsed with calm open tasks → check-in", () => {
  const now = 10 * HOUR
  const c = cfg({ baseIntervalMin: 20 })
  const s = state({ enabled: true, lastPromptMs: now - 21 * MIN })
  assert.equal(Model.decide(c, s, tasksOf([task({ due: null })]), now).prompt, "checkin")
})

test("decide: interval elapsed while overdue past window → takeover", () => {
  const now = 10 * HOUR
  const c = cfg({ baseIntervalMin: 20, minIntervalMin: 8, overdueTakeoverHours: 2 })
  const s = state({ enabled: true, lastPromptMs: now - 30 * MIN })
  assert.equal(Model.decide(c, s, tasksOf([task({ due: now - 3 * HOUR })]), now).prompt, "takeover")
})

test("decide: a hard deadline fires a takeover immediately, ignoring the interval", () => {
  const now = 10 * HOUR
  const c = cfg({ baseIntervalMin: 20 })
  const s = state({ enabled: true, lastPromptMs: now }) // just prompted → interval not elapsed
  const d = Model.decide(c, s, tasksOf([task({ hard: true, due: now })]), now)
  assert.equal(d.prompt, "takeover")
  assert.equal(d.reason, "deadline")
})

test("decide: dismissed-streak escalation waits for the (shortened) interval", () => {
  const now = 10 * HOUR
  const c = cfg({ baseIntervalMin: 20, minIntervalMin: 8, dismissTakeoverStreak: 3 })
  const t = tasksOf([task({ due: null })])
  const fresh = state({ enabled: true, dismissStreak: 4, lastPromptMs: now - 2 * MIN })
  assert.equal(Model.decide(c, fresh, t, now).prompt, null)
  const ripe = state({ enabled: true, dismissStreak: 4, lastPromptMs: now - 20 * MIN })
  assert.equal(Model.decide(c, ripe, t, now).prompt, "takeover")
})

// ── mutations ──────────────────────────────────────────────────────────────

test("addTask: appends a normalised typed row and returns a new object", () => {
  const before = tasksOf([])
  const after = Model.addTask(before, { text: "  call dentist  ", due: 123, hard: true }, { id: "x1", now: 50 })
  assert.notEqual(after, before)
  assert.equal(before.tasks.length, 0)
  assert.deepEqual(after.tasks[0], {
    id: "x1", text: "call dentist", source: "typed", due: 123, hard: true, done: false, created: 50,
  })
})

test("addTask: blank text is rejected (returns the same state)", () => {
  const before = tasksOf([task()])
  assert.equal(Model.addTask(before, { text: "   " }, { id: "x", now: 1 }), before)
})

test("completeTask / dropTask: by id, no-op on unknown id", () => {
  const t = tasksOf([task({ id: "a" }), task({ id: "b" })])
  assert.equal(Model.completeTask(t, "a").tasks.find((x) => x.id === "a").done, true)
  assert.deepEqual(Model.dropTask(t, "b").tasks.map((x) => x.id), ["a"])
  assert.equal(Model.completeTask(t, "zzz").tasks.filter((x) => x.done).length, 0)
})

test("syncRoutines: seeds one open task per configured routine on a new day", () => {
  const c = cfg({ routines: [{ id: "meds", text: "Take meds" }, { id: "inbox", text: "Inbox zero" }] })
  const out = Model.syncRoutines(tasksOf([task({ id: "keep" })]), c, "2026-09-03")
  const routineRows = out.tasks.filter((t) => t.source === "routine")
  assert.deepEqual(routineRows.map((r) => r.id).sort(), ["routine:inbox:2026-09-03", "routine:meds:2026-09-03"])
  assert.ok(out.tasks.some((t) => t.id === "keep"))
  assert.ok(routineRows.every((r) => r.done === false))
})

test("syncRoutines: is idempotent within the same day and preserves a ticked routine", () => {
  const c = cfg({ routines: [{ id: "meds", text: "Take meds" }] })
  let out = Model.syncRoutines(tasksOf([]), c, "2026-09-03")
  out = Model.completeTask(out, "routine:meds:2026-09-03")
  const again = Model.syncRoutines(out, c, "2026-09-03")
  assert.equal(again.tasks.filter((t) => t.source === "routine").length, 1)
  assert.equal(again.tasks.find((t) => t.id === "routine:meds:2026-09-03").done, true)
})

test("syncRoutines: a new day drops yesterday's routine rows and reseeds", () => {
  const c = cfg({ routines: [{ id: "meds", text: "Take meds" }] })
  const yesterday = Model.syncRoutines(tasksOf([]), c, "2026-09-02")
  const today = Model.syncRoutines(yesterday, c, "2026-09-03")
  const rows = today.tasks.filter((t) => t.source === "routine")
  assert.deepEqual(rows.map((r) => r.id), ["routine:meds:2026-09-03"])
})

test("syncRoutines: removing a routine from config clears its rows", () => {
  const c1 = cfg({ routines: [{ id: "meds", text: "Take meds" }] })
  const seeded = Model.syncRoutines(tasksOf([]), c1, "2026-09-03")
  const cleared = Model.syncRoutines(seeded, cfg({ routines: [] }), "2026-09-03")
  assert.equal(cleared.tasks.filter((t) => t.source === "routine").length, 0)
})

// ── formatting ─────────────────────────────────────────────────────────────

test("formatDue: future and past phrasings", () => {
  assert.equal(Model.formatDue(null, 0), "")
  assert.equal(Model.formatDue(30 * MIN, 0), "in 30m")
  assert.equal(Model.formatDue(3 * HOUR, 0), "in 3h")
  assert.equal(Model.formatDue(50 * HOUR, 0), "in 2d")
  assert.equal(Model.formatDue(-5 * MIN, 0), "5m overdue")
  assert.equal(Model.formatDue(-4 * HOUR, 0), "4h overdue")
  assert.equal(Model.formatDue(-30 * HOUR, 0), "1d overdue")
})

test("summary: counts open / overdue and picks the loudest tone", () => {
  const now = 10 * HOUR
  const calm = Model.summary(tasksOf([task({ due: null }), task({ id: "b", due: now + HOUR })]), state({ enabled: true }), now)
  assert.deepEqual([calm.open, calm.overdue, calm.tone], [2, 0, "calm"])

  const hot = Model.summary(tasksOf([task({ due: now - 5 * HOUR })]), state({ enabled: true }), now)
  assert.equal(hot.overdue, 1)
  assert.equal(hot.tone, "overdue")

  const pending = Model.summary(tasksOf([task({ due: null })]), state({ enabled: true, prompt: { kind: "checkin", since: 1 } }), now)
  assert.equal(pending.tone, "prompt")

  const paused = Model.summary(tasksOf([task({ due: now - 5 * HOUR })]), state({ enabled: true, pauseUntilMs: now + HOUR }), now)
  assert.equal(paused.tone, "paused")

  const off = Model.summary(tasksOf([task()]), state({ enabled: false }), now)
  assert.equal(off.tone, "off")
})
