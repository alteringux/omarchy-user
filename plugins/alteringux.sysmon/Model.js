// Pure logic for the sysmon plugin: tolerant parsing of the state
// ~/.local/bin/omarchy-sysmon writes, plus the read-side formatting and
// warn/crit thresholds the bar glyph and panel render. No QML / Quickshell
// APIs so it can be reasoned about and unit-tested with `node --test`.

function num(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
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
    uptimeSec: 0
  }
}

function clampPct(v) {
  var n = num(v, 0)
  if (n < 0) return 0
  if (n > 100) return 100
  return n
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

  var cpu = parsed.cpu || {}
  var mem = parsed.memory || {}
  var swap = parsed.swap || {}
  var load = parsed.load || {}

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
    temp: (parsed.temp === null || parsed.temp === undefined) ? null : num(parsed.temp, null),
    load: {
      one: num(load.one, 0),
      five: num(load.five, 0),
      fifteen: num(load.fifteen, 0)
    },
    uptimeSec: num(parsed.uptimeSec, 0)
  }
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
  if (!state || !state.updatedAt) return true
  return (nowMs - state.updatedAt) > (staleAfterMs || 15000)
}

module.exports = {
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
  isStale: isStale
}
