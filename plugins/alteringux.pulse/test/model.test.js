"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../Model.js")

const T0 = 1_700_000_000_000

function ev(over) {
  return Object.assign(
    { id: "x", ts: T0, plugin: "alteringux.grip", message: "hi", action: "", actionLabel: "", level: "info" },
    over || {}
  )
}

test("parseActivity tolerates empty / garbage / half-written lines", () => {
  assert.deepEqual(M.parseActivity("").events, [])
  assert.deepEqual(M.parseActivity(null).events, [])
  assert.deepEqual(M.parseActivity("not json\n{bad").events, [])
  const raw = JSON.stringify(ev({ ts: T0 })) + "\n" + '{"ts": broken' // trailing junk
  assert.equal(M.parseActivity(raw, T0).events.length, 1)
})

test("parseActivity normalises, drops event with no message or ts, dedupes by id", () => {
  const raw = [
    JSON.stringify({ id: "a", ts: T0, plugin: "p", message: "one" }),
    JSON.stringify({ id: "a", ts: T0 + 1, plugin: "p", message: "dup id" }),
    JSON.stringify({ id: "b", ts: T0 + 2, plugin: "p", message: "" }),   // no message
    JSON.stringify({ id: "c", plugin: "p", message: "no ts" }),          // no ts
    JSON.stringify({ id: "d", ts: T0 + 5, plugin: "p", message: "two", level: "nonsense" }),
  ].join("\n")
  const out = M.parseActivity(raw, T0 + 10)
  assert.deepEqual(out.events.map((e) => e.id), ["d", "a"]) // newest first, b/c dropped, dup ignored
  assert.equal(out.events[0].level, "info") // bad level clamped
})

test("parseActivity prunes by age and count", () => {
  const old = JSON.stringify(ev({ id: "old", ts: T0 - 40 * 24 * 3600 * 1000, message: "ancient" }))
  const fresh = JSON.stringify(ev({ id: "fresh", ts: T0, message: "now" }))
  const out = M.parseActivity(old + "\n" + fresh, T0)
  assert.deepEqual(out.events.map((e) => e.id), ["fresh"])

  let lines = []
  for (let i = 0; i < 400; i++) lines.push(JSON.stringify(ev({ id: "e" + i, ts: T0 - i * 1000, message: "m" + i })))
  assert.equal(M.parseActivity(lines.join("\n"), T0).events.length, 250)
})

test("makeEvent builds a normalised event with sane defaults", () => {
  const e = M.makeEvent({ plugin: "alteringux.flow", message: "ran", action: "flow view x" }, { now: T0, id: "fixed" })
  assert.equal(e.id, "fixed")
  assert.equal(e.ts, T0)
  assert.equal(e.actionLabel, "Open") // default when an action is present
  assert.equal(e.level, "info")
  const bare = M.makeEvent({ plugin: "p", message: "m" }, { now: T0 })
  assert.equal(bare.action, "")
  assert.equal(bare.actionLabel, "")
})

test("attention: makeAttentionItem + parse + list ordering", () => {
  const a = M.makeAttentionItem({ label: "check-in due", action: "omarchy-grip checkin", level: "urgent" }, { now: T0 })
  assert.equal(a.level, "urgent")
  assert.equal(a.actionLabel, "Do it")

  const att = M.parseAttention({
    items: {
      "alteringux.stocks": { label: "AAPL -4%", level: "info", ts: T0 + 5 },
      "alteringux.grip": { label: "check-in", level: "urgent", ts: T0 },
      "alteringux.bad": { level: "urgent" }, // no label -> dropped
    },
  })
  const rows = M.attentionList(att)
  assert.deepEqual(rows.map((r) => r.plugin), ["alteringux.grip", "alteringux.stocks"]) // urgent before info
})

test("summary: unread counts events after lastReadTs; topLevel from attention", () => {
  const activity = M.parseActivity(
    [
      JSON.stringify(ev({ id: "a", ts: T0, message: "old" })),
      JSON.stringify(ev({ id: "b", ts: T0 + 100, message: "new1" })),
      JSON.stringify(ev({ id: "c", ts: T0 + 200, message: "new2" })),
    ].join("\n"),
    T0 + 300
  )
  const attention = M.parseAttention({ items: { "alteringux.grip": { label: "x", level: "critical", ts: T0 } } })
  const s = M.summary(activity, attention, M.parseState({ lastReadTs: T0 + 50 }))
  assert.equal(s.unread, 2)
  assert.equal(s.total, 3)
  assert.equal(s.needAction, 1)
  assert.equal(s.topLevel, "critical")
})

test("activityDescription summarizes retained feed and attention-only state", () => {
  const activity = M.parseActivity(
    [
      JSON.stringify(ev({ id: "a", ts: T0, plugin: "alteringux.grip", message: "old" })),
      JSON.stringify(ev({ id: "b", ts: T0 + 100, plugin: "alteringux.grip", level: "critical" })),
      JSON.stringify(ev({ id: "c", ts: T0 + 200, plugin: "alteringux.pulse", level: "warning" }))
    ].join("\n"),
    T0 + 300
  )
  const attention = M.parseAttention({
    items: { "alteringux.timers": { label: "Timer ended", level: "urgent", ts: T0 } }
  })
  const state = M.parseState({ lastReadTs: T0 + 50 })

  assert.equal(M.activityDescription(activity, state, attention),
    "3 recent notifications from 2 plugins · 2 unread · 1 alert needs action · 1 urgent or critical\nMost: grip (2) · pulse (1)")
  assert.match(M.activityDescription(activity, state, attention, 1), /newest 1 shown below/)
  assert.equal(M.activityDescription(M.defaultActivity(), state, attention), "1 alert needs action")
  assert.equal(M.activityDescription(M.defaultActivity(), state, M.defaultAttention()), "")
})

