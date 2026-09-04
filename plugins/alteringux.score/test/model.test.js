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

test("canUndo reflects history presence", () => {
  assert.strictEqual(Model.canUndo(Model.defaultState()), false)
  assert.strictEqual(Model.canUndo({ score: 1, history: [{ action: "increment", value: 1, timestamp: 0 }] }), true)
  assert.strictEqual(Model.canUndo(null), false)
})
