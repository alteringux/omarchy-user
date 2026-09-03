// Node's built-in test runner, no install:
//   node --test test/model.test.js
const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../Model.js")

test("parseState: empty / garbage -> idle default", () => {
  assert.equal(M.parseState("").active, false)
  assert.equal(M.parseState("not json").phase, "idle")
  assert.deepEqual(M.parseState("{}").steps, [])
})

test("parseState: normalises steps and defaults optional to true", () => {
  const s = M.parseState(JSON.stringify({
    active: true, ritual: "focus", label: "Ship it", phase: "running",
    steps: [
      { cli: "omarchy-pomodoro", args: ["start"], when: "start", status: "ok", ms: 12 },
      { cli: "protonvpn-rotate", args: ["connect"], status: "skipped", optional: true, error: "exit 1" },
      { when: "end" }
    ]
  }))
  assert.equal(s.active, true)
  assert.equal(s.steps.length, 3)
  assert.equal(s.steps[0].status, "ok")
  assert.equal(s.steps[2].optional, true)      // missing -> true
  assert.equal(s.steps[2].cli, "")             // missing -> ""
  assert.equal(s.steps[2].when, "end")
})

test("stepCounts tallies by status", () => {
  const s = M.parseState(JSON.stringify({
    steps: [
      { status: "ok" }, { status: "ok" }, { status: "skipped" },
      { status: "failed" }, { status: "pending" }
    ]
  }))
  const c = M.stepCounts(s)
  assert.deepEqual(c, { done: 4, total: 5, ok: 2, skipped: 1, failed: 1, pending: 1 })
})

test("widgetLabel: empty when idle, name + progress when active", () => {
  assert.equal(M.widgetLabel(M.parseState("{}")), "")
  const s = M.parseState(JSON.stringify({
    active: true, label: "Focus",
    steps: [{ status: "ok" }, { status: "ok" }, { status: "pending" }]
  }))
  assert.equal(M.widgetLabel(s), "Focus  2/3")
})

test("ritualName falls back label -> ritual id -> 'ritual'", () => {
  assert.equal(M.ritualName({ label: "Deep Work" }), "Deep Work")
  assert.equal(M.ritualName({ label: "", ritual: "focus" }), "focus")
  assert.equal(M.ritualName({ label: "", ritual: "" }), "ritual")
})

test("progressText summarises resolved steps", () => {
  const s = M.parseState(JSON.stringify({
    steps: [{ status: "ok" }, { status: "skipped" }, { status: "pending" }]
  }))
  assert.equal(M.progressText(s), "2 / 3 steps  ·  1 ok, 1 skipped")
  assert.equal(M.progressText(M.parseState("{}")), "no steps")
})

test("stepGlyph maps every status", () => {
  assert.equal(M.stepGlyph("ok"), "✓")
  assert.equal(M.stepGlyph("skipped"), "·")
  assert.equal(M.stepGlyph("failed"), "✗")
  assert.equal(M.stepGlyph("pending"), "○")
})

test("stepText joins cli + args", () => {
  assert.equal(M.stepText({ cli: "omarchy-timers", args: ["add", "draft"] }), "omarchy-timers add draft")
  assert.equal(M.stepText({ cli: "flow", args: [] }), "flow")
  assert.equal(M.stepText({}), "(no cli)")
})

test("parseRitualList tolerates junk and keeps shaped entries", () => {
  const raw = JSON.stringify([
    { id: "focus", label: "Focus", description: "d", steps: 20, phases: ["start", "break", "end"] },
    { label: "no id" },
    "nope"
  ])
  const list = M.parseRitualList(raw)
  assert.equal(list.length, 1)
  assert.equal(list[0].id, "focus")
  assert.equal(list[0].steps, 20)
  assert.equal(M.parseRitualList("broken").length, 0)
})

test("ritualSubtitle shows step count and multi-phase flow", () => {
  assert.equal(M.ritualSubtitle({ steps: 9, phases: ["start"] }), "9 steps")
  assert.equal(M.ritualSubtitle({ steps: 20, phases: ["start", "break", "end"] }), "20 steps  ·  start → break → end")
})

test("snapshotLines: one row per present plugin, skips absent ones", () => {
  const snap = M.parseSnapshot(JSON.stringify({
    pomodoro: { phase: "WORK", streak: 3, completedToday: 2 },
    timers: { count: 4, longestMs: 5400000 },
    countdowns: { count: 6, soonestDays: 4 },
    score: { score: 7 },
    reminders: [{}, {}],
    vpn: { connected: true, country: "NL" }
  }))
  const lines = M.snapshotLines(snap)
  const byLabel = Object.fromEntries(lines.map(l => [l.label, l.value]))
  assert.equal(byLabel["Pomodoro"], "work  ·  streak 3  ·  2 today")
  assert.equal(byLabel["Timers"], "4 running  ·  longest 1h 30m")
  assert.equal(byLabel["Countdowns"], "6 tracked  ·  soonest in 4d")
  assert.equal(byLabel["Score"], "7")
  assert.equal(byLabel["Reminders"], "2 pending")
  assert.equal(byLabel["VPN"], "connected  ·  NL")

  assert.deepEqual(M.snapshotLines(M.parseSnapshot("{}")), [])
})

test("fmtMs", () => {
  assert.equal(M.fmtMs(0), "0m")
  assert.equal(M.fmtMs(90000), "1m")
  assert.equal(M.fmtMs(3600000), "1h 0m")
})
