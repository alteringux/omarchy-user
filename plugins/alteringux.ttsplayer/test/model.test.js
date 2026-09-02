// Hand-rolled test harness (run: `node test/model.test.js`), matching the
// other alteringux.* plugins — not `node --test`.
const M = require("../Model.js");

let pass = 0, fail = 0;
function test(name, fn) {
  try { fn(); pass++; console.log("  ok  " + name); }
  catch (e) { fail++; console.log("FAIL  " + name + "\n      " + e.message); }
}
function eq(a, b, msg) {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A !== B) throw new Error((msg || "") + " expected " + B + " got " + A);
}
function ok(v, msg) { if (!v) throw new Error(msg || "expected truthy"); }

// ── parseState ──────────────────────────────────────────────────────────
test("parseState: null for empty / garbage", () => {
  eq(M.parseState(""), null);
  eq(M.parseState("not json"), null);
  eq(M.parseState("{}"), null);
  eq(M.parseState(JSON.stringify({ pgid: 0 })), null);
});

test("parseState: full record", () => {
  const s = M.parseState(JSON.stringify({
    tag: "narrate", voice: "en_GB-cori-high", length_scale: "",
    pgid: 1234, started_at: 100, chunks: 5, chars: 700, text: "hello there"
  }));
  eq(s.tag, "narrate");
  eq(s.pgid, 1234);
  eq(s.startedAt, 100);
  eq(s.chunks, 5);
  eq(s.chars, 700);
  eq(s.text, "hello there");
});

test("parseState: missing fields fall back sanely", () => {
  const s = M.parseState(JSON.stringify({ pgid: 9 }));
  eq(s.tag, "default");
  eq(s.voice, "");
  eq(s.chunks, 1);
  eq(s.chars, 0);
  eq(s.text, "");
});

// ── parseStatus ─────────────────────────────────────────────────────────
test("parseStatus: inactive shapes", () => {
  eq(M.parseStatus("").active, false);
  eq(M.parseStatus('{"active":false}').active, false);
  eq(M.parseStatus("broken").active, false);
});

test("parseStatus: active record", () => {
  const s = M.parseStatus(JSON.stringify({
    active: true, paused: true, muted: false, played: 2, elapsed: 17, chunks: 4
  }));
  eq(s.active, true);
  eq(s.paused, true);
  eq(s.muted, false);
  eq(s.played, 2);
  eq(s.elapsed, 17);
  eq(s.chunks, 4);
});

// ── formatElapsed ───────────────────────────────────────────────────────
test("formatElapsed", () => {
  eq(M.formatElapsed(0), "0:00");
  eq(M.formatElapsed(9), "0:09");
  eq(M.formatElapsed(65), "1:05");
  eq(M.formatElapsed(600), "10:00");
  eq(M.formatElapsed(-5), "0:00");
});

// ── progressFraction ────────────────────────────────────────────────────
test("progressFraction: multi-chunk uses the chunk cursor", () => {
  eq(M.progressFraction({ chunks: 4, played: 0 }), 1 / 5);
  eq(M.progressFraction({ chunks: 4, played: 3 }), 4 / 5);
});

test("progressFraction: single chunk uses a time estimate", () => {
  // 140 chars / 14 cps = 10 s estimate; 5 s elapsed -> 0.5
  eq(M.progressFraction({ chunks: 1, played: 0, elapsed: 5, chars: 140 }), 0.5);
});

test("progressFraction: never reaches 1 while playing, never negative", () => {
  ok(M.progressFraction({ chunks: 1, elapsed: 9999, chars: 10 }) <= 0.98);
  ok(M.progressFraction({ chunks: 2, played: 50 }) <= 0.98);
  ok(M.progressFraction({}) >= 0);
  ok(M.progressFraction({ chunks: 1, elapsed: -3, chars: 100 }) >= 0);
});

