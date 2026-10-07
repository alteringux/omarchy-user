// Plain-node tests for the pure logic in ReminderFlowModel.js. Run with:
//   node test/model.test.js
// ReminderFlowModel.js has no module system of its own (it's loaded as a
// QML JS import), so it exposes a guarded `module.exports` at the bottom
// purely for this test harness; that export is a no-op inside QML.
const assert = require("assert")
const Model = require("../ReminderFlowModel.js")

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

test("validMinutes accepts positive integers", () => {
  assert.strictEqual(Model.validMinutes("5"), "5")
  assert.strictEqual(Model.validMinutes("  42 "), "42")
  assert.strictEqual(Model.validMinutes(90), "90")
})

test("validMinutes rejects zero, negatives, non-numbers, empty", () => {
  assert.strictEqual(Model.validMinutes("0"), "")
  assert.strictEqual(Model.validMinutes("-5"), "")
  assert.strictEqual(Model.validMinutes("2.5"), "")
  assert.strictEqual(Model.validMinutes("abc"), "")
  assert.strictEqual(Model.validMinutes(""), "")
  assert.strictEqual(Model.validMinutes(null), "")
  assert.strictEqual(Model.validMinutes(undefined), "")
})

test("reminderArgs builds [minutes] or [minutes, message]", () => {
  assert.deepStrictEqual(Model.reminderArgs("5"), ["5"])
  assert.deepStrictEqual(Model.reminderArgs(" 5 ", "water plants"), ["5", "water plants"])
  assert.deepStrictEqual(Model.reminderArgs("5", "x"), ["5", "x"])
  assert.deepStrictEqual(Model.reminderArgs("0", "x"), [])
  assert.deepStrictEqual(Model.reminderArgs("", "x"), [])
})

test("repeatReminderArgs builds [--every, minutes] or [--every, minutes, message]", () => {
  assert.deepStrictEqual(Model.repeatReminderArgs("10"), ["--every", "10"])
  assert.deepStrictEqual(Model.repeatReminderArgs("10", "stretch"), ["--every", "10", "stretch"])
  assert.deepStrictEqual(Model.repeatReminderArgs("10", "x"), ["--every", "10", "x"])
  assert.deepStrictEqual(Model.repeatReminderArgs("0", "x"), [])
  assert.deepStrictEqual(Model.repeatReminderArgs("", "x"), [])
})