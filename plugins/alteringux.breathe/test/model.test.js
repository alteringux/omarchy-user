// Plain-node tests for the pure logic in Model.js. Run with:
//   node test/model.test.js
// Model.js has no module system of its own (it's loaded as a QML JS import),
// so it exposes a guarded `module.exports` at the bottom purely for this
// harness; that export is a no-op inside QML.
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const Model = require("../Model.js")

let passed = 0
function test(name, fn) {
  try {
    fn()
    passed++
    console.log("ok - " + name)
  } catch (e) {
    console.error("FAIL - " + name)
    console.error(e)
    process.exitCode = 1
  }
}

const CATALOGUE = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "techniques.json"), "utf8"))

// ── catalogue integrity ────────────────────────────────────────────────────

test("Model.TECHNIQUES is byte-identical to techniques.json", () => {
  // The catalogue exists three times (this file, techniques.json, and the bash
  // CLI). This is the check that stops the JS copy drifting; catalogue.test.sh
  // covers the bash one.
  assert.deepStrictEqual(Model.TECHNIQUES, CATALOGUE.techniques)
})

test("techniques.json declares every phase kind the catalogue actually uses", () => {
  const used = new Set()
  CATALOGUE.techniques.forEach(t => t.phases.forEach(p => used.add(p.kind)))
  used.forEach(kind => assert.ok(CATALOGUE.phaseKinds.includes(kind), "undeclared kind: " + kind))
})

test("every phase kind in the catalogue is a known Model.PHASE", () => {
  Model.TECHNIQUES.forEach(t => t.phases.forEach(p => {
    assert.ok(Model.PHASE[p.kind], t.id + " uses unknown kind " + p.kind)
  }))
})

test("technique ids are unique", () => {
  const ids = Model.TECHNIQUES.map(t => t.id)
  assert.strictEqual(new Set(ids).size, ids.length)
})

test("every technique has phases, positive durations and a positive cycle count", () => {
  Model.TECHNIQUES.forEach(t => {
    assert.ok(t.phases.length > 0, t.id + " has no phases")
    assert.ok(t.defaultCycles > 0, t.id + " has no default cycles")
    t.phases.forEach(p => assert.ok(p.seconds > 0, t.id + " phase " + p.kind + " has no duration"))
  })
})

test("every technique carries the prose the panel renders", () => {
  Model.TECHNIQUES.forEach(t => {
    assert.ok(t.name && t.name.length, t.id + " has no name")
    assert.ok(t.pattern && t.pattern.length, t.id + " has no pattern")
    assert.ok(t.blurb && t.blurb.length, t.id + " has no blurb")
    assert.ok(t.use && t.use.length, t.id + " has no use line")
    assert.ok(["core", "energising", "clinical"].includes(t.family), t.id + " has an odd family")
    assert.ok(["neutral", "info", "positive", "warning", "negative"].includes(t.tone), t.id + " has an odd tone")
  })
})

test("the risky techniques carry a warning", () => {
  assert.ok(Model.techniqueById("wim-hof").warning)
  assert.ok(Model.techniqueById("bellows").warning)
})

test("POWER_BREATHS phases declare a breath count", () => {
  Model.TECHNIQUES.forEach(t => t.phases.forEach(p => {
    if (p.kind === Model.PHASE.POWER_BREATHS) assert.ok(p.breaths > 0, t.id + " power breaths without a count")
  }))
})

test("cycleSeconds and sessionSeconds add up", () => {
  assert.strictEqual(Model.cycleSeconds(Model.techniqueById("box")), 16)
  assert.strictEqual(Model.cycleSeconds(Model.techniqueById("relaxing478")), 19)
  assert.strictEqual(Model.sessionSeconds(Model.techniqueById("box"), 8), 128)
  assert.strictEqual(Model.cycleSeconds(null), 0)
  assert.strictEqual(Model.sessionSeconds(null, 5), 0)
})

test("Vortex is the descending Fibonacci run and its cycle sums to 32s", () => {
  const vortex = Model.techniqueById("vortex")
  assert.ok(vortex, "vortex is in the catalogue")
  assert.strictEqual(vortex.phases.length, 12, "six breaths, each an inhale and an exhale")
  assert.deepStrictEqual(
    vortex.phases.map(p => p.seconds),
    [6.5, 6.5, 4, 4, 2.5, 2.5, 1.5, 1.5, 1, 1, 0.5, 0.5]
  )
  assert.strictEqual(Model.cycleSeconds(vortex), 32)
  // The 0.5s tail is the fastest phase in the catalogue — make sure resolve
  // still lands cleanly on it rather than skidding past.
  const r = Model.resolve(
    { state: "RUNNING", techniqueId: "vortex", cycles: 4, savedAtMs: 0, elapsedMs: 31200 }, vortex, 0)
  assert.strictEqual(r.phaseIndex, 10, "31.2s in is inside the last half-second inhale")
  assert.strictEqual(r.phaseKind, Model.PHASE.INHALE)
})

