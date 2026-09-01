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

test("reminderIntervalMs uses config.reminderMinutes", () => {
  assert.strictEqual(Model.reminderIntervalMs({ reminderMinutes: 3 }), 3 * 60000)
})

test("reminderIntervalMs falls back to 5 minutes when unset", () => {
  assert.strictEqual(Model.reminderIntervalMs({}), 5 * 60000)
})

test("reminderIntervalMs floors non-positive values to 1 minute", () => {
  assert.strictEqual(Model.reminderIntervalMs({ reminderMinutes: 0 }), 60000)
})

test("reminderNotification for a ready short break tells the user to start it", () => {
  const n = Model.reminderNotification(Model.PHASE_SHORT_BREAK)
  assert.strictEqual(n.summary, " Short Break ready")
  assert.match(n.body, /start/i)
})

test("reminderNotification for a ready work phase tells the user to start it", () => {
  const n = Model.reminderNotification(Model.PHASE_WORK)
  assert.strictEqual(n.summary, " Work ready")
  assert.match(n.body, /start/i)
})

test("readyIcon is distinct from the phase icons so a waiting phase reads differently", () => {
  const icon = Model.readyIcon()
  assert.notStrictEqual(icon, Model.phaseIcon(Model.PHASE_WORK))
  assert.notStrictEqual(icon, Model.phaseIcon(Model.PHASE_SHORT_BREAK))
  assert.notStrictEqual(icon, Model.phaseIcon(Model.PHASE_LONG_BREAK))
})

test("soundPlayCommand builds an execDetached argv that passes the path as $1 (no shell interpolation)", () => {
  const cmd = Model.soundPlayCommand("/tmp/a b.oga")
  assert.strictEqual(cmd[0], "sh")
  assert.strictEqual(cmd[1], "-c")
  assert.strictEqual(cmd[cmd.length - 1], "/tmp/a b.oga")
})

test("soundPlayCommand tries multiple players so a missing mpv isn't fatal", () => {
  const script = Model.soundPlayCommand("/x.oga")[2]
  assert.match(script, /mpv/)
  assert.match(script, /paplay/)
  assert.match(script, /pw-play/)
  assert.match(script, /canberra-gtk-play/)
})

test("recordWorkSession appends and trims to the retention window", () => {
  const history = Model.defaultHistory()
  for (let i = 0; i < 205; i++) Model.recordWorkSession(history, 25, true)
  assert.strictEqual(history.sessions.length, 200)
})

test("suggestedWorkMinutes returns null with too little same-length history", () => {
  const history = Model.defaultHistory()
  for (let i = 0; i < 4; i++) Model.recordWorkSession(history, 25, false)
  assert.strictEqual(Model.suggestedWorkMinutes(history, 25), null)
})

test("suggestedWorkMinutes suggests shorter after frequent interruptions", () => {
  const history = Model.defaultHistory()
  for (let i = 0; i < 6; i++) Model.recordWorkSession(history, 25, false)
  assert.strictEqual(Model.suggestedWorkMinutes(history, 25), 20)
})

test("suggestedWorkMinutes never suggests below 10 minutes", () => {
  const history = Model.defaultHistory()
  for (let i = 0; i < 6; i++) Model.recordWorkSession(history, 12, false)
  assert.strictEqual(Model.suggestedWorkMinutes(history, 12), 10)
})

test("suggestedWorkMinutes suggests longer after an unbroken completion streak", () => {
  const history = Model.defaultHistory()
  for (let i = 0; i < 6; i++) Model.recordWorkSession(history, 25, true)
  assert.strictEqual(Model.suggestedWorkMinutes(history, 25), 30)
})

test("suggestedWorkMinutes never suggests above 50 minutes", () => {
  const history = Model.defaultHistory()
  for (let i = 0; i < 6; i++) Model.recordWorkSession(history, 48, true)
  assert.strictEqual(Model.suggestedWorkMinutes(history, 48), 50)
})

test("suggestedWorkMinutes stays silent on a balanced mix", () => {
  const history = Model.defaultHistory()
  for (let i = 0; i < 3; i++) Model.recordWorkSession(history, 25, true)
  for (let i = 0; i < 3; i++) Model.recordWorkSession(history, 25, false)
  assert.strictEqual(Model.suggestedWorkMinutes(history, 25), null)
})

test("suggestedWorkMinutes only looks at sessions at the current length", () => {
  const history = Model.defaultHistory()
  for (let i = 0; i < 6; i++) Model.recordWorkSession(history, 45, false)
  assert.strictEqual(Model.suggestedWorkMinutes(history, 25), null)
})

test("phaseProgress is 0 at the start of a work phase and 1 when it hits zero", () => {
  const config = Model.defaultConfig()
  const total = Model.phaseDurationMs(Model.PHASE_WORK, config)
  assert.strictEqual(Model.phaseProgress(Model.PHASE_WORK, total, config), 0)
  assert.strictEqual(Model.phaseProgress(Model.PHASE_WORK, 0, config), 1)
})

