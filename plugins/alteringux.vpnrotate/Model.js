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

// ── wifi link state ─────────────────────────────────────────────────────
// Parses `nmcli -t -f TYPE,STATE dev` (colon-separated rows: "wifi:connected",
// "ethernet:connected", "wifi:disconnected", …). Returns one of:
//   "connected"     at least one wifi device is joined to an AP
//   "disconnected"  a wifi device exists but is on no AP (or the radio is off)
//   "unavailable"   a wifi device exists but is unmanaged / rfkill-blocked, or
//                   reports a state string we don't recognise
//   "unknown"       no wifi device at all, or empty / unreadable input
// "wifi-p2p" is a distinct TYPE and is ignored here. Multiple "wifi" rows
// collapse to the strongest: connected > disconnected > unavailable. Junk in →
// "unknown" out, so callers never need a try/catch — same safe-empty contract
// as parseState. The widget gates its connect calls on this; the bash script
// keeps its own independent gate so IPC / bare-CLI callers behave the same.
function parseWifiState(raw) {
  if (!raw || raw.length === 0) return "unknown";
  var rank = { connected: 4, disconnected: 3, unavailable: 2 };
  var best = "unknown";
  var bestRank = 0;
  var lines = raw.split("\n");
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^wifi:(\S+)/);
    if (!m) continue;
    var s = m[1];
    if (!rank[s]) s = "unavailable";
    if (rank[s] > bestRank) { bestRank = rank[s]; best = s; }
  }
  return best;
}

// True iff a wifi link is up right now. Accepts the string parseWifiState
// returns, or a parsed object carrying a `wifiState` field, so either caller
// shape works.
function isWifiActive(x) {
  if (x && typeof x === "object") x = x.wifiState;
  return x === "connected";
}

// ── metrics sidecar (written by `protonvpn-rotate metrics` + connect/rotate) ─
// {
//   load: <int %>, protocol: "wireguard", latencyMs: <int>, latencyAt: <epoch>,
//   rxBytes, txBytes, bytesAt: <epoch>,       // tunnel iface counters, reset per session
//   rotations, rotationsToday, todayDate,
//   distinctIps, ipChangedCount, failures, updated
// }
function parseMetrics(raw) {
  var empty = {
    load: 0, protocol: "", latencyMs: 0, latencyAt: 0,
    rxBytes: 0, txBytes: 0, bytesAt: 0,
    rotations: 0, rotationsToday: 0, todayDate: "",
    distinctIps: 0, ipChangedCount: 0, failures: 0, updated: 0
  };
  if (!raw || raw.length === 0) return empty;
  try {
    var p = JSON.parse(raw);
    if (!p || typeof p !== "object") return empty;
    return {
      load: num(p.load),
      protocol: str(p.protocol),
      latencyMs: num(p.latencyMs),
      latencyAt: num(p.latencyAt),
      rxBytes: num(p.rxBytes),
      txBytes: num(p.txBytes),
      bytesAt: num(p.bytesAt),
      rotations: num(p.rotations),
      rotationsToday: num(p.rotationsToday),
      todayDate: str(p.todayDate),
      distinctIps: num(p.distinctIps),
      ipChangedCount: num(p.ipChangedCount),
      failures: num(p.failures),
      updated: num(p.updated)
    };
  } catch (e) {
    return empty;
  }
}

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

// ── metric formatting ───────────────────────────────────────────────────
// Binary units (KiB/MiB/GiB) but labelled KB/MB/GB, matching how the other
// alteringux.* monitors (diskmon, netwatch) render sizes.
function formatBytes(n) {
  n = Math.max(0, num(n));
  if (n < 1024) return n + " B";
  var u = ["KB", "MB", "GB", "TB"], i = -1;
  do { n /= 1024; i++; } while (n >= 1024 && i < u.length - 1);
  return (n < 10 ? n.toFixed(1) : Math.round(n)) + " " + u[i];
}

function formatRate(bytesPerSec) {
  var b = Math.max(0, num(bytesPerSec));
  if (b < 1) return "0 B/s";
  return formatBytes(b) + "/s";
}

function formatLatency(ms) {
  var m = num(ms);
  return m > 0 ? Math.round(m) + " ms" : "—";
}

function formatLoad(pct) {
  var p = num(pct);
  return (p > 0 ? p : 0) + "%";
}

// "5 rotations · 4 changed IP · 9 seen · 1 failed" — omits zero-valued clauses
// except the leading rotation count. `today` true swaps in the daily figure.
function rotationSummary(m, today) {
  if (!m) return "";
  var n = today ? m.rotationsToday : m.rotations;
  var bits = [n + (today ? " today" : (n === 1 ? " rotation" : " rotations"))];
  if (m.ipChangedCount > 0) bits.push(m.ipChangedCount + " changed IP");
  if (m.distinctIps > 0) bits.push(m.distinctIps + " IPs seen");
  if (m.failures > 0) bits.push(m.failures + " failed");
  return bits.join("  ·  ");
}

// Instantaneous throughput from two counter samples. Guards the counter reset
// that happens when the tunnel iface is recreated on reconnect (negative → 0).
function throughput(curBytes, curAt, prevBytes, prevAt) {
  var dt = num(curAt) - num(prevAt);
  if (!(dt > 0)) return 0;
  var db = num(curBytes) - num(prevBytes);
  if (!(db > 0)) return 0;
  return db / dt;
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
    parseWifiState: parseWifiState,
    isWifiActive: isWifiActive,
    parseConfig: parseConfig,
    parseMetrics: parseMetrics,
    defaultConfig: defaultConfig,
    clampInterval: clampInterval,
    intervalPresets: intervalPresets,
    shortAgo: shortAgo,
    secondsUntilNextRotation: secondsUntilNextRotation,
    formatCountdown: formatCountdown,
    prettyInterval: prettyInterval,
    barLabel: barLabel,
    iconFor: iconFor,
    summaryLine: summaryLine,
    formatBytes: formatBytes,
    formatRate: formatRate,
    formatLatency: formatLatency,
    formatLoad: formatLoad,
    rotationSummary: rotationSummary,
    throughput: throughput
  };
}
