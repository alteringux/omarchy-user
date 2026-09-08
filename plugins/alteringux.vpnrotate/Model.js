// Pure helpers for the alteringux.vpnrotate bar widget. No QML / Quickshell
// APIs in here so the parsing + formatting can be unit-tested under plain node
// (test/model.test.js). The guarded module.exports at the bottom is a no-op
// inside QML.

// ── status file (written by ~/.local/bin/protonvpn-rotate) ────────────────
// {
//   connected: bool, action: "idle|connecting|rotating|disconnecting",
//   server: "NL#123", exitIp: "1.2.3.4", country: "NL", city: "Amsterdam",
//   org: "Proton AG", since: <epoch>, lastRotate: <epoch>, error: "", updated: <epoch>
// }
function parseState(raw) {
  var empty = {
    connected: false, action: "idle", server: "", exitIp: "", country: "",
    city: "", org: "", since: 0, lastRotate: 0, error: "", updated: 0
  };
  if (!raw || raw.length === 0) return empty;
  try {
    var p = JSON.parse(raw);
    if (!p || typeof p !== "object") return empty;
    return {
      connected: p.connected === true,
      action: typeof p.action === "string" ? p.action : "idle",
      server: str(p.server),
      exitIp: str(p.exitIp),
      country: str(p.country).toUpperCase(),
      city: str(p.city),
      org: str(p.org),
      since: num(p.since),
      lastRotate: num(p.lastRotate),
      error: str(p.error),
      updated: num(p.updated)
    };
  } catch (e) {
    return empty;
  }
}

function str(v) { return typeof v === "string" ? v : ""; }
function num(v) { return typeof v === "number" && isFinite(v) ? v : 0; }

// ── widget-owned config (Kit.Store, owned mode) ──────────────────────────
function parseConfig(raw) {
  var d = defaultConfig();
  if (!raw || raw.length === 0) return d;
  try {
    var p = JSON.parse(raw) || {};
    return {
      autoRotate: p.autoRotate === true,
      intervalSec: clampInterval(p.intervalSec),
      killSwitch: p.killSwitch === true
    };
  } catch (e) {
    return d;
  }
}

function defaultConfig() {
  return { autoRotate: false, intervalSec: 600, killSwitch: false };
}

// Proton free tier: don't let the user set a cadence that would trip abuse
// detection or leave the tunnel down more than up. 60s floor, 6h ceiling.
function clampInterval(v) {
  var n = Math.round(num(v));
  if (!(n >= 1)) return 600;
  if (n < 60) return 60;
  if (n > 21600) return 21600;
  return n;
}

// Presets offered in the panel (seconds → label).
function intervalPresets() {
  return [
    { sec: 60, label: "1m" },
    { sec: 120, label: "2m" },
    { sec: 300, label: "5m" },
    { sec: 600, label: "10m" },
    { sec: 1800, label: "30m" }
  ];
}

// ── formatting ──────────────────────────────────────────────────────────
function shortAgo(epochSec, nowSec) {
  if (!(epochSec > 0)) return "";
  var d = Math.max(0, Math.floor(nowSec - epochSec));
  if (d < 5) return "just now";
  if (d < 60) return d + "s ago";
  if (d < 3600) return Math.floor(d / 60) + "m ago";
  if (d < 86400) return Math.floor(d / 3600) + "h ago";
  return Math.floor(d / 86400) + "d ago";
}

function secondsUntilNextRotation(state, config, nowSec) {
  if (!config || !config.autoRotate || !state || !state.connected) return null;
  var base = state.lastRotate > 0 ? state.lastRotate : state.since;
  if (!(base > 0)) return config.intervalSec;
  return Math.max(0, base + config.intervalSec - nowSec);
}

function formatCountdown(sec) {
  if (sec === null || sec === undefined) return "";
  var s = Math.max(0, Math.floor(sec));
  var m = Math.floor(s / 60);
  var r = s % 60;
  if (m <= 0) return r + "s";
  return m + "m " + (r < 10 ? "0" : "") + r + "s";
}

// Bar label next to the shield: country code when connected, else nothing.
// Transient states show nothing here and let iconFor() carry the meaning.
function barLabel(state) {
  if (!state) return "";
  if (state.action === "connecting" || state.action === "rotating" || state.action === "disconnecting") return "";
  if (state.connected) return state.country || "on";
  return "";
}

// Which glyph the shield shows. BMP Nerd Font (nf-fa-*) escapes only, so the
// literal survives editing (see memory: nerd-font-glyph-edits) and matches how
// the other alteringux.* widgets pick icons.
//   \uf132 nf-fa-shield   \uf021 nf-fa-refresh   \uf071 nf-fa-warning
// "off" and "connected" share the shield; the widget dims it when off and
// shows the country code beside it when on.
function iconFor(state) {
  if (!state) return "\uf132";
  if (state.action === "connecting" || state.action === "rotating") return "\uf021";
  if (state.error) return "\uf071";
  return "\uf132";
}

// Label for an arbitrary interval: the matching preset's label, else a plain
// "Nm" / formatCountdown fallback. Was hand-rolled in Panel.qml as
// formatCountdown(sec).replace(" 00s", "m"), which only strips the string
// " 00s" — for any exact-minute value formatCountdown already renders
// zero-padded ("2m 00s"), so the replace left a stray trailing "m" behind
// ("2mm"). Only presets are offered as buttons today, but a hand-edited
// vpnrotate-config.json can set any clamped value, and this is also the
// fallback the panel falls through to for those.
function prettyInterval(sec) {
  var presets = intervalPresets()
  for (var i = 0; i < presets.length; i++)
    if (presets[i].sec === sec) return presets[i].label
  var s = Math.max(0, Math.floor(sec))
  var r = s % 60
  if (r === 0) return Math.floor(s / 60) + "m"
  return formatCountdown(s)
}

// One-line human summary for the panel header / tooltip.
function summaryLine(state) {
  if (!state) return "Not connected";
  if (state.action === "connecting") return "Connecting\u2026";
  if (state.action === "rotating") return "Rotating\u2026";
  if (state.action === "disconnecting") return "Disconnecting\u2026";
  if (state.error) return "Error: " + state.error;
  if (state.connected) {
    var where = [state.city, state.country].filter(Boolean).join(", ");
    return "Connected" + (where ? " · " + where : "") + (state.exitIp ? " · " + state.exitIp : "");
  }
  return "Not connected";
}

if (typeof module !== "undefined") {
  module.exports = {
    parseState: parseState,
    parseConfig: parseConfig,
    defaultConfig: defaultConfig,
    clampInterval: clampInterval,
    intervalPresets: intervalPresets,
    shortAgo: shortAgo,
    secondsUntilNextRotation: secondsUntilNextRotation,
    formatCountdown: formatCountdown,
    prettyInterval: prettyInterval,
    barLabel: barLabel,
    iconFor: iconFor,
    summaryLine: summaryLine
  };
}
