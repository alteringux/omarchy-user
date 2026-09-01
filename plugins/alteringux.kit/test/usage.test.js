// Plain-node tests for the pure logic in UsageModel.js. Run with:
//   node test/usage.test.js
// UsageModel.js has no module system of its own (it's a QML JS import);
// the guarded module.exports at its foot exists purely for this harness.
const assert = require("assert")
const U = require("../UsageModel.js")

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

const DAY = U.DAY_MS
const T0 = 1_700_000_000_000 // fixed "now" for deterministic decay math

test("defaultDoc is empty", () => {
  assert.deepStrictEqual(U.defaultDoc(), { actions: {}, firstAt: 0 })
})

test("parse tolerates empty / garbage / partial input", () => {
  assert.deepStrictEqual(U.parse(""), U.defaultDoc())
  assert.deepStrictEqual(U.parse("not json"), U.defaultDoc())
  assert.deepStrictEqual(U.parse("{}"), U.defaultDoc())
  const messy = JSON.stringify({
    firstAt: -5,
    actions: {
      good: { count: 3, lastAt: T0, recent: [T0, "x", -1, T0 - DAY] },
      bad:  "nope",
      neg:  { count: -2, lastAt: 0, recent: null }
    }
  })
  const d = U.parse(messy)
  assert.strictEqual(d.firstAt, 0)                 // negative dropped
  assert.strictEqual(d.actions.good.count, 3)
  assert.deepStrictEqual(d.actions.good.recent, [T0, T0 - DAY]) // junk filtered
  assert.strictEqual(d.actions.neg.count, 0)       // negative count floored
  assert.deepStrictEqual(d.actions.neg.recent, [])
})

test("record folds in a use without mutating the input", () => {
  const before = U.defaultDoc()
  const after = U.record(before, "add", T0)
  assert.deepStrictEqual(before, U.defaultDoc(), "input untouched")
  assert.strictEqual(after.actions.add.count, 1)
  assert.strictEqual(after.actions.add.lastAt, T0)
  assert.deepStrictEqual(after.actions.add.recent, [T0])
  assert.strictEqual(after.firstAt, T0)
})

test("record ignores a blank action name", () => {
  const d = U.record(U.defaultDoc(), "   ", T0)
  assert.deepStrictEqual(d.actions, {})
})

test("record caps the recency ring at RECENT_CAP", () => {
  let d = U.defaultDoc()
  for (let i = 0; i < U.RECENT_CAP + 15; i++) d = U.record(d, "tick", T0 + i)
  assert.strictEqual(d.actions.tick.recent.length, U.RECENT_CAP)
  assert.strictEqual(d.actions.tick.count, U.RECENT_CAP + 15) // count is lifetime
  assert.strictEqual(d.actions.tick.recent[U.RECENT_CAP - 1], T0 + U.RECENT_CAP + 14)
})

test("score decays by half every HALF_LIFE_DAYS", () => {
  const fresh = U.record(U.defaultDoc(), "a", T0)
  const old   = U.record(U.defaultDoc(), "a", T0 - U.HALF_LIFE_DAYS * DAY)
  const sFresh = U.score(fresh, "a", T0)
  const sOld   = U.score(old, "a", T0)
  // fresh ≈ 1 + log(2)*0.25 ; old ≈ 0.5 + log(2)*0.25
  assert.ok(Math.abs((sFresh - sOld) - 0.5) < 1e-9, `${sFresh} vs ${sOld}`)
})

test("score is 0 for an unknown action", () => {
  assert.strictEqual(U.score(U.defaultDoc(), "ghost", T0), 0)
})

test("rank orders by descending blended score; subset restricts + orders", () => {
  let d = U.defaultDoc()
  d = U.record(d, "rare", T0 - 30 * DAY)
  for (let i = 0; i < 5; i++) d = U.record(d, "often", T0 - i * DAY)
  d = U.record(d, "recent", T0)
  assert.deepStrictEqual(U.rank(d, null, T0).slice(0, 2), ["often", "recent"])
  // subset keeps only asked-for names, still score-ordered, unknowns last
  assert.deepStrictEqual(
    U.rank(d, ["rare", "often", "never"], T0),
    ["often", "rare", "never"]
  )
})

test("top(n) slices the ranking", () => {
  let d = U.defaultDoc()
  d = U.record(d, "a", T0); d = U.record(d, "b", T0 - DAY); d = U.record(d, "c", T0 - 2 * DAY)
  assert.deepStrictEqual(U.top(d, 2, T0), ["a", "b"])
  assert.deepStrictEqual(U.top(d, 0, T0), [])
})

test("isDead: never-used and idle+rare are dead; recent or heavily-used are not", () => {
  assert.strictEqual(U.isDead(U.defaultDoc(), "never", T0), true)

  const idleRare = U.record(U.defaultDoc(), "x", T0 - (U.DEAD_AFTER_DAYS + 1) * DAY)
  assert.strictEqual(U.isDead(idleRare, "x", T0), true)

  let idleButUsed = U.defaultDoc()
  for (let i = 0; i < U.DEAD_UNDER_COUNT; i++) {
    idleButUsed = U.record(idleButUsed, "y", T0 - (U.DEAD_AFTER_DAYS + 5) * DAY - i)
  }
  assert.strictEqual(U.isDead(idleButUsed, "y", T0), false, "count >= threshold keeps it alive")

  const recent = U.record(U.defaultDoc(), "z", T0 - 2 * DAY)
  assert.strictEqual(U.isDead(recent, "z", T0), false)
})
