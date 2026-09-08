"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("parseState returns the default shape for garbage input", () => {
  assert.deepEqual(Model.parseState(""), Model.defaultState())
  assert.deepEqual(Model.parseState("{not json"), Model.defaultState())
  assert.deepEqual(Model.parseState(null), Model.defaultState())
})

test("parseState is tolerant of a half-written primary/mounts shape", () => {
  const r = Model.parseState(JSON.stringify({ updatedAt: 123, primary: { pct: 150 }, mounts: "nope" }))
  assert.equal(r.updatedAt, 123)
  assert.equal(r.primary.pct, 100) // clamped
  assert.equal(r.primary.level, "normal") // invalid/missing level falls back
  assert.deepEqual(r.mounts, [])
})

test("parseState keeps a valid critical level", () => {
  const r = Model.parseState(JSON.stringify({ primary: { pct: 96, level: "critical" } }))
  assert.equal(r.primary.level, "critical")
})

test("formatPct rounds and clamps", () => {
  assert.equal(Model.formatPct(84.6), "85%")
  assert.equal(Model.formatPct(-5), "0%")
  assert.equal(Model.formatPct(150), "100%")
})

test("formatGb scales kB to a readable GB string", () => {
  assert.equal(Model.formatGb(1024 * 1024 * 5), "5.0 GB")
  assert.equal(Model.formatGb(1024 * 1024 * 42), "42 GB")
})

test("historyStats computes min/avg/max/cur over the pct series", () => {
  const history = [{ ts: 1, pct: 10 }, { ts: 2, pct: 30 }, { ts: 3, pct: 20 }]
  const stats = Model.historyStats(history, "pct")
  assert.equal(stats.min, 10)
  assert.equal(stats.max, 30)
  assert.equal(stats.avg, 20)
  assert.equal(stats.cur, 20)
  assert.equal(stats.n, 3)
})

test("historyStats on an empty history returns zeroed n:0", () => {
  assert.deepEqual(Model.historyStats([], "pct"), { min: 0, max: 0, avg: 0, cur: 0, n: 0 })
})

test("sparkline trims to the last n points and floors the max", () => {
  const history = [{ pct: 5 }, { pct: 60 }, { pct: 40 }, { pct: 10 }]
  const s = Model.sparkline(history, "pct", 2, 100)
  assert.deepEqual(s.values, [40, 10])
  assert.equal(s.max, 100) // floor wins since both points are under it
  assert.equal(s.n, 2)
})

test("isStale compares updatedAt against now", () => {
  assert.equal(Model.isStale(Model.defaultState(), Date.now()), true) // updatedAt: 0
  assert.equal(Model.isStale({ updatedAt: 1000 }, 1000, 15000), false)
  assert.equal(Model.isStale({ updatedAt: 1000 }, 20000, 15000), true)
})