// ── the orb-scale envelope ─────────────────────────────────────────────────

test("orbScale stays inside its declared range for every technique", () => {
  Model.TECHNIQUES.forEach(t => {
    t.phases.forEach((p, i) => {
      for (let f = 0; f <= 1.0001; f += 0.05) {
        const s = Model.orbScale(t, i, f)
        assert.ok(s >= Model.SCALE_MIN - 1e-9 && s <= Model.SCALE_MAX + 1e-9,
          t.id + " phase " + i + " @" + f.toFixed(2) + " => " + s)
      }
    })
  })
})

test("orbScale is continuous across every phase boundary, including the cycle wrap", () => {
  // A seam here is exactly what makes an animation snap, and it is invisible
  // in any single-phase test — so walk every adjacent pair of every built-in.
  Model.TECHNIQUES.forEach(t => {
    for (let i = 0; i < t.phases.length; i++) {
      const next = (i + 1) % t.phases.length
      const endOfThis = Model.orbScale(t, i, 1)
      const startOfNext = Model.orbScale(t, next, 0)
      assert.ok(Math.abs(endOfThis - startOfNext) < 1e-9,
        t.id + ": phase " + i + " ends " + endOfThis + " but phase " + next + " starts " + startOfNext)
    }
  })
})

test("scaleEnvelope caches per technique and recomputes when it changes", () => {
  // The guides call this every animation frame; it must return the same array
  // for the same technique without rebuilding it, and still be correct.
  const box = Model.techniqueById("box")
  const a = Model.scaleEnvelope(box)
  assert.strictEqual(Model.scaleEnvelope(box), a, "a repeat call returns the cached array")
  const vortex = Model.techniqueById("vortex")
  assert.notStrictEqual(Model.scaleEnvelope(vortex), a, "a different technique rebuilds")
  assert.strictEqual(Model.scaleEnvelope(box).length, box.phases.length)
  assert.ok(a.every(s => s.from >= Model.SCALE_MIN - 1e-9 && s.to <= Model.SCALE_MAX + 1e-9))
})

test("holds do not move the orb", () => {
  const box = Model.techniqueById("box")
  const holdIn = box.phases.findIndex(p => p.kind === Model.PHASE.HOLD_IN)
  assert.strictEqual(Model.orbScale(box, holdIn, 0), Model.orbScale(box, holdIn, 0.5))
  assert.strictEqual(Model.orbScale(box, holdIn, 0.5), Model.orbScale(box, holdIn, 1))
})

test("a hold at the top sits at the peak and a hold at the bottom sits at the floor", () => {
  const box = Model.techniqueById("box")
  const holdIn = box.phases.findIndex(p => p.kind === Model.PHASE.HOLD_IN)
  const holdOut = box.phases.findIndex(p => p.kind === Model.PHASE.HOLD_OUT)
  assert.ok(Math.abs(Model.orbScale(box, holdIn, 0.5) - Model.SCALE_MAX) < 1e-9)
  assert.ok(Math.abs(Model.orbScale(box, holdOut, 0.5) - Model.SCALE_MIN) < 1e-9)
})

test("the physiological sigh's first inhale stops short so the sip has headroom", () => {
  // The whole point of the sigh is that the second sip goes HIGHER. If the
  // first inhale already peaked, the sip would have to jump backwards.
  const sigh = Model.techniqueById("physiological-sigh")
  const afterInhale = Model.orbScale(sigh, 0, 1)
  const afterSip = Model.orbScale(sigh, 1, 1)
  assert.ok(afterInhale < afterSip, "inhale ended at " + afterInhale + ", sip ended at " + afterSip)
  assert.ok(Math.abs(afterSip - Model.SCALE_MAX) < 1e-9, "the sip should reach the peak")
})

