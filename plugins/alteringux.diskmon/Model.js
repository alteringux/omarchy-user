// Pure logic for the diskmon plugin: tolerant parsing of the state
// ~/.local/bin/omarchy-diskmon writes, plus the read-side formatting the bar
// glyph and panel render. No QML / Quickshell APIs so it can be reasoned
// about and unit-tested with `node --test`.

function num(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function defaultMount() {
  return { source: null, fstype: null, totalKb: 0, usedKb: 0, availKb: 0, pct: 0, target: null }
}

function defaultState() {
  return {
    version: 1,
    updatedAt: 0,
    primary: (function () { var m = defaultMount(); m.level = "normal"; return m })(),
    mounts: [],
    history: []
  }
}

function clampPct(v) {
  var n = num(v, 0)
  if (n < 0) return 0
  if (n > 100) return 100
  return n
}

function parseMount(m) {
  m = m || {}
  return {
    source: typeof m.source === "string" ? m.source : null,
    fstype: typeof m.fstype === "string" ? m.fstype : null,
    totalKb: num(m.totalKb, 0),
    usedKb: num(m.usedKb, 0),
    availKb: num(m.availKb, 0),
    pct: clampPct(m.pct),
    target: typeof m.target === "string" ? m.target : null
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
  if (!parsed || typeof parsed !== "object") return d

  var primary = parseMount(parsed.primary)
  primary.level = ["normal", "warning", "critical"].indexOf(parsed.primary && parsed.primary.level) !== -1
    ? parsed.primary.level
    : "normal"

  return {
    version: 1,
    updatedAt: num(parsed.updatedAt, 0),
    primary: primary,
    mounts: Array.isArray(parsed.mounts) ? parsed.mounts.map(parseMount) : [],
    history: Array.isArray(parsed.history)
      ? parsed.history.map(function (h) {
          h = h || {}
          return { ts: num(h.ts, 0), pct: clampPct(h.pct) }
        })
      : []
  }
}

// ── history projections: sparkline points + min/avg/max/current ─────────

function historySeries(history, key) {
  if (!Array.isArray(history)) return []
  var out = []
  for (var i = 0; i < history.length; i++) {
    var v = history[i] ? history[i][key] : null
    if (v !== null && v !== undefined && isFinite(v)) out.push(Number(v))
  }
  return out
}

function historyStats(history, key) {
  var s = historySeries(history, key || "pct")
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

function sparkline(history, key, n, floor) {
  var s = historySeries(history, key || "pct")
  if (n && s.length > n) s = s.slice(s.length - n)
  var max = (floor === undefined || floor === null) ? 1 : floor
  for (var i = 0; i < s.length; i++) if (s[i] > max) max = s[i]
  return { values: s, max: max, n: s.length }
}

// ── formatting ─────────────────────────────────────────────────────────

function formatPct(pct) {
  return Math.round(clampPct(pct)) + "%"
}

function formatGb(kb) {
  var gb = num(kb, 0) / (1024 * 1024)
  return (gb >= 10 ? gb.toFixed(0) : gb.toFixed(1)) + " GB"
}

function isStale(state, nowMs, staleAfterMs) {
  if (!state || !state.updatedAt) return true
  return (nowMs - state.updatedAt) > (staleAfterMs || 15000)
}

// Exposed only for the plain-node test harness. QML's JS import has no `module`
// global, and this file is re-evaluated on every state poll, so even a `typeof
// module` guard surfaces a ReferenceError in the shell log each tick. A bare
// try/catch is the only form that stays quiet in the shell.
try {
  module.exports = {
    defaultState: defaultState,
    parseState: parseState,
    clampPct: clampPct,
    formatPct: formatPct,
    formatGb: formatGb,
    isStale: isStale,
    historySeries: historySeries,
    historyStats: historyStats,
    sparkline: sparkline
  }
} catch (e) {}
