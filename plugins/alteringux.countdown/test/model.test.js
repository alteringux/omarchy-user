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

test("formatRemaining pads minutes and seconds under an hour", () => {
  assert.strictEqual(Model.formatRemaining(65), "01:05")
})

test("formatRemaining includes hours once remaining crosses an hour", () => {
  assert.strictEqual(Model.formatRemaining(3661), "1:01:01")
})

test("parseState rejects empty input", () => {
  assert.strictEqual(Model.parseState(""), null)
})

test("parseState rejects input without a numeric end_epoch", () => {
  assert.strictEqual(Model.parseState(JSON.stringify({ label: "x" })), null)
})

test("parseState accepts a well-formed state blob", () => {
  const state = Model.parseState(JSON.stringify({ end_epoch: 100, total_seconds: 60, label: "Tea" }))
  assert.strictEqual(state.end_epoch, 100)
  assert.strictEqual(state.label, "Tea")
})

test("canStart rejects zero, the Quick slider's floor", () => {
  assert.strictEqual(Model.canStart(0), false)
})

test("canStart rejects negative or non-numeric durations", () => {
  assert.strictEqual(Model.canStart(-1), false)
  assert.strictEqual(Model.canStart(NaN), false)
})

test("canStart accepts any duration of at least one unit", () => {
  assert.strictEqual(Model.canStart(1), true)
  assert.strictEqual(Model.canStart(180), true)
})

test("mode constants are the literal strings the bash script's --seconds flag decision depends on", () => {
  assert.strictEqual(Model.MODE_MINUTES, "minutes")
  assert.strictEqual(Model.MODE_SECONDS, "seconds")
})

test("rankPresets ranks by frequency, most-used first", () => {
  const history = [
    { mode: "minutes", duration: 25, label: "Focus" },
    { mode: "minutes", duration: 5, label: "Tea" },
    { mode: "minutes", duration: 25, label: "Focus" },
    { mode: "minutes", duration: 25, label: "Focus" },
  ]
  const ranked = Model.rankPresets(history, 4)
  assert.strictEqual(ranked[0].label, "Focus")
  assert.strictEqual(ranked[0].count, 3)
  assert.strictEqual(ranked[1].label, "Tea")
})

test("rankPresets treats distinct mode/duration/label combos separately", () => {
  const history = [
    { mode: "minutes", duration: 5, label: "" },
    { mode: "seconds", duration: 5, label: "" },
  ]
  const ranked = Model.rankPresets(history, 4)
  assert.strictEqual(ranked.length, 2)
})

test("rankPresets breaks ties by most recent use", () => {
  const history = [
    { mode: "minutes", duration: 10, label: "A" },
    { mode: "minutes", duration: 20, label: "B" },
  ]
  const ranked = Model.rankPresets(history, 4)
  assert.strictEqual(ranked[0].label, "B")
})

test("rankPresets ignores malformed entries and respects the limit", () => {
  const history = [
    null,
    { mode: "minutes", label: "no duration" },
    { mode: "minutes", duration: 1, label: "A" },
    { mode: "minutes", duration: 2, label: "B" },
    { mode: "minutes", duration: 3, label: "C" },
  ]
  const ranked = Model.rankPresets(history, 2)
  assert.strictEqual(ranked.length, 2)
})

test("rankPresets returns an empty list for non-array input", () => {
  assert.deepStrictEqual(Model.rankPresets(null, 4), [])
  assert.deepStrictEqual(Model.rankPresets(undefined, 4), [])
})