test("wim hof walks the orb back down before the next round starts", () => {
  // Without the closing release exhale the round would end holding a full
  // breath and the next would begin empty, snapping the orb across the seam.
  const wh = Model.techniqueById("wim-hof")
  assert.strictEqual(wh.phases[wh.phases.length - 1].kind, Model.PHASE.EXHALE)
  assert.ok(Math.abs(Model.orbScale(wh, wh.phases.length - 1, 1) - Model.SCALE_MIN) < 1e-9)
})

test("power breaths oscillate once per breath and return empty", () => {
  const wh = Model.techniqueById("wim-hof")
  const breaths = wh.phases[0].breaths
  assert.ok(Math.abs(Model.orbScale(wh, 0, 0) - Model.SCALE_MIN) < 1e-9)
  assert.ok(Math.abs(Model.orbScale(wh, 0, 1) - Model.SCALE_MIN) < 1e-9)
  // Mid-way through the first breath is the top of that breath.
  const midFirstBreath = Model.orbScale(wh, 0, 0.5 / breaths)
  assert.ok(midFirstBreath > 0.9, "expected a full swell mid-breath, got " + midFirstBreath)
})

test("amplitude damps how far a technique swells", () => {
  // Buteyko's premise is breathing LESS than feels natural; rendering it at
  // the same sweep as a power breath would teach the wrong thing.
  const buteyko = Model.techniqueById("buteyko")
  const box = Model.techniqueById("box")
  assert.ok(Model.peakScale(buteyko) < Model.peakScale(box))
  assert.ok(Math.abs(Model.peakScale(box) - Model.SCALE_MAX) < 1e-9)
  const peak = Model.orbScale(buteyko, 0, 1)
  assert.ok(Math.abs(peak - Model.peakScale(buteyko)) < 1e-9)
})

test("orbScale degrades rather than throwing on nonsense input", () => {
  assert.strictEqual(Model.orbScale(null, 0, 0), Model.SCALE_MIN)
  assert.strictEqual(Model.orbScale({ phases: [] }, 0, 0), Model.SCALE_MIN)
  const box = Model.techniqueById("box")
  assert.ok(isFinite(Model.orbScale(box, 99, 0.5)))
  assert.ok(isFinite(Model.orbScale(box, -3, 0.5)))
  assert.ok(isFinite(Model.orbScale(box, 0, 7)))
  assert.ok(isFinite(Model.orbScale(box, 0, NaN)))
})

// ── resolve ────────────────────────────────────────────────────────────────

const box = Model.techniqueById("box")

function runningSession(elapsedMs, cycles) {
  return {
    version: 1, state: "RUNNING", techniqueId: "box", cycles: cycles || 8,
    sessionId: "s", startedAtMs: 1000, savedAtMs: 1000, elapsedMs: elapsedMs, silent: false
  }
}

test("resolve lands on the right phase mid-cycle", () => {
  const r = Model.resolve(runningSession(6000), box, 1000)   // 6s in: 4s inhale done, 2s into hold
  assert.strictEqual(r.phaseIndex, 1)
  assert.strictEqual(r.phaseKind, Model.PHASE.HOLD_IN)
  assert.strictEqual(r.phaseElapsedMs, 2000)
  assert.strictEqual(r.phaseRemainingMs, 2000)
  assert.strictEqual(r.phaseFraction, 0.5)
  assert.strictEqual(r.cycleIndex, 0)
})

test("resolve is exact at a phase boundary", () => {
  const r = Model.resolve(runningSession(4000), box, 1000)   // exactly the end of the inhale
  assert.strictEqual(r.phaseIndex, 1, "a boundary belongs to the phase starting there")
  assert.strictEqual(r.phaseElapsedMs, 0)
  assert.strictEqual(r.phaseFraction, 0)
})

test("resolve rolls into the next cycle at the cycle boundary", () => {
  const r = Model.resolve(runningSession(16000), box, 1000)  // one full 16s cycle
  assert.strictEqual(r.cycleIndex, 1)
  assert.strictEqual(r.phaseIndex, 0)
  assert.strictEqual(r.phaseElapsedMs, 0)
})

test("resolve counts the session clock across cycles", () => {
  const r = Model.resolve(runningSession(20000), box, 1000)
  assert.strictEqual(r.sessionElapsedMs, 20000)
  assert.strictEqual(r.sessionDurationMs, 128000)
  assert.ok(Math.abs(r.sessionFraction - 20000 / 128000) < 1e-9)
})

