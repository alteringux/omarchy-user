// Plain-node tests for the pure logic in Str.js. Run with:
//   node test/str.test.js
// Str.js has no `.pragma library` so this harness can require() it; the
// guarded module.exports at its foot exists for exactly this.
const assert = require("assert")
const Str = require("../Str.js")

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

test("escapeHtml: entity-encodes the four rich-text metacharacters", () => {
  assert.equal(Str.escapeHtml('A & B <c> "d"'), "A &amp; B &lt;c&gt; &quot;d&quot;")
})

test("escapeHtml: leaves safe text untouched", () => {
  assert.equal(Str.escapeHtml("Dating and Social — plain (BBC)"), "Dating and Social — plain (BBC)")
})

test("escapeHtml: null / undefined / number -> string", () => {
  assert.equal(Str.escapeHtml(null), "")
  assert.equal(Str.escapeHtml(undefined), "")
  assert.equal(Str.escapeHtml(42), "42")
})

test("escapeHtml: order is safe (no double-encoding of & from < >)", () => {
  assert.equal(Str.escapeHtml("<a href=\"x&y\">"), "&lt;a href=&quot;x&amp;y&quot;&gt;")
})
