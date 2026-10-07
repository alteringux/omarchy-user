"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("parseState falls back to defaults on empty/garbage input", () => {
  assert.deepEqual(Model.parseState(""), Model.defaultState())
  assert.deepEqual(Model.parseState("not json"), Model.defaultState())
  assert.deepEqual(Model.parseState(null), Model.defaultState())
})

test("parseState clamps percentages into 0..100", () => {
  const s = Model.parseState(JSON.stringify({
    cpu: { pct: 150, cores: [-5, 42, 200] },
    memory: { pct: -10, totalKb: 1000, availableKb: 500, usedKb: 500 }
  }))
  assert.equal(s.cpu.pct, 100)
  assert.deepEqual(s.cpu.cores, [0, 42, 100])
  assert.equal(s.memory.pct, 0)
})

test("parseState preserves a numeric temp and nulls a missing one", () => {
  const withTemp = Model.parseState(JSON.stringify({ temp: 72.4 }))
  assert.equal(withTemp.temp, 72.4)

  const withoutTemp = Model.parseState(JSON.stringify({ temp: null }))
  assert.equal(withoutTemp.temp, null)
})

test("pctLevel thresholds: normal < 70 <= warning < 90 <= critical", () => {
  assert.equal(Model.pctLevel(0), "normal")
  assert.equal(Model.pctLevel(69.9), "normal")
  assert.equal(Model.pctLevel(70), "warning")
  assert.equal(Model.pctLevel(89.9), "warning")
  assert.equal(Model.pctLevel(90), "critical")
  assert.equal(Model.pctLevel(100), "critical")
})

test("tempLevel thresholds: normal < 75 <= warning < 90 <= critical; null is normal", () => {
  assert.equal(Model.tempLevel(null), "normal")
  assert.equal(Model.tempLevel(74.9), "normal")
  assert.equal(Model.tempLevel(75), "warning")
  assert.equal(Model.tempLevel(89.9), "warning")
  assert.equal(Model.tempLevel(90), "critical")
})

test("formatPct rounds and appends %", () => {
  assert.equal(Model.formatPct(42.6), "43%")
  assert.equal(Model.formatPct(0), "0%")
})

test("formatTemp renders an em dash when null, else rounded degrees", () => {
  assert.equal(Model.formatTemp(null), "—")
  assert.equal(Model.formatTemp(68.4), "68°C")
})

test("formatGb converts kB to GB with adaptive precision", () => {
  assert.equal(Model.formatGb(1024 * 1024), "1.0 GB")
  assert.equal(Model.formatGb(16 * 1024 * 1024), "16 GB")
})

test("formatUptime renders the largest two useful units", () => {
  assert.equal(Model.formatUptime(45), "0m")
  assert.equal(Model.formatUptime(125 * 60), "2h 5m")
  assert.equal(Model.formatUptime(3 * 86400 + 4 * 3600), "3d 4h")
})

test("barLabel omits the temp segment when temp is null", () => {
  const withoutTemp = Model.parseState(JSON.stringify({ cpu: { pct: 10 }, memory: { pct: 20 }, temp: null }))
  assert.deepEqual(Model.barLabel(withoutTemp), ["10%", "20%"])

  const withTemp = Model.parseState(JSON.stringify({ cpu: { pct: 10 }, memory: { pct: 20 }, temp: 55 }))
  assert.deepEqual(Model.barLabel(withTemp), ["10%", "20%", "55°C"])
})

test("isStale compares the real sample age and honors explicit thresholds", () => {
  assert.equal(Model.isStale(Model.defaultState(), 10000), true)
  assert.equal(Model.isStale({ updatedAt: 1000 }, 20000, 15000), true)
  assert.equal(Model.isStale({ updatedAt: 5000 }, 5000, 15000), false)
  assert.equal(Model.isStale({ updatedAt: 20000 }, 5000, 0), false)
  assert.equal(Model.isStale({ updatedAt: "bad" }, 5000), true)
})

test("parseState drops malformed history rows and preserves missing metric samples", () => {
  const s = Model.parseState(JSON.stringify({
    history: [
      null,
      "bad",
      { ts: 3, cpu: "bad", mem: 40, temp: "bad" },
      { ts: 4, cpu: 50, mem: 60, temp: null }
    ]
  }))
  assert.deepEqual(s.history, [
    { ts: 3, cpu: null, mem: 40, temp: null },
    { ts: 4, cpu: 50, mem: 60, temp: null }
  ])
})

