// Focused node tests for the notification boundary logic. Run with:
//   node test/model.test.js
const assert = require("assert")
const Logic = require("../NotificationLogic.js")

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

test("sanitizeBody removes complete image tags but preserves safe markup and text", () => {
  const body = "<b>Bold</b> <a href=\"https://example.test\">link</a> <img src=\"https://evil.test/pixel.png\"> tail"
  const clean = Logic.sanitizeBody(body, "Chat", "")
  assert.ok(clean.includes("<b>Bold</b>"))
  assert.ok(clean.includes("<a href=\"https://example.test\">link</a>"))
  assert.ok(clean.includes("tail"))
  assert.doesNotMatch(clean, /<img\b/i)
})

test("sanitizeBody neutralizes an unterminated image opener without hiding following text", () => {
  const clean = Logic.sanitizeBody("before <img src=\"https://evil.test/pixel.png\" after", "Chat", "")
  const malformed = Logic.sanitizeBody("before <\nimg src=\"https://evil.test/linebreak.png\"", "Chat", "")
  assert.doesNotMatch(malformed, /<img\b/i)
  assert.ok(malformed.includes("https://evil.test/linebreak.png"))
  assert.ok(malformed.includes("&lt;img"))
  assert.doesNotMatch(clean, /<img\b/i)
  assert.ok(clean.includes("&lt;img"))
})

test("empty-history replay placeholders are deduplicated", () => {
  const placeholder = {
    originalId: -1,
    app: "omarchy-action",
    summary: "No recent notifications"
  }
  const rows = Logic.dedupeHistoryPlaceholders([
    placeholder,
    { originalId: 7, app: "Chat", summary: "hello" },
    Object.assign({}, placeholder)
  ])
  assert.strictEqual(rows.length, 2)
  assert.strictEqual(rows.filter(Logic.isHistoryPlaceholder).length, 1)
  assert.strictEqual(rows[1].summary, "hello")
})