test("activityMessageSummary uses the full feed and surfaces repeated messages", () => {
  const activity = M.parseActivity([
    JSON.stringify(ev({ id: "a", ts: T0, message: "Shared warning" })),
    JSON.stringify(ev({ id: "b", ts: T0 + 100, message: "Older unique message" })),
    JSON.stringify(ev({ id: "c", ts: T0 + 200, message: "Shared   warning" })),
    JSON.stringify(ev({ id: "d", ts: T0 + 300, message: "Newest unique message" }))
  ].join("\n"), T0 + 400)

  assert.equal(M.activityMessageSummary(activity), "grip: Shared warning ×2 · grip: Newest unique message")
  assert.equal(M.activityMessageSummary(M.defaultActivity()), "")
})

test("activityMessageSummary keeps identical messages distinct by plugin", () => {
  const activity = M.parseActivity([
    JSON.stringify(ev({ id: "a", ts: T0, message: "Shared warning" })),
    JSON.stringify(ev({ id: "b", ts: T0 + 100, plugin: "alteringux.pulse", message: "Shared warning" }))
  ].join("\n"), T0 + 200)

  assert.equal(M.activityMessageSummary(activity), "pulse: Shared warning · grip: Shared warning")
})

test("plugin usage normalises tracked, untracked, most/least-used and stale rows", () => {
  const usage = M.parseUsage({
    generatedAt: "2026-09-18T00:00:00Z",
    thresholdDays: 30,
    plugins: [
      { id: "alteringux.hot", label: "Hot", tracked: true, uses: 8, lastAt: T0 + 31 * 86400000 },
      { id: "alteringux.cold", label: "Cold", tracked: true, uses: 1, lastAt: T0 - 31 * 86400000 },
      { id: "alteringux.new", label: "New", tracked: false, uses: 0, lastAt: 0 }
    ]
  }, T0 + 31 * 86400000)
  assert.deepEqual(usage.summary, { tracked: 2, untracked: 1, neverUsed: 0, stale: 1 })
  assert.deepEqual(M.usageMostUsed(usage, 1).map((p) => p.id), ["alteringux.hot"])
  assert.deepEqual(M.usageLeastUsed(usage, 1).map((p) => p.id), ["alteringux.new"])
  assert.match(M.makeUsageAttention(usage, { now: T0 }).label, /alteringux.cold.*62d idle/)
  assert.equal(M.makeUsageAttention(M.parseUsage({
    thresholdDays: 30,
    plugins: [{ id: "alteringux.recent", tracked: true, uses: 2, lastAt: T0 }]
  }, T0), { now: T0 }), null)
})

test("usage attention acknowledgements suppress only the same snapshot", () => {
  const usage = M.parseUsage({
    thresholdDays: 30,
    plugins: [{ id: "alteringux.cold", tracked: true, uses: 2, lastAt: T0 - 31 * 86400000 }]
  }, T0)
  assert.equal(M.makeUsageAttention(usage, {
    now: T0,
    acknowledged: { "alteringux.cold": { uses: 2, lastAt: T0 - 31 * 86400000 } }
  }), null)
  assert.ok(M.makeUsageAttention(usage, {
    now: T0,
    acknowledged: { "alteringux.cold": { uses: 1, lastAt: T0 - 31 * 86400000 } }
  }))
})

test("nextAction: attention wins; falls back to newest actionable unread; else null", () => {
  const attention = M.parseAttention({
    items: {
      "alteringux.grip": { label: "g", level: "warning", ts: T0 },
      "alteringux.timers": { label: "t", level: "urgent", ts: T0 },
    },
  })
  const na1 = M.nextAction(M.defaultActivity(), attention, M.defaultState())
  assert.equal(na1.source, "attention")
  assert.equal(na1.plugin, "alteringux.timers") // loudest

  const activity = M.parseActivity(
    [
      JSON.stringify(ev({ id: "a", ts: T0 + 1, message: "no action" })),
      JSON.stringify(ev({ id: "b", ts: T0 + 2, message: "do x", action: "cmd-x" })),
    ].join("\n"),
    T0 + 10
  )
  const na2 = M.nextAction(activity, M.defaultAttention(), M.parseState({ lastReadTs: T0 }))
  assert.equal(na2.source, "activity")
  assert.equal(na2.action, "cmd-x")

  assert.equal(M.nextAction(M.defaultActivity(), M.defaultAttention(), M.defaultState()), null)
})

test("relTime buckets", () => {
  assert.equal(M.relTime(0), "just now")
  assert.equal(M.relTime(20 * 1000), "just now")
  assert.equal(M.relTime(60 * 1000), "1m ago")
  assert.equal(M.relTime(5 * 60 * 1000), "5m ago")
  assert.equal(M.relTime(3 * 3600 * 1000), "3h ago")
  assert.equal(M.relTime(2 * 24 * 3600 * 1000), "2d ago")
})

test("formatList renders a table and an empty state", () => {
  assert.equal(M.formatList(M.defaultActivity(), T0, 10), "No activity yet.")
  const activity = M.parseActivity(JSON.stringify(ev({ id: "a", ts: T0, message: "hello", level: "urgent" })), T0)
  const txt = M.formatList(activity, T0 + 60000, 10)
  assert.match(txt, /^! grip/)
  assert.match(txt, /1m ago/)
  assert.match(txt, /hello/)
})
