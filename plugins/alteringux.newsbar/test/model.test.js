// Plain-node tests for the pure logic in Model.js. Run with:
//   node --test typing-trainer  (n/a) — here:  node test/model.test.js
// Model.js has no module system of its own (loaded as a QML JS import); it
// exposes a guarded module.exports purely for this harness.
const assert = require("assert");
const Model = require("../Model.js");

function test(name, fn) {
  try {
    fn();
    console.log("ok - " + name);
  } catch (e) {
    console.error("FAIL - " + name);
    console.error(e);
    process.exitCode = 1;
  }
}

// ---------------------------------------------------------------- parseState
test("parseState: empty / garbage input yields default state", () => {
  assert.deepStrictEqual(Model.parseState(""), Model.defaultState());
  assert.deepStrictEqual(Model.parseState("   "), Model.defaultState());
  const g = Model.parseState("{not json");
  assert.strictEqual(g.headlines.length, 0);
  assert.strictEqual(g.error, "state file unreadable");
});

test("parseState: keeps well-formed headlines, drops broken ones", () => {
  const raw = JSON.stringify({
    version: 1,
    updatedAt: "2026-01-01T00:00:00Z",
    error: null,
    headlines: [
      { source: "BBC", title: "Real one", url: "https://example.com/a" },
      { source: "X", title: "No url", url: "" },
      { source: "Y", title: "", url: "https://example.com/b" },
      { source: "Z", title: "Bad scheme", url: "ftp://example.com/c" },
      { title: "No source ok", url: "https://example.com/d" }
    ]
  });
  const s = Model.parseState(raw);
  assert.strictEqual(s.headlines.length, 2);
  assert.strictEqual(s.headlines[0].title, "Real one");
  assert.strictEqual(s.headlines[1].source, "News"); // default when blank
  assert.strictEqual(s.updatedAt, "2026-01-01T00:00:00Z");
});

test("parseState: non-array headlines field is tolerated", () => {
  const s = Model.parseState(JSON.stringify({ headlines: "nope" }));
  assert.strictEqual(s.headlines.length, 0);
});

// --------------------------------------------------------------- relativeAge
test("relativeAge: buckets", () => {
  const now = Date.parse("2026-01-02T00:00:00Z");
  assert.strictEqual(Model.relativeAge("2026-01-01T23:59:40Z", now), "just now");
  assert.strictEqual(Model.relativeAge("2026-01-01T23:30:00Z", now), "30m");
  assert.strictEqual(Model.relativeAge("2026-01-01T21:00:00Z", now), "3h");
  assert.strictEqual(Model.relativeAge("2025-12-30T00:00:00Z", now), "3d");
});

test("relativeAge: missing / unparseable / future -> empty string", () => {
  const now = Date.parse("2026-01-02T00:00:00Z");
  assert.strictEqual(Model.relativeAge("", now), "");
  assert.strictEqual(Model.relativeAge("not a date", now), "");
  assert.strictEqual(Model.relativeAge("2026-01-02T01:00:00Z", now), "");
});

// ---------------------------------------------------------------- signature
test("signature: stable for same urls, changes when a url changes", () => {
  const a = [{ url: "https://x/1" }, { url: "https://x/2" }];
  const b = [{ url: "https://x/1" }, { url: "https://x/2" }];
  const c = [{ url: "https://x/1" }, { url: "https://x/3" }];
  assert.strictEqual(Model.signature(a), Model.signature(b));
  assert.notStrictEqual(Model.signature(a), Model.signature(c));
  assert.strictEqual(Model.signature([]), "");
});

// -------------------------------------------------------------- withAges / label
test("withAges + headlineLabel", () => {
  const now = Date.parse("2026-01-01T03:00:00Z");
  const [h] = Model.withAges(
    [{ source: "BBC", title: "Thing happened", url: "https://x/1", published: "2026-01-01T00:00:00Z" }],
    now
  );
  assert.strictEqual(h.age, "3h");
  assert.strictEqual(Model.headlineLabel(h), "BBC   Thing happened  · 3h");
  const [h2] = Model.withAges(
    [{ source: "AP", title: "Undated", url: "https://x/2", published: "" }],
    now
  );
  assert.strictEqual(Model.headlineLabel(h2), "AP   Undated");
});

