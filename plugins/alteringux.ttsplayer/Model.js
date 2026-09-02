// Pure helpers for the alteringux.ttsplayer bar widget. No QML / Quickshell
// APIs in here so the parsing + progress math can be unit-tested with plain
// node (test/model.test.js).

// ── current.json ─────────────────────────────────────────────────────────
// Written by piper-tts (_tts_publish_current) once a job holds the playback
// queue. Returns null for "nothing is speaking" (missing / empty / garbage
// file, or a record with no live pgid field).
function parseState(raw) {
  if (!raw || raw.length === 0) return null;
  try {
    var d = JSON.parse(raw);
    if (!d || typeof d.pgid !== "number" || d.pgid <= 0) return null;
    return {
      tag: (typeof d.tag === "string" && d.tag) ? d.tag : "default",
      voice: typeof d.voice === "string" ? d.voice : "",
      lengthScale: typeof d.length_scale === "string" ? d.length_scale : "",
      pgid: d.pgid,
      startedAt: typeof d.started_at === "number" ? d.started_at : 0,
      chunks: (typeof d.chunks === "number" && d.chunks > 0) ? d.chunks : 1,
      chars: (typeof d.chars === "number" && d.chars > 0) ? d.chars : 0,
      text: typeof d.text === "string" ? d.text : ""
    };
  } catch (e) {
    return null;
  }
}

// ── tts-player-ctl status ────────────────────────────────────────────────
// Tolerant: always returns a well-formed object so the widget never has to
// null-check the poll result.
function parseStatus(raw) {
  var base = { active: false, paused: false, muted: false, played: 0, elapsed: 0, chunks: 1 };
  if (!raw) return base;
  try {
    var d = JSON.parse(raw);
    if (!d || d.active !== true) return base;
    return {
      active: true,
      paused: d.paused === true,
      muted: d.muted === true,
      played: (typeof d.played === "number" && d.played >= 0) ? d.played : 0,
      elapsed: (typeof d.elapsed === "number" && d.elapsed >= 0) ? d.elapsed : 0,
      chunks: (typeof d.chunks === "number" && d.chunks > 0) ? d.chunks : 1
    };
  } catch (e) {
    return base;
  }
}

function formatElapsed(totalSeconds) {
  var s = Math.max(0, Math.floor(totalSeconds || 0));
  var m = Math.floor(s / 60);
  var sec = s % 60;
  return m + ":" + (sec < 10 ? "0" : "") + sec;
}

// A streaming TTS job has no true total duration (piper-tts pipes raw PCM
// through paplay chunk by chunk, synthesising ahead of the play cursor). So
// this is a best-effort fraction, never a promise:
//   * multiple chunks  -> the chunk cursor, the honest signal. Divided by
//     (chunks + 1) so the bar doesn't read 100% while the last chunk is
//     still being spoken.
//   * single chunk     -> a characters-per-second time estimate.
// Caps at 0.98 so the fill only completes when the job actually ends and the
// widget clears it.
function progressFraction(o) {
  o = o || {};
  var chunks = o.chunks > 0 ? o.chunks : 1;
  var played = o.played >= 0 ? o.played : 0;
  var elapsed = o.elapsed >= 0 ? o.elapsed : 0;
  var chars = o.chars > 0 ? o.chars : 0;
  var f;
  if (chunks > 1) {
    f = (played + 1) / (chunks + 1);
  } else if (chars > 0) {
    var est = chars / 14; // ~14 chars/s for en_GB-cori-high at length_scale 1
    f = est > 0 ? elapsed / est : 0;
  } else {
    f = 0;
  }
  if (!(f >= 0)) f = 0;
  if (f > 0.98) f = 0.98;
  return f;
}

function chunkLabel(o) {
  o = o || {};
  var chunks = o.chunks > 0 ? o.chunks : 1;
  if (chunks <= 1) return "";
  var n = Math.min(chunks, (o.played >= 0 ? o.played : 0) + 1);
  return "chunk " + n + "/" + chunks;
}

// piper-tts --length_scale: higher = slower. A 1.5x speed-up is length_scale
// 0.667. "" means "leave piper's default", i.e. 1x.
function speedToLengthScale(speed) {
  if (!speed || speed <= 0 || speed === 1) return "";
  return String(Math.round((1 / speed) * 1000) / 1000);
}

// Argv for replaying a captured reading (Loop, or Restart-at-speed / voice).
// Mirrors how omarchy-narrate calls piper-tts; the queue is left ON so a loop
// can't stomp another voice. `voiceOverride`, when a non-empty string, wins
// over the voice captured in the reading — that's how the panel's Voice
// dropdown re-speaks the current text in a different model.
function replayCommand(piperTtsPath, state, speed, voiceOverride) {
  var voice = (typeof voiceOverride === "string" && voiceOverride)
    ? voiceOverride
    : ((state && state.voice) ? state.voice : "");
  var cmd = [piperTtsPath, "--tag", (state && state.tag) ? state.tag : "default"];
  if (voice) cmd.push("--voice", voice);
  var ls = speedToLengthScale(speed);
  if (ls) cmd.push("--length-scale", ls);
  cmd.push("--", (state && state.text) ? state.text : "");
  return cmd;
}

// Voice ids from a newline-separated list of .onnx paths, as produced by
// `ls -1 "$PIPER_TTS_VOICE_DIR"/*.onnx`. Directory and extension stripped,
// de-duped, sorted. Returns [] for empty / garbage so the dropdown falls back
// to whatever the current reading is already using.
function parseVoiceList(raw) {
  if (!raw) return [];
  var out = [], seen = {};
  var lines = String(raw).split("\n");
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    if (!line) continue;
    var base = line.replace(/^.*\//, "").replace(/\.onnx$/i, "");
    if (!base || seen[base]) continue;
    seen[base] = true;
    out.push(base);
  }
  out.sort();
  return out;
}

// ── ttsplayer.json (widget-owned config: Loop + Speed + Voice) ───────────
// `voice` is "" when the user has not pinned one, meaning "use whatever the
// reading was produced with / piper's default".
function parseConfig(raw) {
  var d = { loop: false, speed: 1, voice: "" };
  if (!raw) return d;
  try {
    var p = JSON.parse(raw);
    if (p && typeof p === "object") {
      d.loop = p.loop === true;
      if (typeof p.speed === "number" && p.speed > 0) d.speed = p.speed;
      if (typeof p.voice === "string") d.voice = p.voice;
    }
  } catch (e) { /* keep defaults */ }
  return d;
}

if (typeof module !== "undefined") {
  module.exports = {
    parseState: parseState,
    parseStatus: parseStatus,
    formatElapsed: formatElapsed,
    progressFraction: progressFraction,
    chunkLabel: chunkLabel,
    speedToLengthScale: speedToLengthScale,
    replayCommand: replayCommand,
    parseVoiceList: parseVoiceList,
    parseConfig: parseConfig
  };
}
