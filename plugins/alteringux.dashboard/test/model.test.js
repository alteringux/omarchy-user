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

test("defaultState has every section a panel binding reads", () => {
  const s = Model.defaultState()
  assert.deepStrictEqual(s.notes.items, [])
  assert.strictEqual(s.news.updatedAt, null)
  assert.deepStrictEqual(s.news.items, [])
  assert.deepStrictEqual(s.system.items, [])
  assert.deepStrictEqual(s.engagement.news, {})
  assert.strictEqual(s.digest.text, "")
})

test("parseState returns defaults for empty input", () => {
  assert.deepStrictEqual(Model.parseState(""), Model.defaultState())
})

test("parseState returns defaults for malformed JSON instead of throwing", () => {
  assert.deepStrictEqual(Model.parseState("{not json"), Model.defaultState())
})

test("parseState pulls through well-formed sections", () => {
  const raw = JSON.stringify({
    notes: { items: [{ text: "buy milk" }] },
    news: { updatedAt: "2026-01-01T00:00:00Z", items: [{ title: "x" }] },
    digest: { text: "all quiet", updatedAt: "2026-01-01T00:00:00Z" }
  })
  const s = Model.parseState(raw)
  assert.strictEqual(s.notes.items.length, 1)
  assert.strictEqual(s.news.items[0].title, "x")
  assert.strictEqual(s.digest.text, "all quiet")
})

test("parseState ignores a section whose items field is not an array", () => {
  const s = Model.parseState(JSON.stringify({ news: { items: "nope", updatedAt: "t" } }))
  assert.deepStrictEqual(s.news.items, [])
  assert.strictEqual(s.news.updatedAt, "t")
})

test("parseState rejects a non-object engagement.news", () => {
  const s = Model.parseState(JSON.stringify({ engagement: { news: [1, 2] } }))
  assert.deepStrictEqual(s.engagement.news, {})
})

test("formatRelative returns an empty string for missing or unparseable input", () => {
  assert.strictEqual(Model.formatRelative(null), "")
  assert.strictEqual(Model.formatRelative("not a date"), "")
})

test("formatRelative says 'just now' under a minute", () => {
  assert.strictEqual(Model.formatRelative(new Date().toISOString()), "just now")
})

test("formatRelative buckets minutes, hours, and days", () => {
  const ago = (ms) => new Date(Date.now() - ms).toISOString()
  assert.strictEqual(Model.formatRelative(ago(5 * 60000)), "5m ago")
  assert.strictEqual(Model.formatRelative(ago(3 * 3600000)), "3h ago")
  assert.strictEqual(Model.formatRelative(ago(2 * 86400000)), "2d ago")
})

test("formatRelative clamps a future timestamp to 'just now'", () => {
  assert.strictEqual(Model.formatRelative(new Date(Date.now() + 60000).toISOString()), "just now")
})