test("resolve past the end reports done and stays inside the last phase", () => {
  const r = Model.resolve(runningSession(999999), box, 1000)
  assert.strictEqual(r.done, true)
  assert.strictEqual(r.cycleIndex, 7, "clamped to the last cycle, not wrapped to the first")
  assert.strictEqual(r.phaseIndex, box.phases.length - 1)
  assert.strictEqual(r.sessionFraction, 1)
  assert.strictEqual(r.sessionElapsedMs, r.sessionDurationMs)
})

test("resolve at exactly the session duration is done, not restarted", () => {
  const r = Model.resolve(runningSession(128000), box, 1000)
  assert.strictEqual(r.done, true)
  assert.strictEqual(r.cycleIndex, 7)
})

test("a RUNNING session keeps counting from the last heartbeat", () => {
  const s = runningSession(5000)
  s.savedAtMs = 10000
  const r = Model.resolve(s, box, 13000)   // 3s of wall clock since the write
  assert.strictEqual(r.sessionElapsedMs, 8000)
})

test("a PAUSED session is frozen where it stopped", () => {
  const s = runningSession(5000)
  s.state = "PAUSED"
  s.savedAtMs = 10000
  const r = Model.resolve(s, box, 999999)
  assert.strictEqual(r.sessionElapsedMs, 5000, "wall clock must not advance a paused session")
})

test("an IDLE session rests at the start of the first phase", () => {
  const s = runningSession(5000)
  s.state = "IDLE"
  const r = Model.resolve(s, box, 99999)
  assert.strictEqual(r.sessionElapsedMs, 0)
  assert.strictEqual(r.phaseIndex, 0)
  assert.strictEqual(r.done, false)
  assert.strictEqual(r.cycleCount, 8, "an idle session still knows how long it would be")
})

test("resolve walks the eight-phase alternate-nostril cycle correctly", () => {
  const nadi = Model.techniqueById("nadi-shodhana")
  const s = { state: "RUNNING", techniqueId: "nadi-shodhana", cycles: 6, savedAtMs: 0, elapsedMs: 12500 }
  const r = Model.resolve(s, nadi, 0)   // 4+4+4=12 done, half a second into the switch
  assert.strictEqual(r.phaseIndex, 3)
  assert.strictEqual(r.phaseKind, Model.PHASE.SWITCH)
  assert.strictEqual(r.phaseLabel, "Switch")
  // 13000 is the switch's closing boundary, which belongs to the phase starting there.
  const later = Model.resolve({ state: "RUNNING", cycles: 6, savedAtMs: 0, elapsedMs: 13000 }, nadi, 0)
  assert.strictEqual(later.phaseIndex, 4)
  assert.strictEqual(later.phaseLabel, "Inhale right", "the second half must name the other nostril")
})

test("resolve reports a breath index only inside a POWER_BREATHS phase", () => {
  const wh = Model.techniqueById("wim-hof")
  const mid = Model.resolve({ state: "RUNNING", cycles: 3, savedAtMs: 0, elapsedMs: 30000 }, wh, 0)
  assert.strictEqual(mid.phaseKind, Model.PHASE.POWER_BREATHS)
  assert.strictEqual(mid.breathCount, 30)
  assert.strictEqual(mid.breathIndex, 15, "halfway through 60s of 30 breaths is breath 16 (index 15)")
  const hold = Model.resolve({ state: "RUNNING", cycles: 3, savedAtMs: 0, elapsedMs: 90000 }, wh, 0)
  assert.strictEqual(hold.phaseKind, Model.PHASE.RETENTION)
  assert.strictEqual(hold.breathIndex, null)
  assert.strictEqual(hold.breathCount, null)
})

test("resolve flags holds so the guides know to count up", () => {
  assert.strictEqual(Model.resolve(runningSession(6000), box, 1000).isHold, true)
  assert.strictEqual(Model.resolve(runningSession(1000), box, 1000).isHold, false)
})

test("resolve carries the orb scale so both guides share one animation", () => {
  const r = Model.resolve(runningSession(2000), box, 1000)
  assert.strictEqual(r.orbScale, Model.orbScale(box, r.phaseIndex, r.phaseFraction))
})

test("resolve never returns NaN or a negative remaining", () => {
  const cases = [null, undefined, {}, { state: "RUNNING" }, runningSession(-500), runningSession(NaN)]
  cases.forEach(s => {
    const r = Model.resolve(s, box, 1000)
    assert.ok(isFinite(r.phaseRemainingMs) && r.phaseRemainingMs >= 0, "bad remaining for " + JSON.stringify(s))
    assert.ok(isFinite(r.sessionFraction) && r.sessionFraction >= 0, "bad fraction for " + JSON.stringify(s))
    assert.ok(isFinite(r.orbScale), "bad orbScale for " + JSON.stringify(s))
  })
})