test("history projections can select a real timestamp window", () => {
  const now = 1_000_000
  const h = [
    { ts: now - 700_000, cpu: 10, mem: 0, temp: null },
    { ts: now - 300_000, cpu: 30, mem: 0, temp: null },
    { ts: now - 1_000, cpu: 50, mem: 0, temp: null },
    { ts: now + 1_000, cpu: 90, mem: 0, temp: null }
  ]
  assert.deepEqual(Model.historySeries(h, "cpu", now, 600_000), [30, 50])
  assert.deepEqual(Model.historyStats(h, "cpu", now, 600_000), {
    min: 30, max: 50, avg: 40, cur: 50, n: 2
  })
  assert.deepEqual(Model.sparkline(h, "cpu", 10, 100, now, 600_000).values, [30, 50])
})

test("epoch histories default to the ten-minute trend window", () => {
  const now = 2_000_000_000_000
  const originalNow = Date.now
  Date.now = () => now
  try {
    const h = [
      { ts: now - Model.TREND_WINDOW_MS - 1, cpu: 10, mem: 0, temp: null },
      { ts: now - Model.TREND_WINDOW_MS + 1, cpu: 30, mem: 0, temp: null }
    ]
    assert.deepEqual(Model.historySeries(h, "cpu"), [30])
  } finally {
    Date.now = originalNow
  }
})

test("parseState caps hostile history length", () => {
  const history = Array.from({ length: Model.HISTORY_CAP + 5 }, (_, i) => ({
    ts: i + 1, cpu: i % 100, mem: 0, temp: null
  }))
  const s = Model.parseState(JSON.stringify({ history }))
  assert.equal(s.history.length, Model.HISTORY_CAP)
  assert.equal(s.history[0].ts, 6)
})

test("parseState carries a clamped history ring, empty when absent or malformed", () => {
  assert.deepEqual(Model.parseState(JSON.stringify({})).history, [])
  const s = Model.parseState(JSON.stringify({
    history: [
      { ts: 1, cpu: 150, mem: 40, temp: 55 },
      { ts: 2, cpu: 10, mem: -5, temp: null },
      null
    ]
  }))
  assert.deepEqual(s.history, [
    { ts: 1, cpu: 100, mem: 40, temp: 55 },
    { ts: 2, cpu: 10, mem: 0, temp: null }
  ])
})

test("historySeries drops null/absent samples for the requested key", () => {
  const h = [
    { ts: 1, cpu: 10, mem: 20, temp: null },
    { ts: 2, cpu: 30, mem: 40, temp: 50 },
    { ts: 3, cpu: 50, mem: 60, temp: 60 }
  ]
  assert.deepEqual(Model.historySeries(h, "cpu"), [10, 30, 50])
  assert.deepEqual(Model.historySeries(h, "temp"), [50, 60])
  assert.deepEqual(Model.historySeries([], "cpu"), [])
})

test("historyStats reports min/avg/max/current over a key, zeroed when empty", () => {
  const h = [
    { ts: 1, cpu: 10, mem: 0, temp: null },
    { ts: 2, cpu: 20, mem: 0, temp: null },
    { ts: 3, cpu: 60, mem: 0, temp: null }
  ]
  assert.deepEqual(Model.historyStats(h, "cpu"), { min: 10, max: 60, avg: 30, cur: 60, n: 3 })
  assert.deepEqual(Model.historyStats(h, "temp"), { min: 0, max: 0, avg: 0, cur: 0, n: 0 })
})

test("sparkline returns the last n points for a key and a floored max", () => {
  const h = [10, 12, 8, 40, 5].map((v, i) => ({ ts: i, cpu: v, mem: 0, temp: null }))
  const s = Model.sparkline(h, "cpu", 3, 100)
  assert.deepEqual(s.values, [8, 40, 5])
  assert.equal(s.max, 100)
  assert.equal(s.n, 3)

  const dyn = Model.sparkline(h, "cpu", 10, 1)
  assert.equal(dyn.max, 40)
})