test("phaseProgress reports the elapsed fraction mid-phase", () => {
  const config = Model.defaultConfig()
  const total = Model.phaseDurationMs(Model.PHASE_SHORT_BREAK, config) // 5 min
  assert.strictEqual(Model.phaseProgress(Model.PHASE_SHORT_BREAK, total / 5, config), 0.8)
})

test("phaseProgress clamps a stale or overshot remainingMs into [0, 1]", () => {
  const config = Model.defaultConfig()
  const total = Model.phaseDurationMs(Model.PHASE_WORK, config)
  assert.strictEqual(Model.phaseProgress(Model.PHASE_WORK, total * 2, config), 0)
  assert.strictEqual(Model.phaseProgress(Model.PHASE_WORK, -5000, config), 1)
})

test("phaseProgress is 0 for IDLE (no phase length to measure against)", () => {
  assert.strictEqual(Model.phaseProgress(Model.PHASE_IDLE, 0, Model.defaultConfig()), 0)
})

test("phaseProgress is 0 for a zero-length break rather than dividing by zero", () => {
  const config = Object.assign(Model.defaultConfig(), { longBreakMinutes: 0 })
  assert.strictEqual(Model.phaseProgress(Model.PHASE_LONG_BREAK, 0, config), 0)
})

test("parseSession returns an idle session for empty / missing / malformed input", () => {
  assert.deepStrictEqual(Model.parseSession(""), Model.defaultSession())
  assert.deepStrictEqual(Model.parseSession(null), Model.defaultSession())
  assert.deepStrictEqual(Model.parseSession("{oops"), Model.defaultSession())
})

test("parseSession reads a running work session from a good file", () => {
  const s = Model.parseSession(JSON.stringify({
    phase: "WORK", running: true, ready: false, remainingMs: 600000,
    elapsedReadyMs: 0, completedPomodorosThisSession: 2, savedAtMs: 1000
  }))
  assert.strictEqual(s.phase, "WORK")
  assert.strictEqual(s.running, true)
  assert.strictEqual(s.remainingMs, 600000)
  assert.strictEqual(s.completedPomodorosThisSession, 2)
  assert.strictEqual(s.savedAtMs, 1000)
})

test("parseSession rejects an unknown phase and forces idle fields consistent", () => {
  const s = Model.parseSession(JSON.stringify({ phase: "BOGUS", running: true, remainingMs: 5 }))
  assert.strictEqual(s.phase, "IDLE")
  assert.strictEqual(s.running, false)
  assert.strictEqual(s.remainingMs, 0)
})

test("parseSession coerces non-finite numbers to safe defaults", () => {
  const s = Model.parseSession(JSON.stringify({ phase: "WORK", remainingMs: "nope", savedAtMs: null }))
  assert.strictEqual(s.remainingMs, 0)
  assert.strictEqual(s.savedAtMs, 0)
})

test("restoreSession leaves an idle session idle", () => {
  const r = Model.restoreSession(Model.defaultSession(), 999999, Model.defaultConfig())
  assert.strictEqual(r.phase, "IDLE")
  assert.strictEqual(r.running, false)
})

test("restoreSession subtracts downtime from a running phase that still has time left", () => {
  const config = Model.defaultConfig()
  const saved = { phase: "WORK", running: true, ready: false, remainingMs: 600000, elapsedReadyMs: 0, completedPomodorosThisSession: 1, savedAtMs: 10000 }
  const r = Model.restoreSession(saved, 10000 + 90000, config) // 90s downtime
  assert.strictEqual(r.phase, "WORK")
  assert.strictEqual(r.running, true)
  assert.strictEqual(r.remainingMs, 600000 - 90000)
  assert.strictEqual(r.workCompletedOffline, false)
})

test("restoreSession rolls a running WORK phase that ran out while away into a ready short break", () => {
  const config = Model.defaultConfig() // work 25, short 5, longBreakCycle 4
  const saved = { phase: "WORK", running: true, ready: false, remainingMs: 60000, elapsedReadyMs: 0, completedPomodorosThisSession: 0, savedAtMs: 0 }
  const r = Model.restoreSession(saved, 200000, config) // 200s downtime, phase had 60s left
  assert.strictEqual(r.phase, "SHORT_BREAK")
  assert.strictEqual(r.running, false)
  assert.strictEqual(r.ready, true)
  assert.strictEqual(r.remainingMs, Model.phaseDurationMs("SHORT_BREAK", config))
  assert.strictEqual(r.completedPomodorosThisSession, 1)
  assert.strictEqual(r.workCompletedOffline, true)
  assert.strictEqual(r.elapsedReadyMs, 140000) // 200s downtime - 60s that finished the phase
})

test("restoreSession sends the 4th completed WORK to a long break", () => {
  const config = Model.defaultConfig()
  const saved = { phase: "WORK", running: true, ready: false, remainingMs: 1000, elapsedReadyMs: 0, completedPomodorosThisSession: 3, savedAtMs: 0 }
  const r = Model.restoreSession(saved, 5000, config)
  assert.strictEqual(r.phase, "LONG_BREAK")
  assert.strictEqual(r.completedPomodorosThisSession, 4)
})