test("resolve survives a technique with no phases", () => {
  const r = Model.resolve(runningSession(5000), { id: "x", phases: [] }, 1000)
  assert.strictEqual(r.phaseIndex, 0)
  assert.ok(isFinite(r.orbScale))
})

test("resolve handles a single-phase technique", () => {
  const single = { id: "hum", phases: [{ kind: "EXHALE", seconds: 6, label: "Out" }], defaultCycles: 5 }
  const r = Model.resolve({ state: "RUNNING", cycles: 5, savedAtMs: 0, elapsedMs: 9000 }, single, 0)
  assert.strictEqual(r.phaseIndex, 0)
  assert.strictEqual(r.cycleIndex, 1)
  assert.strictEqual(r.phaseElapsedMs, 3000)
})

test("effectiveElapsedMs ignores a savedAtMs in the future", () => {
  // A clock step backwards must not rewind the session below what was banked.
  const s = runningSession(5000)
  s.savedAtMs = 20000
  assert.strictEqual(Model.effectiveElapsedMs(s, 10000), 5000)
})

// ── formatting ─────────────────────────────────────────────────────────────

test("formatClock counts bare seconds under a minute and clocks above", () => {
  assert.strictEqual(Model.formatClock(4000), "4")
  assert.strictEqual(Model.formatClock(3500), "4", "a countdown rounds up so it never shows 0 while running")
  assert.strictEqual(Model.formatClock(0), "0")
  assert.strictEqual(Model.formatClock(60000), "1:00")
  assert.strictEqual(Model.formatClock(90000), "1:30")
  assert.strictEqual(Model.formatClock(-500), "0")
  assert.strictEqual(Model.formatClock(NaN), "0")
})

test("formatDuration reads as prose", () => {
  assert.strictEqual(Model.formatDuration(45), "45 sec")
  assert.strictEqual(Model.formatDuration(120), "2 min")
  assert.strictEqual(Model.formatDuration(3600), "1 h")
  assert.strictEqual(Model.formatDuration(4320), "1 h 12 min")
  assert.strictEqual(Model.formatDuration(-5), "0 sec")
})

// ── parsers ────────────────────────────────────────────────────────────────

test("every parser is total against garbage", () => {
  const garbage = ["", "{{{", "null", "[]", "12", undefined, null]
  garbage.forEach(raw => {
    assert.deepStrictEqual(typeof Model.parseConfig(raw), "object")
    assert.deepStrictEqual(typeof Model.parseStats(raw), "object")
    assert.deepStrictEqual(typeof Model.parseHistory(raw), "object")
    assert.deepStrictEqual(typeof Model.parseSession(raw), "object")
  })
  assert.deepStrictEqual(Model.parseConfig("{{{"), Model.defaultConfig())
  assert.deepStrictEqual(Model.parseHistory("nope").sessions, [])
  assert.strictEqual(Model.parseSession("nope").state, "IDLE")
})

test("parseConfig keeps stored values and fills missing ones", () => {
  const c = Model.parseConfig(JSON.stringify({ defaultTechniqueId: "coherent", silent: true }))
  assert.strictEqual(c.defaultTechniqueId, "coherent")
  assert.strictEqual(c.silent, true)
  assert.strictEqual(c.notifyOnEnd, true, "an absent key falls back to its default")
  assert.strictEqual(c.nudge.everyMinutes, 90)
})

test("parseConfig merges nudge key-by-key so an older file gains new fields", () => {
  const c = Model.parseConfig(JSON.stringify({ nudge: { enabled: true } }))
  assert.strictEqual(c.nudge.enabled, true)
  assert.strictEqual(c.nudge.quietFrom, "22:00", "a field the stored file never had must still default")
  assert.strictEqual(c.nudge.techniqueId, "physiological-sigh")
})

test("parseConfig clamps a nonsense overlay dim and cycle count", () => {
  assert.strictEqual(Model.parseConfig(JSON.stringify({ overlayDim: 5 })).overlayDim, 1)
  assert.strictEqual(Model.parseConfig(JSON.stringify({ overlayDim: -2 })).overlayDim, 0)
  assert.strictEqual(Model.parseConfig(JSON.stringify({ defaultCycles: 0 })).defaultCycles, 1)
})

