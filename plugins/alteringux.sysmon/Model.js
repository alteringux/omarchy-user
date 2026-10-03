// Pure logic for the sysmon plugin: tolerant parsing of the state
// ~/.local/bin/omarchy-sysmon writes, plus the read-side formatting and
// warn/crit thresholds the bar glyph and panel render. No QML / Quickshell
// APIs so it can be reasoned about and unit-tested with `node --test`.

var HISTORY_CAP = 300
var TREND_WINDOW_MS = 10 * 60 * 1000

function num(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function finiteOrNull(value) {
  var n = Number(value)
  return isFinite(n) ? n : null
}
function metricOrNull(value) {
  if (value === null || value === undefined || value === "") return null
  return finiteOrNull(value)
}

function defaultState() {
  return {
    version: 1,
    updatedAt: 0,
    cpu: { pct: 0, cores: [] },
    memory: { pct: 0, totalKb: 0, availableKb: 0, usedKb: 0 },
    swap: { pct: 0, totalKb: 0, usedKb: 0 },
    temp: null,
    load: { one: 0, five: 0, fifteen: 0 },
    uptimeSec: 0,
    history: []
  }
}

function clampPct(v) {
  var n = num(v, 0)
  if (n < 0) return 0
  if (n > 100) return 100
  return n
}

function parseHistoryEntry(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  var cpu = metricOrNull(raw.cpu)
  var mem = metricOrNull(raw.mem)
  var temp = (raw.temp === null || raw.temp === undefined) ? null : finiteOrNull(raw.temp)
  // A row with no usable metric cannot contribute to a trend and should not
  // become a misleading all-zero sample.
  if (cpu === null && mem === null && temp === null) return null
  return {
    ts: num(raw.ts, 0),
    cpu: cpu === null ? null : clampPct(cpu),
    mem: mem === null ? null : clampPct(mem),
    temp: temp
  }
}

function parseState(raw) {
  var d = defaultState()
  if (!raw || raw.length === 0) return d
  var parsed
  try {
    parsed = typeof raw === "string" ? JSON.parse(raw) : raw
  } catch (e) {
    return d
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return d

  var cpu = parsed.cpu && typeof parsed.cpu === "object" ? parsed.cpu : {}
  var mem = parsed.memory && typeof parsed.memory === "object" ? parsed.memory : {}
  var swap = parsed.swap && typeof parsed.swap === "object" ? parsed.swap : {}
  var load = parsed.load && typeof parsed.load === "object" ? parsed.load : {}
  var history = []
  if (Array.isArray(parsed.history)) {
    for (var i = 0; i < parsed.history.length; i++) {
      var entry = parseHistoryEntry(parsed.history[i])
      if (entry) history.push(entry)
    }
    if (history.length > HISTORY_CAP) history = history.slice(history.length - HISTORY_CAP)
  }

  return {
    version: 1,
    updatedAt: num(parsed.updatedAt, 0),
    cpu: {
      pct: clampPct(cpu.pct),
      cores: Array.isArray(cpu.cores) ? cpu.cores.map(function (c) { return clampPct(c) }) : []
    },
    memory: {
      pct: clampPct(mem.pct),
      totalKb: num(mem.totalKb, 0),
      availableKb: num(mem.availableKb, 0),
      usedKb: num(mem.usedKb, 0)
    },
    swap: {
      pct: clampPct(swap.pct),
      totalKb: num(swap.totalKb, 0),
      usedKb: num(swap.usedKb, 0)
    },
    temp: (parsed.temp === null || parsed.temp === undefined) ? null : finiteOrNull(parsed.temp),
    load: {
      one: num(load.one, 0),
      five: num(load.five, 0),
      fifteen: num(load.fifteen, 0)
    },
    uptimeSec: num(parsed.uptimeSec, 0),
    history: history
  }
}

// ── history projections: sparkline points + min/avg/max/current ─────────
// `key` is "cpu", "mem", or "temp". Missing/non-finite samples are dropped,
// so a machine with no temp sensor yields an empty temp series, not zeros.
//
// When `nowMs` and `windowMs` are supplied, rows are selected by timestamp
// age rather than row count. The old two-argument form remains count-based for
// synthetic/non-epoch timestamps, while real CLI samples default to 10 minutes.
function historyWindow(nowMs, windowMs) {
  var hasNow = nowMs !== undefined && nowMs !== null
  var hasWindow = windowMs !== undefined && windowMs !== null
  if (!hasNow && !hasWindow) return null
  var now = hasNow ? num(nowMs, NaN) : Date.now()
  var window = hasWindow ? num(windowMs, NaN) : TREND_WINDOW_MS
  if (!isFinite(now) || !isFinite(window) || window < 0) return null
  return { now: now, window: window }
}

function projectionWindow(history, nowMs, windowMs) {
  var explicit = historyWindow(nowMs, windowMs)
  if (explicit) return explicit
  // CLI samples use epoch milliseconds. Tiny synthetic timestamps used by
  // older callers/tests are intentionally left on the legacy count behavior.
  if (!Array.isArray(history)) return null
  for (var i = history.length - 1; i >= 0; i--) {
    var ts = history[i] && typeof history[i] === "object" ? num(history[i].ts, 0) : 0
    if (ts >= 100000000000) return { now: Date.now(), window: TREND_WINDOW_MS }
  }
  return null
}

function inWindow(row, window) {
  if (!window || !row || !row.ts || row.ts > window.now) return !window
  return window.now - row.ts <= window.window
}

function historySeries(history, key, nowMs, windowMs) {
  if (!Array.isArray(history)) return []
  var window = projectionWindow(history, nowMs, windowMs)
  var out = []
  for (var i = 0; i < history.length; i++) {
    var row = history[i]
    if (!row || typeof row !== "object" || !inWindow(row, window)) continue
    var v = row[key]
    if (v !== null && v !== undefined && isFinite(v)) out.push(Number(v))
  }
  return out
}

function historyStats(history, key, nowMs, windowMs) {
  var s = historySeries(history, key, nowMs, windowMs)
  if (s.length === 0) return { min: 0, max: 0, avg: 0, cur: 0, n: 0 }
  var min = s[0], max = s[0], sum = 0
  for (var i = 0; i < s.length; i++) {
    var v = s[i]
    if (v < min) min = v
    if (v > max) max = v
    sum += v
  }
  return { min: min, max: max, avg: sum / s.length, cur: s[s.length - 1], n: s.length }
}

// Last `n` samples plus the max across them (floored at `floor`, so a flat
// low-usage series still renders against a sane ceiling rather than its own
// noise). If a timestamp window is provided, age filtering happens first.
function sparkline(history, key, n, floor, nowMs, windowMs) {
  var s = historySeries(history, key, nowMs, windowMs)
  if (n && s.length > n) s = s.slice(s.length - n)
  var max = (floor === undefined || floor === null) ? 1 : floor
  for (var i = 0; i < s.length; i++) if (s[i] > max) max = s[i]
  return { values: s, max: max, n: s.length }
}

// ── thresholds: "warning" from ~70/~75, "critical" from ~90/~85 ──────────

function pctLevel(pct) {
  var p = clampPct(pct)
  if (p >= 90) return "critical"
  if (p >= 70) return "warning"
  return "normal"
}

function tempLevel(celsius) {
  if (celsius === null || celsius === undefined) return "normal"
  var t = num(celsius, 0)
  if (t >= 90) return "critical"
  if (t >= 75) return "warning"
  return "normal"
}

// ── formatting ─────────────────────────────────────────────────────────

function formatPct(pct) {
  return Math.round(clampPct(pct)) + "%"
}

function formatTemp(celsius) {
  if (celsius === null || celsius === undefined) return "—"
  return Math.round(num(celsius, 0)) + "°C"
}

function formatGb(kb) {
  var gb = num(kb, 0) / (1024 * 1024)
  return (gb >= 10 ? gb.toFixed(0) : gb.toFixed(1)) + " GB"
}

function formatUptime(seconds) {
  var s = Math.max(0, num(seconds, 0))
  var days = Math.floor(s / 86400)
  var hours = Math.floor((s % 86400) / 3600)
  var mins = Math.floor((s % 3600) / 60)
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + mins + "m"
  return mins + "m"
}

// The compact bar readout, e.g. "42%  61%  68°C" (temp segment omitted when
// no sensor was found).
function barLabel(state) {
  var parts = [formatPct(state.cpu.pct), formatPct(state.memory.pct)]
  if (state.temp !== null && state.temp !== undefined) parts.push(formatTemp(state.temp))
  return parts
}

function isStale(state, nowMs, staleAfterMs) {
  var updatedAt = state ? num(state.updatedAt, 0) : 0
  if (updatedAt <= 0) return true
  var now = num(nowMs, Date.now())
  var threshold = (staleAfterMs === null || staleAfterMs === undefined)
    ? 15000 : num(staleAfterMs, 15000)
  if (threshold < 0) threshold = 0
  // A clock adjustment can make a sample appear to be from the future. Treat
  // that as zero age rather than allowing a negative age to affect freshness.
  return Math.max(0, now - updatedAt) > threshold
}

// Exposed only for the plain-node test harness. QML's JS import has no `module`
// global, and this file is re-evaluated on every state poll, so even a `typeof
// module` guard surfaces a ReferenceError in the shell log each tick. A bare
// try/catch is the only form that stays quiet in the shell.
try {
  module.exports = {
    HISTORY_CAP: HISTORY_CAP,
    TREND_WINDOW_MS: TREND_WINDOW_MS,
    defaultState: defaultState,
    parseState: parseState,
    clampPct: clampPct,
    pctLevel: pctLevel,
    tempLevel: tempLevel,
    formatPct: formatPct,
    formatTemp: formatTemp,
    formatGb: formatGb,
    formatUptime: formatUptime,
    barLabel: barLabel,
    isStale: isStale,
    historySeries: historySeries,
    historyStats: historyStats,
    sparkline: sparkline
  }
} catch (e) {}
