// Plain-node tests for the pure logic in Model.js. Run with:
//   node --test test/model.test.js     (or: node test/model.test.js)
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

const EMPTY = {
  updatedAt: "",
  previewUrl: "",
  projectPath: "",
  lastRun: null,
  tests: null
};

test("parseIndex: tolerant of garbage", () => {
  assert.deepEqual(Model.parseIndex(""), EMPTY);
  assert.deepEqual(Model.parseIndex(null), EMPTY);
  assert.deepEqual(Model.parseIndex("{ bad"), EMPTY);
  assert.deepEqual(Model.parseIndex("[]"), EMPTY);
  assert.deepEqual(Model.parseIndex("42"), EMPTY);
});

test("parseIndex: empty object keeps defaults", () => {
  assert.deepEqual(Model.parseIndex({}), EMPTY);
});

test("parseIndex: maps a real-ish index", () => {
  const out = Model.parseIndex(
    JSON.stringify({
      updatedAt: "2026-09-05T10:00:00Z",
      previewUrl: "http://127.0.0.1:8731/preview.html",
      projectPath: "/home/u/Work/crochet-machine",
      lastRun: {
        pattern: "sample",
        ok: true,
        stitches: 70,
        rows: 12,
        finalRowWidth: 10,
        svgPath: "/tmp/sample.svg",
        stitchPath: "/tmp/sample-stitches.svg",
        at: "2026-09-05T09:59:00Z"
      },
      tests: { total: 30, passed: 30, failed: 0, ok: true, at: "2026-09-05T09:58:00Z" }
    })
  );
  assert.equal(out.updatedAt, "2026-09-05T10:00:00Z");
  assert.equal(out.previewUrl, "http://127.0.0.1:8731/preview.html");
  assert.equal(out.projectPath, "/home/u/Work/crochet-machine");
  assert.equal(out.lastRun.pattern, "sample");
  assert.equal(out.lastRun.ok, true);
  assert.equal(out.lastRun.stitches, 70);
  assert.equal(out.lastRun.rows, 12);
  assert.equal(out.lastRun.finalRowWidth, 10);
  assert.equal(out.lastRun.svgPath, "/tmp/sample.svg");
  assert.equal(out.lastRun.stitchPath, "/tmp/sample-stitches.svg");
  assert.equal(out.tests.total, 30);
  assert.equal(out.tests.passed, 30);
  assert.equal(out.tests.failed, 0);
  assert.equal(out.tests.ok, true);
});

test("parseIndex: failed run keeps error, nulls the numbers", () => {
  const out = Model.parseIndex(
    JSON.stringify({
      lastRun: { pattern: "broken", ok: false, error: "yarn over at row 3" }
    })
  );
  assert.equal(out.lastRun.ok, false);
  assert.equal(out.lastRun.error, "yarn over at row 3");
  assert.equal(out.lastRun.stitches, null);
  assert.equal(out.lastRun.rows, null);
  assert.equal(out.lastRun.finalRowWidth, null);
  assert.equal(out.lastRun.svgPath, null);
  assert.equal(out.lastRun.stitchPath, null);
  assert.equal(out.tests, null);
});

test("parseIndex: coerces numeric strings, ok is strict", () => {
  const out = Model.parseIndex(
    JSON.stringify({
      lastRun: { pattern: "p", ok: "true", stitches: "70", rows: "12" },
      tests: { total: "5", passed: "4", ok: 1 }
    })
  );
  assert.equal(out.lastRun.stitches, 70);
  assert.equal(out.lastRun.rows, 12);
  assert.equal(out.lastRun.ok, false);
  assert.equal(out.tests.total, 5);
  assert.equal(out.tests.ok, false);
});

test("parseIndex: missing lastRun/tests stay null, failed defaults to 0", () => {
  const out = Model.parseIndex(JSON.stringify({ updatedAt: "now" }));
  assert.equal(out.lastRun, null);
  assert.equal(out.tests, null);
  const t = Model.parseIndex(JSON.stringify({ tests: { total: 3, passed: 3 } }));
  assert.equal(t.tests.failed, 0);
  assert.equal(t.tests.ok, false);
});

test("parsePatternList: trims, drops blanks", () => {
  assert.deepEqual(Model.parsePatternList("a\n  b  \n\n\nc\n"), ["a", "b", "c"]);
});

test("parsePatternList: empty and garbage give []", () => {
  assert.deepEqual(Model.parsePatternList(""), []);
  assert.deepEqual(Model.parsePatternList(null), []);
  assert.deepEqual(Model.parsePatternList("   \n\n"), []);
});