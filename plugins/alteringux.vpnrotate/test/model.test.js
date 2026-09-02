// Plain-node tests for the pure logic in Model.js. Run with:
//   node test/model.test.js
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

// ── parseState ────────────────────────────────────────────────────────────
test("parseState returns a safe empty shape for junk", () => {
  const s = Model.parseState("not json");
  assert.strictEqual(s.connected, false);
  assert.strictEqual(s.action, "idle");
  assert.strictEqual(s.exitIp, "");
});

test("parseState reads a well-formed status blob and upcases country", () => {
  const raw = JSON.stringify({
    connected: true, action: "idle", server: "NL#12", exitIp: "5.6.7.8",
    country: "nl", city: "Amsterdam", org: "Proton", since: 100, lastRotate: 150
  });
  const s = Model.parseState(raw);
  assert.strictEqual(s.connected, true);
  assert.strictEqual(s.country, "NL");
  assert.strictEqual(s.server, "NL#12");
  assert.strictEqual(s.lastRotate, 150);
});

test("parseState coerces connected:'true' string to false (strict bool)", () => {
  assert.strictEqual(Model.parseState(JSON.stringify({ connected: "true" })).connected, false);
});

// ── parseConfig / clampInterval ──────────────────────────────────────────
test("parseConfig defaults when empty", () => {
  assert.deepStrictEqual(Model.parseConfig(""), { autoRotate: false, intervalSec: 600, killSwitch: false });
});

test("clampInterval enforces the 60s floor and 6h ceiling", () => {
  assert.strictEqual(Model.clampInterval(5), 60);
  assert.strictEqual(Model.clampInterval(999999), 21600);
  assert.strictEqual(Model.clampInterval(300), 300);
  assert.strictEqual(Model.clampInterval("abc"), 600);
});

// ── countdown ────────────────────────────────────────────────────────────
test("secondsUntilNextRotation is null when auto-rotate is off", () => {
  const st = Model.parseState(JSON.stringify({ connected: true, since: 0, lastRotate: 1000 }));
  assert.strictEqual(Model.secondsUntilNextRotation(st, { autoRotate: false, intervalSec: 600 }, 1200), null);
});

test("secondsUntilNextRotation counts down from lastRotate + interval", () => {
  const st = Model.parseState(JSON.stringify({ connected: true, since: 500, lastRotate: 1000 }));
  assert.strictEqual(Model.secondsUntilNextRotation(st, { autoRotate: true, intervalSec: 600 }, 1300), 300);
});

test("secondsUntilNextRotation never goes negative", () => {
  const st = Model.parseState(JSON.stringify({ connected: true, since: 500, lastRotate: 1000 }));
  assert.strictEqual(Model.secondsUntilNextRotation(st, { autoRotate: true, intervalSec: 600 }, 9999), 0);
});

test("secondsUntilNextRotation is null while disconnected", () => {
  const st = Model.parseState(JSON.stringify({ connected: false }));
  assert.strictEqual(Model.secondsUntilNextRotation(st, { autoRotate: true, intervalSec: 600 }, 10), null);
});

test("formatCountdown renders m + zero-padded s", () => {
  assert.strictEqual(Model.formatCountdown(65), "1m 05s");
  assert.strictEqual(Model.formatCountdown(9), "9s");
  assert.strictEqual(Model.formatCountdown(0), "0s");
});

// ── shortAgo ─────────────────────────────────────────────────────────────
test("shortAgo buckets by magnitude", () => {
  assert.strictEqual(Model.shortAgo(0, 100), "");
  assert.strictEqual(Model.shortAgo(1000, 1002), "just now");
  assert.strictEqual(Model.shortAgo(1000, 1030), "30s ago");
  assert.strictEqual(Model.shortAgo(1000, 1000 + 180), "3m ago");
  assert.strictEqual(Model.shortAgo(1000, 1000 + 7200), "2h ago");
});

// ── presentation helpers ─────────────────────────────────────────────────
test("barLabel shows country only when idle+connected", () => {
  assert.strictEqual(Model.barLabel(Model.parseState(JSON.stringify({ connected: true, country: "jp", action: "idle" }))), "JP");
  assert.strictEqual(Model.barLabel(Model.parseState(JSON.stringify({ connected: true, country: "jp", action: "rotating" }))), "");
  assert.strictEqual(Model.barLabel(Model.parseState("{}")), "");
});

test("iconFor swaps to the refresh glyph mid-action and warning on error", () => {
  assert.strictEqual(Model.iconFor({ action: "rotating" }), "");
  assert.strictEqual(Model.iconFor({ action: "idle", error: "boom" }), "");
  assert.strictEqual(Model.iconFor({ action: "idle", connected: true }), "");
});

test("summaryLine describes each state", () => {
  assert.strictEqual(Model.summaryLine(null), "Not connected");
  assert.strictEqual(Model.summaryLine({ action: "connecting" }), "Connecting…");
  assert.ok(Model.summaryLine({ action: "idle", connected: true, city: "Oslo", country: "NO", exitIp: "1.1.1.1" }).indexOf("Oslo, NO") !== -1);
});
