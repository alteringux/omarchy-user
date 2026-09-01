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

test("defaultState starts at zero with empty history", () => {
  const s = Model.defaultState()
  assert.strictEqual(s.score, 0)
  assert.deepStrictEqual(s.history, [])
})

test("formatScore prefixes the icon when showIcon is set", () => {
  assert.strictEqual(Model.formatScore(7, { showIcon: true, icon: "" }), " 7")
})

test("formatScore drops the icon when showIcon is false", () => {
  assert.strictEqual(Model.formatScore(7, { showIcon: false, icon: "" }), "7")
})

test("formatScore tolerates a null config instead of throwing", () => {
  assert.strictEqual(Model.formatScore(3, null), "3")
})

test("formatScore falls back to the default icon when one is missing", () => {
  assert.strictEqual(Model.formatScore(1, { showIcon: true }), " 1")
})

test("increment adds the configured step and logs it", () => {
  const next = Model.increment(Model.defaultState(), { step: 5 })
  assert.strictEqual(next.score, 5)
  assert.strictEqual(next.history.length, 1)
  assert.strictEqual(next.history[0].action, "increment")
  assert.strictEqual(next.history[0].value, 5)
  assert.strictEqual(typeof next.history[0].timestamp, "number")
})

test("decrement subtracts the configured step and logs it", () => {
  const next = Model.decrement({ score: 10, history: [] }, { step: 3 })
  assert.strictEqual(next.score, 7)
  assert.strictEqual(next.history[0].action, "decrement")
  assert.strictEqual(next.history[0].value, 3)
})

test("reset returns to initialValue and records the from/to pair", () => {
  const next = Model.reset({ score: 42, history: [] }, { initialValue: 0 })
  assert.strictEqual(next.score, 0)
  assert.strictEqual(next.history[0].action, "reset")
  assert.strictEqual(next.history[0].from, 42)
  assert.strictEqual(next.history[0].to, 0)
})

test("a garbled step never poisons the score with NaN", () => {
  const next = Model.increment({ score: 4, history: [] }, { step: "oops" })
  assert.strictEqual(next.score, 5) // falls back to step 1
})

test("a garbled stored score is treated as zero before the delta", () => {
  const next = Model.increment({ score: "corrupt", history: [] }, { step: 2 })
  assert.strictEqual(next.score, 2)
})

test("reducers do not mutate the input state", () => {
  const state = { score: 0, history: [] }
  Model.increment(state, { step: 1 })
  assert.strictEqual(state.score, 0)
  assert.strictEqual(state.history.length, 0)
})

test("reducers create a history array when the input lacks one", () => {
  const next = Model.increment({ score: 0 }, { step: 1 })
  assert.strictEqual(next.history.length, 1)
})

test("trimHistory keeps only the most recent maxEntries", () => {
  const history = []
  for (let i = 0; i < 10; i++) history.push({ action: "increment", value: 1, timestamp: i })
  const trimmed = Model.trimHistory({ score: 10, history: history }, 3)
  assert.strictEqual(trimmed.history.length, 3)
  assert.strictEqual(trimmed.history[0].timestamp, 7)
})

test("trimHistory is a no-op below the limit", () => {
  const trimmed = Model.trimHistory({ score: 1, history: [{ action: "increment", value: 1, timestamp: 0 }] }, 50)
  assert.strictEqual(trimmed.history.length, 1)
})

test("setScore overrides the score without touching history", () => {
  const next = Model.setScore({ score: 5, history: [{ action: "increment", value: 5, timestamp: 0 }] }, 99)
  assert.strictEqual(next.score, 99)
  assert.strictEqual(next.history.length, 1)
})

test("parseConfig returns the defaults for empty / missing input", () => {
  assert.deepStrictEqual(Model.parseConfig(""), Model.defaultConfig())
  assert.deepStrictEqual(Model.parseConfig(null), Model.defaultConfig())
})

test("parseConfig adopts only keys that exist in the default schema", () => {
  const c = Model.parseConfig(JSON.stringify({ step: 5, icon: "★", bogus: 1 }))
  assert.strictEqual(c.step, 5)
  assert.strictEqual(c.icon, "★")
  assert.strictEqual(c.bogus, undefined)
  assert.strictEqual(c.initialValue, 0) // untouched default
})

test("parseConfig degrades to all-defaults on malformed JSON", () => {
  assert.deepStrictEqual(Model.parseConfig("{not json"), Model.defaultConfig())
})

test("parseState returns score 0 / empty history for empty / missing input", () => {
  assert.deepStrictEqual(Model.parseState(""), Model.defaultState())
  assert.deepStrictEqual(Model.parseState(undefined), Model.defaultState())
})

test("parseState reads score and history from a good file", () => {
  const s = Model.parseState(JSON.stringify({ score: 12, history: [{ action: "increment", value: 1, timestamp: 0 }] }))
  assert.strictEqual(s.score, 12)
  assert.strictEqual(s.history.length, 1)
})

test("parseState coerces a non-numeric stored score to 0", () => {
  assert.strictEqual(Model.parseState(JSON.stringify({ score: "oops" })).score, 0)
})

test("parseState ignores a non-array history", () => {
  assert.deepStrictEqual(Model.parseState(JSON.stringify({ score: 3, history: "nope" })).history, [])
})

test("parseState degrades to defaults on malformed JSON", () => {
  assert.deepStrictEqual(Model.parseState("<xml/>"), Model.defaultState())
})

// ---------------------------------------------------------------- undo

test("undo reverses the last increment and drops it from history", () => {
  const cfg = Model.defaultConfig()
  let s = Model.increment(Model.defaultState(), cfg) // score 1
  s = Model.increment(s, cfg)                        // score 2
  s = Model.undo(s)
  assert.strictEqual(s.score, 1)
  assert.strictEqual(s.history.length, 1)
})

test("undo reverses a decrement (adds the delta back)", () => {
  const cfg = { step: 3, initialValue: 0, showIcon: false, icon: "" }
  let s = Model.decrement(Model.defaultState(), cfg) // score -3
  s = Model.undo(s)
  assert.strictEqual(s.score, 0)
  assert.strictEqual(s.history.length, 0)
})

test("undo of a reset restores the pre-reset score", () => {
  const cfg = { step: 1, initialValue: 0, showIcon: false, icon: "" }
  let s = Model.increment(Model.increment(Model.defaultState(), cfg), cfg) // 2
  s = Model.reset(s, cfg)                                                  // 0, history has reset{from:2}
  assert.strictEqual(s.score, 0)
  s = Model.undo(s)
  assert.strictEqual(s.score, 2)
  assert.strictEqual(s.history.length, 2) // reset entry popped, the two increments remain
})

test("undo is a no-op with empty history and does not mutate the input", () => {
  const s0 = Model.defaultState()
  const s1 = Model.undo(s0)
  assert.deepStrictEqual(s1, Model.defaultState())
  assert.deepStrictEqual(s0, Model.defaultState())
})

test("canUndo reflects history presence", () => {
  assert.strictEqual(Model.canUndo(Model.defaultState()), false)
  assert.strictEqual(Model.canUndo(Model.increment(Model.defaultState(), Model.defaultConfig())), true)
  assert.strictEqual(Model.canUndo(null), false)
})
