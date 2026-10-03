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

// ── parseWifiState / isWifiActive ───────────────────────────────────────
test("parseWifiState: empty / junk input -> unknown", () => {
  assert.strictEqual(Model.parseWifiState(""), "unknown");
  assert.strictEqual(Model.parseWifiState(null), "unknown");
});

test("parseWifiState: lone wifi:connected -> connected", () => {
  assert.strictEqual(Model.parseWifiState("wifi:connected"), "connected");
});

test("parseWifiState: lone wifi:disconnected -> disconnected", () => {
  assert.strictEqual(Model.parseWifiState("wifi:disconnected\nwifi-p2p:disconnected"), "disconnected");
});

test("parseWifiState: connected wins over a weaker wifi row", () => {
  assert.strictEqual(Model.parseWifiState("wifi:connected\nwifi:unavailable"), "connected");
});

test("parseWifiState: wifi-p2p rows are ignored (different TYPE)", () => {
  assert.strictEqual(Model.parseWifiState("wifi-p2p:disconnected"), "unknown");
  assert.strictEqual(Model.parseWifiState("wifi:connected\nwifi-p2p:disconnected"), "connected");
});

test("parseWifiState: an unrecognised state string -> unavailable", () => {
  assert.strictEqual(Model.parseWifiState("wifi:somethingweird"), "unavailable");
});

test("parseWifiState: no wifi row among other device types -> unknown", () => {
  assert.strictEqual(Model.parseWifiState("ethernet:connected\nloopback:connected"), "unknown");
});

test("isWifiActive: true only for connected, in string or object form", () => {
  assert.strictEqual(Model.isWifiActive("connected"), true);
  assert.strictEqual(Model.isWifiActive("disconnected"), false);
  assert.strictEqual(Model.isWifiActive("unknown"), false);
  assert.strictEqual(Model.isWifiActive({ wifiState: "connected" }), true);
  assert.strictEqual(Model.isWifiActive({ wifiState: "unavailable" }), false);
  assert.strictEqual(Model.isWifiActive(null), false);
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

test("prettyInterval: preset seconds use the preset label", () => {
  assert.strictEqual(Model.prettyInterval(600), "10m");
  assert.strictEqual(Model.prettyInterval(60), "1m");
});

test("prettyInterval: an exact-minute non-preset value renders 'Nm', not 'Nmm'", () => {
  assert.strictEqual(Model.prettyInterval(120), "2m");
  assert.strictEqual(Model.prettyInterval(180), "3m");
});

test("prettyInterval: a non-exact-minute non-preset value falls back to formatCountdown", () => {
  assert.strictEqual(Model.prettyInterval(90), "1m 30s");
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

// ── metrics ─────────────────────────────────────────────────────────────
test("parseMetrics returns a safe empty shape for junk", () => {
  const m = Model.parseMetrics("not json");
  assert.strictEqual(m.load, 0);
  assert.strictEqual(m.protocol, "");
  assert.strictEqual(m.rotations, 0);
});

test("parseMetrics reads a well-formed blob and coerces types", () => {
  const m = Model.parseMetrics(JSON.stringify({
    load: 83, protocol: "wireguard", latencyMs: 42, rxBytes: 2048, txBytes: 1024,
    bytesAt: 100, rotations: 5, rotationsToday: 3, distinctIps: 9,
    ipChangedCount: 7, failures: 1
  }));
  assert.strictEqual(m.load, 83);
  assert.strictEqual(m.protocol, "wireguard");
  assert.strictEqual(m.rxBytes, 2048);
  assert.strictEqual(m.rotations, 5);
  assert.strictEqual(m.failures, 1);
});

test("formatBytes scales and labels binary units", () => {
  assert.strictEqual(Model.formatBytes(512), "512 B");
  assert.strictEqual(Model.formatBytes(1536), "1.5 KB");
  assert.strictEqual(Model.formatBytes(5 * 1024 * 1024), "5.0 MB");
  assert.strictEqual(Model.formatBytes(3 * 1024 * 1024 * 1024), "3.0 GB");
  assert.strictEqual(Model.formatBytes(-10), "0 B");
});

test("formatRate appends /s, floors at 0 B/s", () => {
  assert.strictEqual(Model.formatRate(0), "0 B/s");
  assert.strictEqual(Model.formatRate(2048), "2.0 KB/s");
  assert.strictEqual(Model.formatRate(-5), "0 B/s");
});

test("formatLatency renders ms or an em-dash when unmeasured", () => {
  assert.strictEqual(Model.formatLatency(42), "42 ms");
  assert.strictEqual(Model.formatLatency(0), "—");
  assert.strictEqual(Model.formatLatency(-1), "—");
});

test("throughput divides the byte delta by the time delta, guarding a counter reset", () => {
  assert.strictEqual(Model.throughput(3000, 110, 1000, 100), 200);   // 2000 B / 10 s
  assert.strictEqual(Model.throughput(500, 110, 1000, 100), 0);       // counter went backwards (reconnect)
  assert.strictEqual(Model.throughput(3000, 100, 1000, 100), 0);      // no time elapsed
});

test("rotationSummary omits zero clauses but always keeps the count", () => {
  assert.strictEqual(Model.rotationSummary({ rotations: 1, ipChangedCount: 0, distinctIps: 0, failures: 0 }), "1 rotation");
  assert.strictEqual(
    Model.rotationSummary({ rotations: 5, ipChangedCount: 4, distinctIps: 9, failures: 1 }),
    "5 rotations  ·  4 changed IP  ·  9 IPs seen  ·  1 failed"
  );
  assert.strictEqual(Model.rotationSummary({ rotationsToday: 3, ipChangedCount: 0, distinctIps: 0, failures: 0 }, true), "3 today");
});