test("parseStats repairs a file whose daily map or totals were mangled", () => {
  const s = Model.parseStats(JSON.stringify({ daily: "nope", totals: 4, streak: 3 }))
  assert.deepStrictEqual(s.daily, {})
  assert.deepStrictEqual(s.totals, { sessions: 0, seconds: 0, cycles: 0 })
  assert.strictEqual(s.streak, 3)
})

test("parseSession floors a negative elapsed", () => {
  assert.strictEqual(Model.parseSession(JSON.stringify({ elapsedMs: -900 })).elapsedMs, 0)
})

test("a fresh session is not looping and has skipped nothing", () => {
  const s = Model.defaultSession()
  assert.strictEqual(s.loop, false)
  assert.strictEqual(s.skipMs, 0)
})

test("parseSession keeps the loop flag and floors a bad skipMs", () => {
  assert.strictEqual(Model.parseSession(JSON.stringify({ loop: true })).loop, true)
  assert.strictEqual(Model.parseSession(JSON.stringify({ loop: "yes" })).loop, false, "only a real true is looping")
  assert.strictEqual(Model.parseSession(JSON.stringify({ skipMs: -5 })).skipMs, 0)
  assert.strictEqual(Model.parseSession(JSON.stringify({ skipMs: 60000 })).skipMs, 60000)
})

test("parseConfig defaults loop off and keeps a stored one", () => {
  assert.strictEqual(Model.parseConfig("{}").loop, false)
  assert.strictEqual(Model.parseConfig(JSON.stringify({ loop: true })).loop, true)
  assert.strictEqual(Model.parseConfig(JSON.stringify({ loop: 1 })).loop, false)
})

test("parseConfig defaults spoken cues off and coerces to a real boolean", () => {
  assert.strictEqual(Model.parseConfig("{}").cueVoice, false)
  assert.strictEqual(Model.parseConfig(JSON.stringify({ cueVoice: true })).cueVoice, true)
  assert.strictEqual(Model.parseConfig(JSON.stringify({ cueVoice: "yes" })).cueVoice, false)
})

test("serializeConfig round-trips through parseConfig", () => {
  const c = Model.defaultConfig()
  c.defaultTechniqueId = "wim-hof"
  assert.deepStrictEqual(Model.parseConfig(Model.serializeConfig(c)), c)
})

// ── custom techniques ──────────────────────────────────────────────────────

test("allTechniques and techniqueById include customs from config", () => {
  const config = { customTechniques: [{ id: "custom-mine", name: "Mine", phases: [{ kind: "INHALE", seconds: 3 }] }] }
  assert.strictEqual(Model.allTechniques(config).length, Model.TECHNIQUES.length + 1)
  assert.strictEqual(Model.techniqueById("custom-mine", config).name, "Mine")
  assert.strictEqual(Model.techniqueById("custom-mine"), null, "without the config it is unknown")
  assert.strictEqual(Model.techniqueById("nope", config), null)
})

test("allTechniques ignores a custom entry with no id", () => {
  const config = { customTechniques: [{ name: "broken" }, null] }
  assert.strictEqual(Model.allTechniques(config).length, Model.TECHNIQUES.length)
})

test("validateCustom accepts a good pattern and normalises it", () => {
  const r = Model.validateCustom({
    name: "My Slow One",
    phases: [{ kind: "INHALE", seconds: 6 }, { kind: "EXHALE", seconds: 10 }],
    defaultCycles: 5, tone: "positive"
  })
  assert.strictEqual(r.ok, true)
  assert.deepStrictEqual(r.errors, [])
  assert.strictEqual(r.technique.id, "custom-my-slow-one")
  assert.strictEqual(r.technique.family, "custom")
  assert.strictEqual(r.technique.pattern, "6-10")
  assert.strictEqual(r.technique.phases[0].label, "Inhale", "a missing label falls back to the kind")
})

test("validateCustom rejects the things a builder form can get wrong", () => {
  assert.strictEqual(Model.validateCustom({ name: "", phases: [{ kind: "INHALE", seconds: 4 }] }).ok, false)
  assert.strictEqual(Model.validateCustom({ name: "X", phases: [] }).ok, false)
  assert.strictEqual(Model.validateCustom({ name: "X", phases: [{ kind: "INHALE", seconds: 0 }] }).ok, false)
  assert.strictEqual(Model.validateCustom({ name: "X", phases: [{ kind: "NOPE", seconds: 4 }] }).ok, false)
  assert.strictEqual(Model.validateCustom({ name: "Box", id: "box", phases: [{ kind: "INHALE", seconds: 4 }] }).ok, false)
  assert.strictEqual(Model.validateCustom({ name: "X", phases: [{ kind: "INHALE", seconds: 4000 }] }).ok, false)
  assert.strictEqual(Model.validateCustom(null).ok, false)
})