test("restoreSession caps the carried-over ready counter at one phase length", () => {
  const config = Model.defaultConfig()
  const saved = { phase: "WORK", running: true, ready: false, remainingMs: 1000, elapsedReadyMs: 0, completedPomodorosThisSession: 0, savedAtMs: 0 }
  const r = Model.restoreSession(saved, 7 * 24 * 3600 * 1000, config) // a week away
  assert.strictEqual(r.elapsedReadyMs, Model.phaseDurationMs("SHORT_BREAK", config))
})

test("restoreSession adds downtime to a phase that was already waiting 'ready'", () => {
  const config = Model.defaultConfig()
  const saved = { phase: "SHORT_BREAK", running: false, ready: true, remainingMs: 300000, elapsedReadyMs: 20000, completedPomodorosThisSession: 1, savedAtMs: 1000 }
  const r = Model.restoreSession(saved, 1000 + 45000, config)
  assert.strictEqual(r.ready, true)
  assert.strictEqual(r.elapsedReadyMs, 65000)
  assert.strictEqual(r.workCompletedOffline, false)
})

test("restoreSession keeps a paused mid-phase timer frozen across downtime", () => {
  const config = Model.defaultConfig()
  const saved = { phase: "WORK", running: false, ready: false, remainingMs: 420000, elapsedReadyMs: 0, completedPomodorosThisSession: 2, savedAtMs: 1000 }
  const r = Model.restoreSession(saved, 1000 + 999999, config)
  assert.strictEqual(r.phase, "WORK")
  assert.strictEqual(r.running, false)
  assert.strictEqual(r.ready, false)
  assert.strictEqual(r.remainingMs, 420000)
})

test("restoreSession tolerates a savedAtMs in the future (clock moved back) — no negative downtime", () => {
  const config = Model.defaultConfig()
  const saved = { phase: "WORK", running: true, ready: false, remainingMs: 600000, elapsedReadyMs: 0, completedPomodorosThisSession: 0, savedAtMs: 5000 }
  const r = Model.restoreSession(saved, 1000, config)
  assert.strictEqual(r.remainingMs, 600000)
  assert.strictEqual(r.running, true)
})

test("parseConfig returns defaults for empty / missing / malformed input", () => {
  assert.deepStrictEqual(Model.parseConfig(""), Model.defaultConfig())
  assert.deepStrictEqual(Model.parseConfig(null), Model.defaultConfig())
  assert.deepStrictEqual(Model.parseConfig("{oops"), Model.defaultConfig())
})

test("parseConfig adopts only keys present in the default schema", () => {
  const c = Model.parseConfig(JSON.stringify({ workMinutes: 30, bogus: 9 }))
  assert.strictEqual(c.workMinutes, 30)
  assert.strictEqual(c.bogus, undefined)
  assert.strictEqual(c.shortBreakMinutes, 5) // untouched default
})

test("parseConfig takes a stored sounds object as-is", () => {
  const c = Model.parseConfig(JSON.stringify({ sounds: { workStart: "/x.oga", breakStart: "", longBreakStart: "" } }))
  assert.strictEqual(c.sounds.workStart, "/x.oga")
})

test("parseStats returns a zero streak / empty daily for empty input", () => {
  assert.deepStrictEqual(Model.parseStats(""), Model.defaultStats())
})

test("parseStats reads streak, lastActiveDate and daily from a good file", () => {
  const s = Model.parseStats(JSON.stringify({ streak: 4, lastActiveDate: "2026-09-01", daily: { "2026-09-01": { completed: 2, focusedMs: 3000 } } }))
  assert.strictEqual(s.streak, 4)
  assert.strictEqual(s.lastActiveDate, "2026-09-01")
  assert.strictEqual(s.daily["2026-09-01"].completed, 2)
})

test("parseStats rejects a non-object daily", () => {
  assert.deepStrictEqual(Model.parseStats(JSON.stringify({ daily: "nope" })).daily, {})
})

test("parseStats degrades to defaults on malformed JSON", () => {
  assert.deepStrictEqual(Model.parseStats("<xml/>"), Model.defaultStats())
})

test("parseHistory returns an empty session log for empty input", () => {
  assert.deepStrictEqual(Model.parseHistory(""), Model.defaultHistory())
})

test("parseHistory reads a sessions array from a good file", () => {
  const h = Model.parseHistory(JSON.stringify({ sessions: [{ minutes: 25, completed: true, date: "2026-09-01" }] }))
  assert.strictEqual(h.sessions.length, 1)
  assert.strictEqual(h.sessions[0].minutes, 25)
})

test("parseHistory ignores a non-array sessions field", () => {
  assert.deepStrictEqual(Model.parseHistory(JSON.stringify({ sessions: 5 })).sessions, [])
})

test("parseHistory degrades to defaults on malformed JSON", () => {
  assert.deepStrictEqual(Model.parseHistory("not json"), Model.defaultHistory())
})