// ── chunkLabel ──────────────────────────────────────────────────────────
test("chunkLabel", () => {
  eq(M.chunkLabel({ chunks: 1, played: 0 }), "");
  eq(M.chunkLabel({ chunks: 5, played: 0 }), "chunk 1/5");
  eq(M.chunkLabel({ chunks: 5, played: 4 }), "chunk 5/5");
  eq(M.chunkLabel({ chunks: 5, played: 99 }), "chunk 5/5");
});

// ── speedToLengthScale ──────────────────────────────────────────────────
test("speedToLengthScale", () => {
  eq(M.speedToLengthScale(1), "");
  eq(M.speedToLengthScale(0), "");
  eq(M.speedToLengthScale(2), "0.5");
  eq(M.speedToLengthScale(1.25), "0.8");
  eq(M.speedToLengthScale(1.5), "0.667");
});

// ── replayCommand ───────────────────────────────────────────────────────
test("replayCommand: 1x omits --length-scale", () => {
  const c = M.replayCommand("/p/piper-tts",
    { tag: "narrate", voice: "en_GB-cori-high", text: "hi" }, 1);
  eq(c, ["/p/piper-tts", "--tag", "narrate", "--voice", "en_GB-cori-high", "--", "hi"]);
});

test("replayCommand: faster speed adds --length-scale", () => {
  const c = M.replayCommand("/p/piper-tts",
    { tag: "t", voice: "", text: "yo" }, 1.5);
  eq(c, ["/p/piper-tts", "--tag", "t", "--length-scale", "0.667", "--", "yo"]);
});

test("replayCommand: voice override beats the captured voice", () => {
  const c = M.replayCommand("/p/piper-tts",
    { tag: "narrate", voice: "en_GB-cori-high", text: "hi" }, 1, "en_US-amy-medium");
  eq(c, ["/p/piper-tts", "--tag", "narrate", "--voice", "en_US-amy-medium", "--", "hi"]);
});

test("replayCommand: empty / non-string override falls back to captured voice", () => {
  const base = { tag: "t", voice: "en_GB-cori-high", text: "yo" };
  eq(M.replayCommand("/p", base, 1, ""),
     ["/p", "--tag", "t", "--voice", "en_GB-cori-high", "--", "yo"]);
  eq(M.replayCommand("/p", base, 1, null),
     ["/p", "--tag", "t", "--voice", "en_GB-cori-high", "--", "yo"]);
});

// ── parseVoiceList ──────────────────────────────────────────────────────
test("parseVoiceList: strips dir + .onnx, sorts, de-dupes", () => {
  const raw = [
    "/home/u/.local/share/piper-voices/en_US-lessac-medium.onnx",
    "/home/u/.local/share/piper-voices/en_GB-cori-high.onnx",
    "/home/u/.local/share/piper-voices/en_US-lessac-medium.onnx",
    "",
    "  /tmp/en_US-amy-medium.ONNX  ",
  ].join("\n");
  eq(M.parseVoiceList(raw), ["en_GB-cori-high", "en_US-amy-medium", "en_US-lessac-medium"]);
});

test("parseVoiceList: empty / falsy -> []", () => {
  eq(M.parseVoiceList(""), []);
  eq(M.parseVoiceList(null), []);
  eq(M.parseVoiceList(undefined), []);
});

// ── parseConfig ─────────────────────────────────────────────────────────
test("parseConfig", () => {
  eq(M.parseConfig(""), { loop: false, speed: 1, voice: "" });
  eq(M.parseConfig("junk"), { loop: false, speed: 1, voice: "" });
  eq(M.parseConfig(JSON.stringify({ loop: true, speed: 1.5 })), { loop: true, speed: 1.5, voice: "" });
  eq(M.parseConfig(JSON.stringify({ loop: "yes", speed: -2 })), { loop: false, speed: 1, voice: "" });
  eq(M.parseConfig(JSON.stringify({ voice: "en_GB-cori-high" })),
     { loop: false, speed: 1, voice: "en_GB-cori-high" });
  eq(M.parseConfig(JSON.stringify({ voice: 42 })), { loop: false, speed: 1, voice: "" });
});

console.log("\n" + pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