test("validateCustom errors are phrased for a human next to the field", () => {
  const r = Model.validateCustom({ name: "X", phases: [{ kind: "INHALE", seconds: -1 }] })
  assert.ok(r.errors.some(e => /Phase 1/.test(e)), "an error should name the phase it belongs to: " + r.errors)
})

test("validateCustom defaults a power-breath count", () => {
  const r = Model.validateCustom({ name: "Fast", phases: [{ kind: "POWER_BREATHS", seconds: 40 }] })
  assert.strictEqual(r.technique.phases[0].breaths, 30)
})

test("a validated custom technique resolves and animates like a built-in", () => {
  // The real integration risk: a custom pattern must survive the same envelope
  // and resolve path as a built-in, not just pass validation.
  const t = Model.validateCustom({
    name: "Sighing", phases: [
      { kind: "INHALE", seconds: 2 }, { kind: "INHALE_TOP", seconds: 1 }, { kind: "EXHALE", seconds: 5 }
    ], defaultCycles: 3
  }).technique
  for (let i = 0; i < t.phases.length; i++) {
    const next = (i + 1) % t.phases.length
    assert.ok(Math.abs(Model.orbScale(t, i, 1) - Model.orbScale(t, next, 0)) < 1e-9, "seam at phase " + i)
  }
  const r = Model.resolve({ state: "RUNNING", cycles: 3, savedAtMs: 0, elapsedMs: 2500 }, t, 0)
  assert.strictEqual(r.phaseKind, Model.PHASE.INHALE_TOP)
})

// ── metrics ────────────────────────────────────────────────────────────────

const DAY = 86400000
const NOW = new Date(2026, 8, 10, 14, 30, 0).getTime()   // a fixed local afternoon

function historyOf(entries) { return { version: 1, sessions: entries } }

function entry(daysAgo, techniqueId, seconds, completed, hour) {
  const d = new Date(NOW - daysAgo * DAY)
  if (hour !== undefined) d.setHours(hour, 0, 0, 0)
  return {
    id: "s" + daysAgo + techniqueId, techniqueId: techniqueId, startedAtMs: d.getTime(),
    seconds: seconds, cycles: 8, plannedCycles: 8, completed: completed
  }
}

test("dailyBuckets is dense, oldest-first, and includes zero days", () => {
  const stats = Model.defaultStats()
  stats.daily[Model.dateStringOf(NOW)] = { sessions: 2, seconds: 300, cycles: 16 }
  stats.daily[Model.dateStringOf(NOW - 3 * DAY)] = { sessions: 1, seconds: 120, cycles: 8 }
  const b = Model.dailyBuckets(stats, 7, NOW)
  assert.strictEqual(b.length, 7)
  assert.strictEqual(b[6].date, Model.dateStringOf(NOW), "the newest day is last")
  assert.strictEqual(b[6].sessions, 2)
  assert.strictEqual(b[3].seconds, 120)
  assert.strictEqual(b[5].sessions, 0, "a gap day must be present and zero, not missing")
})

test("dailyBuckets survives empty and malformed stats", () => {
  assert.strictEqual(Model.dailyBuckets(null, 7, NOW).length, 7)
  assert.strictEqual(Model.dailyBuckets({ daily: { "2026-09-10": "nope" } }, 3, NOW)[2].seconds, 0)
})

test("streakOf never reports a best below the current", () => {
  assert.deepStrictEqual(Model.streakOf({ streak: 4, bestStreak: 9 }), { current: 4, best: 9 })
  assert.deepStrictEqual(Model.streakOf({ streak: 12, bestStreak: 3 }), { current: 12, best: 12 })
  assert.deepStrictEqual(Model.streakOf(null), { current: 0, best: 0 })
})

test("totals floors missing or negative counters", () => {
  assert.deepStrictEqual(Model.totals({ totals: { sessions: 5, seconds: 900, cycles: 40 } }),
    { sessions: 5, seconds: 900, cycles: 40 })
  assert.deepStrictEqual(Model.totals(null), { sessions: 0, seconds: 0, cycles: 0 })
})

