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
  assert.strictEqual(n.summary, "☕ Short Break ready")
  assert.match(n.body, /start/i)
})

test("reminderNotification for a ready work phase tells the user to start it", () => {
  const n = Model.reminderNotification(Model.PHASE_WORK)
  assert.strictEqual(n.summary, "🍅 Work ready")
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
