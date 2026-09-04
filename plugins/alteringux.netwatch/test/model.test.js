"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const HOUR = 3600 * 1000

// A fixed "now" so the local-time bucket keys are deterministic per run.
const T0 = new Date(2026, 5, 15, 10, 0, 0).getTime() // 2026-06-15 10:00 local

function sampleAt(ts, rxBytes, txBytes, iface) {
  return { ts, rxBytes, txBytes, iface: iface || "wlp2s0", up: true, isVpn: false }
}

test("first sample records no delta (nothing to diff against)", () => {
  const r = Model.ingest(Model.defaultState(), null, sampleAt(T0, 1_000_000, 500_000), {}, T0)
  assert.equal(r.state.rx.rate, 0)
  assert.equal(r.state.tx.rate, 0)
  assert.deepEqual(r.state.buckets.daily, {})
  assert.equal(r.sample.rxBytes, 1_000_000)
})

test("second sample computes rate and rolls the delta into hour/day/month buckets", () => {
  const s1 = Model.ingest(Model.defaultState(), null, sampleAt(T0, 1_000_000, 500_000), {}, T0)
  const prev = s1.sample
  // +10s, +2 MB down, +1 MB up
  const r = Model.ingest(s1.state, prev, sampleAt(T0 + 10_000, 3_000_000, 1_500_000), {}, T0 + 10_000)
  assert.equal(r.state.rx.rate, 200_000) // 2 MB / 10 s
  assert.equal(r.state.tx.rate, 100_000)

  const dk = Model.dayKey(new Date(T0))
  const hk = Model.hourKey(new Date(T0))
  const mk = Model.monthKey(new Date(T0))
  assert.equal(r.state.buckets.daily[dk].rx, 2_000_000)
  assert.equal(r.state.buckets.daily[dk].tx, 1_000_000)
  assert.equal(r.state.buckets.hourly[hk].rx, 2_000_000)
  assert.equal(r.state.buckets.monthly[mk].tx, 1_000_000)
})

test("a counter that went backwards (reboot / reset) is discarded, not stored negative", () => {
  const s1 = Model.ingest(Model.defaultState(), null, sampleAt(T0, 5_000_000, 5_000_000), {}, T0)
  const r = Model.ingest(s1.state, s1.sample, sampleAt(T0 + 10_000, 10_000, 10_000), {}, T0 + 10_000)
  assert.equal(r.state.rx.rate, 0)
  const dk = Model.dayKey(new Date(T0))
  assert.equal(r.state.buckets.daily[dk], undefined)
  // but the new low reading becomes the baseline for next time
  assert.equal(r.sample.rxBytes, 10_000)
})

test("an interface change resets the baseline instead of diffing across interfaces", () => {
  const s1 = Model.ingest(Model.defaultState(), null, sampleAt(T0, 1_000_000, 0, "wlp2s0"), {}, T0)
  const r = Model.ingest(s1.state, s1.sample, sampleAt(T0 + 10_000, 50, 0, "tun0"), {}, T0 + 10_000)
  assert.equal(r.state.rx.rate, 0)
  assert.equal(r.state.iface, "tun0")
})

test("rates ring is capped at ratesRingSize (min 10 after the parseConfig clamp)", () => {
  const cfg = { ratesRingSize: 12 }
  let state = Model.defaultState()
  let prev = null
  let rx = 0
  for (let i = 0; i < 40; i++) {
    rx += 1_000_000
    const r = Model.ingest(state, prev, sampleAt(T0 + i * 1000, rx, 0), cfg, T0 + i * 1000)
    state = r.state
    prev = r.sample
  }
  assert.equal(state.rates.length, 12)
})

test("quota crosses 80% then 100% — one alert each, not repeated", () => {
  // 1 GB cap; quotaCountsTx counts both directions.
  const cfg = { monthlyQuotaGB: 0.001, quotaCountsTx: true } // 1e6 bytes
  let state = Model.defaultState()
  let prev = Model.ingest(state, null, sampleAt(T0, 0, 0), cfg, T0).sample
  state = Model.ingest(state, null, sampleAt(T0, 0, 0), cfg, T0).state

  // jump to ~85%
  let r = Model.ingest(state, prev, sampleAt(T0 + 1000, 850_000, 0), cfg, T0 + 1000)
  assert.equal(r.alerts.filter((a) => a.kind === "quota80").length, 1)
  state = r.state
  prev = r.sample

  // still climbing but < 100 — no new alert
  r = Model.ingest(state, prev, sampleAt(T0 + 2000, 950_000, 0), cfg, T0 + 2000)
  assert.equal(r.alerts.length, 0)
  state = r.state
  prev = r.sample

  // cross 100%
  r = Model.ingest(state, prev, sampleAt(T0 + 3000, 1_200_000, 0), cfg, T0 + 3000)
  assert.equal(r.alerts.filter((a) => a.kind === "quota100").length, 1)
  state = r.state
  prev = r.sample

  // still over — silent
  r = Model.ingest(state, prev, sampleAt(T0 + 4000, 2_000_000, 0), cfg, T0 + 4000)
  assert.equal(r.alerts.length, 0)
})

test("quota alert flags reset when the calendar month rolls over", () => {
  const cfg = { monthlyQuotaGB: 0.001, quotaCountsTx: false }
  let state = Model.defaultState()
  state = Model.ingest(state, null, sampleAt(T0, 0, 0), cfg, T0).state
  let prev = Model.ingest(state, null, sampleAt(T0, 0, 0), cfg, T0).sample
  let r = Model.ingest(state, prev, sampleAt(T0 + 1000, 1_500_000, 0), cfg, T0 + 1000)
  assert.ok(r.alerts.some((a) => a.kind === "quota100"))

  // next month, fresh counter baseline
  const nextMonth = new Date(2026, 6, 2, 10, 0, 0).getTime()
  r = Model.ingest(r.state, r.sample, sampleAt(nextMonth, 1_600_000, 0), cfg, nextMonth)
  // new month bucket starts near zero, so no immediate alert and flags cleared
  assert.equal(r.state.alerts.quota100, 0)
  assert.equal(r.state.alerts.month, Model.monthKey(new Date(nextMonth)))
})