test("techniqueBreakdown ranks by time and shares add to one", () => {
  const h = historyOf([
    entry(1, "box", 300, true), entry(2, "box", 300, true), entry(3, "coherent", 200, true)
  ])
  const b = Model.techniqueBreakdown(h, 30, NOW)
  assert.strictEqual(b[0].id, "box")
  assert.strictEqual(b[0].sessions, 2)
  assert.strictEqual(b[0].seconds, 600)
  assert.strictEqual(b[0].name, "Box", "it resolves the display name from the catalogue")
  assert.ok(Math.abs(b.reduce((s, x) => s + x.pct, 0) - 1) < 1e-9)
})

test("techniqueBreakdown names an unknown technique by its id rather than dropping it", () => {
  const b = Model.techniqueBreakdown(historyOf([entry(1, "deleted-custom", 100, true)]), 30, NOW)
  assert.strictEqual(b[0].name, "deleted-custom")
})

test("hourHeatmap buckets by local hour of day", () => {
  const h = historyOf([entry(1, "box", 100, true, 7), entry(2, "box", 100, true, 7), entry(3, "box", 100, true, 22)])
  const map = Model.hourHeatmap(h, 30, NOW)
  assert.strictEqual(map.length, 24)
  assert.strictEqual(map[7], 2)
  assert.strictEqual(map[22], 1)
  assert.strictEqual(map[3], 0)
})

test("completionRate splits completed from abandoned", () => {
  const h = historyOf([entry(1, "box", 100, true), entry(2, "box", 50, false), entry(3, "box", 100, true)])
  const r = Model.completionRate(h, 30, NOW)
  assert.strictEqual(r.completed, 2)
  assert.strictEqual(r.abandoned, 1)
  assert.strictEqual(r.total, 3)
  assert.ok(Math.abs(r.pct - 2 / 3) < 1e-9)
  assert.strictEqual(Model.completionRate(historyOf([]), 30, NOW).pct, 0, "no data must not divide by zero")
})

test("the reducers drop malformed records instead of throwing", () => {
  const h = historyOf([null, {}, "nope", { startedAtMs: 0 }, entry(1, "box", 100, true), 42])
  assert.strictEqual(Model.sessionsWithin(h, 30, NOW).length, 1)
  assert.strictEqual(Model.completionRate(h, 30, NOW).total, 1)
  assert.strictEqual(Model.techniqueBreakdown(h, 30, NOW).length, 1)
  assert.strictEqual(Model.hourHeatmap(h, 30, NOW).length, 24)
})

test("sessionsWithin excludes anything outside the window", () => {
  const h = historyOf([entry(1, "box", 100, true), entry(40, "box", 100, true), entry(-5, "box", 100, true)])
  const within = Model.sessionsWithin(h, 30, NOW)
  assert.strictEqual(within.length, 1, "a 40-day-old and a future-dated record must both be excluded")
})

test("suggestTechnique stays quiet until there is enough data", () => {
  assert.strictEqual(Model.suggestTechnique(historyOf([]), null, NOW), null)
  assert.strictEqual(Model.suggestTechnique(historyOf([entry(1, "box", 100, true)]), null, NOW), null)
})

test("suggestTechnique offers the wind-down pattern late at night", () => {
  const lateNight = new Date(2026, 8, 10, 23, 15, 0).getTime()
  const h = historyOf([1, 2, 3, 4, 5].map(d => entry(d, "box", 200, true)))
  const s = Model.suggestTechnique(h, null, lateNight)
  assert.ok(s && s.techniqueId === "relaxing478", "expected the relaxing suggestion, got " + JSON.stringify(s))
  assert.ok(s.reason.length > 0)
})

test("suggestTechnique nudges toward variety when one technique dominates", () => {
  const h = historyOf([1, 2, 3, 4, 5, 6].map(d => entry(d, "box", 200, true)))
  const s = Model.suggestTechnique(h, null, NOW)
  assert.ok(s && s.techniqueId === "coherent", "expected a change of pace, got " + JSON.stringify(s))
})

test("suggestTechnique offers a shorter pattern when sessions keep getting cut short", () => {
  const h = historyOf([1, 2, 3, 4, 5].map(d => entry(d, d % 2 ? "box" : "coherent", 40, false)))
  const s = Model.suggestTechnique(h, null, NOW)
  assert.ok(s && s.techniqueId === "physiological-sigh", "expected the short one, got " + JSON.stringify(s))
})

console.log("\n" + passed + " passed" + (process.exitCode ? "  (with failures above)" : ""))
