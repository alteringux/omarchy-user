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

test("formatElapsed pads minutes and seconds under an hour", () => {
  assert.strictEqual(Model.formatElapsed(65), "01:05")
})

test("formatElapsed includes hours once elapsed crosses an hour", () => {
  assert.strictEqual(Model.formatElapsed(3661), "1:01:01")
})

test("formatElapsed floors fractional seconds instead of rounding up", () => {
  assert.strictEqual(Model.formatElapsed(59.9), "00:59")
})

test("parseState rejects empty input", () => {
  assert.strictEqual(Model.parseState(""), null)
})

test("parseState rejects input without a numeric start_epoch", () => {
  assert.strictEqual(Model.parseState(JSON.stringify({ label: "x" })), null)
})

test("parseState accepts a well-formed state blob", () => {
  const state = Model.parseState(JSON.stringify({ start_epoch: 100, interval_minutes: 5, label: "Focus" }))
  assert.strictEqual(state.start_epoch, 100)
  assert.strictEqual(state.interval_minutes, 5)
  assert.strictEqual(state.label, "Focus")
})

test("parseHistory returns an empty session list for empty/invalid input", () => {
  assert.deepStrictEqual(Model.parseHistory(""), { version: 1, sessions: [] })
  assert.deepStrictEqual(Model.parseHistory("not json"), { version: 1, sessions: [] })
  assert.deepStrictEqual(Model.parseHistory(JSON.stringify({ foo: "bar" })), { version: 1, sessions: [] })
})

test("parseHistory accepts a well-formed history blob", () => {
  const raw = JSON.stringify({ version: 1, sessions: [{ label: "Focus", elapsed_seconds: 60 }] })
  const history = Model.parseHistory(raw)
  assert.strictEqual(history.sessions.length, 1)
  assert.strictEqual(history.sessions[0].label, "Focus")
})

test("historyAverage returns null when no session shares the label", () => {
  const history = { sessions: [{ label: "Focus", elapsed_seconds: 100 }] }
  assert.strictEqual(Model.historyAverage(history, "Other"), null)
  assert.strictEqual(Model.historyAverage({ sessions: [] }, ""), null)
})

test("historyAverage averages only sessions matching the label, treating unlabeled as its own bucket", () => {
  const history = {
    sessions: [
      { label: "Focus", elapsed_seconds: 100 },
      { label: "Focus", elapsed_seconds: 200 },
      { label: "", elapsed_seconds: 900 },
      { elapsed_seconds: 300 }
    ]
  }
  assert.strictEqual(Model.historyAverage(history, "Focus"), 150)
  assert.strictEqual(Model.historyAverage(history, ""), 600)
})

test("formatDelta describes a shorter-than-average session", () => {
  assert.strictEqual(Model.formatDelta(90, 100), "10% shorter than your average")
})

test("formatDelta describes a longer-than-average session", () => {
  assert.strictEqual(Model.formatDelta(150, 100), "50% longer than your average")
})

test("formatDelta reports a match when rounding collapses the difference to 0%", () => {
  assert.strictEqual(Model.formatDelta(100, 100), "right on your average")
})

test("formatDelta returns empty string when there's no average to compare against", () => {
  assert.strictEqual(Model.formatDelta(100, null), "")
  assert.strictEqual(Model.formatDelta(100, 0), "")
})