test("sustained spike alert needs 3 consecutive over-threshold samples, then cools down", () => {
  const cfg = { spikeMbps: 1, ratesRingSize: 50 } // 1 Mbps = 125000 B/s
  let state = Model.defaultState()
  let prev = Model.ingest(state, null, sampleAt(T0, 0, 0), cfg, T0).sample
  state = Model.ingest(state, null, sampleAt(T0, 0, 0), cfg, T0).state

  let rx = 0
  const step = 400_000 // 400 kB/s each second — over the 125 kB/s threshold
  let firedAt = -1
  for (let i = 1; i <= 5; i++) {
    rx += step
    const r = Model.ingest(state, prev, sampleAt(T0 + i * 1000, rx, 0), cfg, T0 + i * 1000)
    if (r.alerts.some((a) => a.kind === "spike") && firedAt < 0) firedAt = i
    state = r.state
    prev = r.sample
  }
  assert.equal(firedAt, 3) // first fire on the 3rd consecutive breach

  // within cooldown (10 min) — no re-fire
  rx += step
  const r = Model.ingest(state, prev, sampleAt(T0 + 6000, rx, 0), cfg, T0 + 6000)
  assert.equal(r.alerts.filter((a) => a.kind === "spike").length, 0)
})

test("ingest.meta reports counter resets and interface changes for the self-improvement loop", () => {
  const s1 = Model.ingest(Model.defaultState(), null, sampleAt(T0, 5_000_000, 5_000_000), {}, T0)
  assert.equal(s1.meta.usableDelta, false) // first sample

  const s2 = Model.ingest(s1.state, s1.sample, sampleAt(T0 + 10_000, 6_000_000, 6_000_000), {}, T0 + 10_000)
  assert.equal(s2.meta.usableDelta, true)
  assert.equal(s2.meta.counterReset, false)
  assert.equal(s2.meta.ifaceChanged, false)

  const reset = Model.ingest(s2.state, s2.sample, sampleAt(T0 + 20_000, 100, 100), {}, T0 + 20_000)
  assert.equal(reset.meta.counterReset, true)
  assert.equal(reset.meta.usableDelta, false)

  const flipped = Model.ingest(s2.state, s2.sample, sampleAt(T0 + 20_000, 50, 0, "tun0"), {}, T0 + 20_000)
  assert.equal(flipped.meta.ifaceChanged, true)
})

test("status projects today/week/month totals and a compact label", () => {
  let state = Model.defaultState()
  let prev = null
  let rx = 0
  let tx = 0
  for (let i = 0; i < 3; i++) {
    rx += 5_000_000
    tx += 1_000_000
    const r = Model.ingest(state, prev, sampleAt(T0 + i * 10_000, rx, tx), {}, T0 + i * 10_000)
    state = r.state
    prev = r.sample
  }
  const st = Model.status(state, {}, T0 + 30_000)
  assert.equal(st.today.rx, 10_000_000) // two usable deltas of 5 MB
  assert.equal(st.today.tx, 2_000_000)
  assert.equal(st.month.total, 12_000_000)
  assert.match(st.label, /↓.*↑/)
  assert.equal(st.stale, false)
})

test("status marks the widget stale when the last sample is older than 3 intervals", () => {
  const s1 = Model.ingest(Model.defaultState(), null, sampleAt(T0, 1000, 1000), {}, T0)
  const st = Model.status(s1.state, { sampleIntervalSec: 20 }, T0 + 61_000)
  assert.equal(st.stale, true)
})

test("report(today) returns 24 hourly points and finds the peak hour", () => {
  let state = Model.defaultState()
  // hour 10: big; hour 11: small
  let r = Model.ingest(state, null, sampleAt(T0, 0, 0), {}, T0)
  r = Model.ingest(r.state, r.sample, sampleAt(T0 + 10_000, 9_000_000, 0), {}, T0 + 10_000)
  r = Model.ingest(r.state, r.sample, sampleAt(T0 + HOUR, 9_500_000, 0), {}, T0 + HOUR)
  const rep = Model.report(r.state, "today", T0 + HOUR)
  assert.equal(rep.series.length, 24)
  assert.equal(rep.peak.label, "10")
  assert.equal(rep.total.rx, 9_500_000)
})

test("parseConfig clamps hostile hand-edits", () => {
  const c = Model.parseConfig('{"sampleIntervalSec":-4,"monthlyQuotaGB":"lots","ratesRingSize":0}')
  assert.equal(c.sampleIntervalSec, 1)
  assert.equal(c.monthlyQuotaGB, 0)
  assert.equal(c.ratesRingSize, 10)
})

test("parseState degrades a corrupt file to defaults rather than throwing", () => {
  const s = Model.parseState("{not json")
  assert.deepEqual(s, Model.defaultState())
})

test("formatBytes / formatRate / compactRate use decimal units", () => {
  assert.equal(Model.formatBytes(1500), "1.5 kB")
  assert.equal(Model.formatBytes(2_500_000_000), "2.50 GB")
  assert.equal(Model.formatRate(0), "0 B/s")
  assert.equal(Model.formatRate(1_500_000), "1.50 MB/s")
  assert.equal(Model.compactRate(930_000), "930k")
  assert.equal(Model.compactRate(1_200_000), "1.2M")
})