// -------------------------------------------------------------- readingMinutes
test("readingMinutes: threaded through, drives readTime + label", () => {
  const now = Date.parse("2026-01-01T03:00:00Z");
  const [h] = Model.withAges(
    [{ source: "Lit", title: "A long one", url: "https://x/1",
       published: "2026-01-01T00:00:00Z", readingMinutes: 17 }],
    now
  );
  assert.strictEqual(h.readingMinutes, 17);
  assert.strictEqual(h.readTime, "17 min read");
  assert.strictEqual(Model.headlineLabel(h), "Lit   A long one  · 3h  · 17 min read");
});

test("formatReadTime: minutes, then hours past 60", () => {
  assert.strictEqual(Model.formatReadTime(0), "");
  assert.strictEqual(Model.formatReadTime(-3), "");
  assert.strictEqual(Model.formatReadTime(1), "1 min read");
  assert.strictEqual(Model.formatReadTime(59), "59 min read");
  assert.strictEqual(Model.formatReadTime(60), "1h read");
  assert.strictEqual(Model.formatReadTime(125), "2h 5m read");
  assert.strictEqual(Model.formatReadTime(358), "5h 58m read");
});

test("readingMinutes: absent / zero / junk -> 0 and no readTime", () => {
  assert.strictEqual(Model.sanitizeHeadline({ title: "T", url: "https://x/1" }).readingMinutes, 0);
  assert.strictEqual(
    Model.sanitizeHeadline({ title: "T", url: "https://x/2", readingMinutes: "abc" }).readingMinutes, 0);
  assert.strictEqual(
    Model.sanitizeHeadline({ title: "T", url: "https://x/3", readingMinutes: -4 }).readingMinutes, 0);
  const [h] = Model.withAges(
    [{ source: "BBC", title: "News", url: "https://x/4", published: "" }], Date.now());
  assert.strictEqual(h.readTime, "");
  assert.strictEqual(Model.headlineLabel(h), "BBC   News");
});

// --------------------------------------------------------- category / sector
test("sanitizeHeadline: keeps and caps category", () => {
  const h = Model.sanitizeHeadline({
    title: "T", url: "https://x/1",
    category: "  Business and finance news reporting extra  "
  });
  assert.strictEqual(h.category.length, 24);
});

test("normalizeCategory: buckets known sectors, 'other' for the rest, '' for blank", () => {
  assert.strictEqual(Model.normalizeCategory("World"), "world");
  assert.strictEqual(Model.normalizeCategory("Middle East"), "world");
  assert.strictEqual(Model.normalizeCategory("Business"), "business");
  assert.strictEqual(Model.normalizeCategory("Tech"), "tech");
  assert.strictEqual(Model.normalizeCategory("Sport"), "sport");
  assert.strictEqual(Model.normalizeCategory("Gardening"), "other");
  assert.strictEqual(Model.normalizeCategory(""), "");
  assert.strictEqual(Model.normalizeCategory(null), "");
});

test("withAges: threads category + bucket + summary through", () => {
  const [h] = Model.withAges(
    [{ source: "BBC", title: "x", url: "https://x/1", published: "",
       category: "Politics", summary: "A short standfirst." }],
    Date.now()
  );
  assert.strictEqual(h.category, "Politics");
  assert.strictEqual(h.categoryBucket, "politics");
  assert.strictEqual(h.summary, "A short standfirst.");
});

test("sanitizeHeadline: summary trimmed and capped at 320", () => {
  const h = Model.sanitizeHeadline({
    title: "T", url: "https://x/1", summary: "  " + "z".repeat(400) + "  "
  });
  assert.strictEqual(h.summary.length, 320);
  const none = Model.sanitizeHeadline({ title: "T", url: "https://x/2" });
  assert.strictEqual(none.summary, "");
});

if (process.exitCode) {
  console.error("\nsome tests failed");
} else {
  console.log("\nall tests passed");
}
