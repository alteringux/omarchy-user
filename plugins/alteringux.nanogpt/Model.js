.pragma library

function isRecord(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v)
}

function recordArray(v) {
  if (!Array.isArray(v)) return []
  var out = []
  for (var i = 0; i < v.length; i++) {
    if (isRecord(v[i])) out.push(v[i])
  }
  return out
}

function parseState(raw) {
  try {
    var v = (raw && raw.length) ? JSON.parse(raw) : null
    if (!isRecord(v)) return defaultState()

    // The collector writes arrays of records. Keep malformed rows out of
    // QML delegates: a null row can otherwise throw while a panel is open.
    v.ready = v.ready === true
    v.plan = isRecord(v.plan) ? v.plan : {}
    v.today = isRecord(v.today) ? v.today : {}
    v.allTime = isRecord(v.allTime) ? v.allTime : {}
    v.tokenComposition = isRecord(v.tokenComposition) ? v.tokenComposition : {}
    v.week = recordArray(v.week)
    v.models = recordArray(v.models)
    for (var i = 0; i < v.models.length; i++) {
      v.models[i].recentDays = recordArray(v.models[i].recentDays)
    }
    return v
  } catch (e) {
    return defaultState()
  }
}

function defaultState() {
  return {
    schemaVersion: 1, ready: false, plan: {},
    today: {}, week: [], allTime: {}, models: [], tokenComposition: {}
  }
}

function clamp(v, lo, hi) {
  if (v < lo) return lo
  if (v > hi) return hi
  return v
}

function formatTokens(n) {
  n = Number(n || 0)
  if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
  if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
  if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
  return String(Math.round(n))
}

function formatCost(n) {
  n = Number(n || 0)
  if (n === 0) return "$0.00"
  if (n < 0.01) return "<$0.01"
  return "$" + n.toFixed(2)
}

function formatNumber(n) {
  n = Number(n || 0)
  return n.toLocaleString()
}

function dayLabel(dateStr, todayStr) {
  if (dateStr === todayStr) return "Today"
  var d = new Date(dateStr + "T00:00:00")
  var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  return days[d.getDay()] || dateStr
}

function shortModelName(id) {
  var name = String(id || "").split("/").pop()
  return name.replace(/-/g, " ").replace(/_/g, " ")
}

// ---- subscription quota ---------------------------------------------------

// Fraction 0..1 of the weekly input-token allowance consumed.
function quotaRatio(plan) {
  if (!plan) return 0
  var lim = Number(plan.weeklyLimit || 0)
  if (lim > 0) return clamp(Number(plan.weeklyUsed || 0) / lim, 0, 1)
  return clamp(Number(plan.percentUsed || 0) / 100, 0, 1)
}

function quotaPctLabel(plan) {
  return (quotaRatio(plan) * 100).toFixed(quotaRatio(plan) < 0.1 ? 2 : 1) + "%"
}

// "resets in 3d 4h" from an epoch-millis reset time.
function formatResetIn(ms) {
  ms = Number(ms || 0)
  if (!ms) return ""
  var secs = Math.round((ms - Date.now()) / 1000)
  if (secs <= 0) return "resetting…"
  var d = Math.floor(secs / 86400); secs -= d * 86400
  var h = Math.floor(secs / 3600); secs -= h * 3600
  var m = Math.floor(secs / 60)
  if (d > 0) return "resets in " + d + "d " + h + "h"
  if (h > 0) return "resets in " + h + "h " + m + "m"
  return "resets in " + m + "m"
}

// ---- peaks / composition (shared with the panel charts) ------------------

function weekPeak(week) {
  var peak = 0
  for (var i = 0; i < week.length; i++) {
    var t = Number(week[i].totalTokens || 0)
    if (t > peak) peak = t
  }
  return peak
}

function modelPeak(models) {
  var peak = 0
  for (var i = 0; i < models.length; i++) {
    var t = Number(models[i].total || 0)
    if (t > peak) peak = t
  }
  return peak
}

function costPeak(models) {
  var peak = 0
  for (var i = 0; i < models.length; i++) {
    var c = Number(models[i].cost || 0)
    if (c > peak) peak = c
  }
  return peak
}

function hourPeak(hours) {
  if (!hours) return 0
  var peak = 0
  for (var i = 0; i < hours.length; i++) {
    if (hours[i] > peak) peak = hours[i]
  }
  return peak
}

function compositionPercents(comp) {
  if (!comp) return []
  var total = Number(comp.input || 0) + Number(comp.output || 0) +
    Number(comp.reasoning || 0) + Number(comp.cacheRead || 0) + Number(comp.cacheWrite || 0)
  if (total === 0) return []
  return [
    { label: "Input", value: Number(comp.input || 0), pct: Number(comp.input || 0) / total },
    { label: "Output", value: Number(comp.output || 0), pct: Number(comp.output || 0) / total },
    { label: "Reasoning", value: Number(comp.reasoning || 0), pct: Number(comp.reasoning || 0) / total },
    { label: "Cache Read", value: Number(comp.cacheRead || 0), pct: Number(comp.cacheRead || 0) / total },
    { label: "Cache Write", value: Number(comp.cacheWrite || 0), pct: Number(comp.cacheWrite || 0) / total },
  ]
}

function modelCompositionPercents(m) {
  if (!m) return []
  var total = Number(m.input || 0) + Number(m.output || 0) +
    Number(m.reasoning || 0) + Number(m.cacheRead || 0) + Number(m.cacheWrite || 0)
  if (total === 0) return []
  return [
    { label: "Input", value: Number(m.input || 0), pct: Number(m.input || 0) / total },
    { label: "Output", value: Number(m.output || 0), pct: Number(m.output || 0) / total },
    { label: "Reasoning", value: Number(m.reasoning || 0), pct: Number(m.reasoning || 0) / total },
    { label: "Cache Read", value: Number(m.cacheRead || 0), pct: Number(m.cacheRead || 0) / total },
    { label: "Cache Write", value: Number(m.cacheWrite || 0), pct: Number(m.cacheWrite || 0) / total },
  ]
}

function modelDayPeak(m) {
  if (!m || !m.recentDays) return 0
  var peak = 0
  for (var i = 0; i < m.recentDays.length; i++) {
    var t = Number(m.recentDays[i].totalTokens || 0)
    if (t > peak) peak = t
  }
  return peak
}

function costPerPrompt(m) {
  if (!m || !m.messages) return 0
  return Number(m.cost || 0) / m.messages
}

function costPerMtok(m) {
  if (!m || !m.total) return 0
  return Number(m.cost || 0) / (m.total / 1e6)
}

function avgTokensPerPrompt(m) {
  if (!m || !m.messages) return 0
  return Math.round(Number(m.total || 0) / m.messages)
}
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    defaultState: defaultState,
    parseState: parseState,
    quotaRatio: quotaRatio,
    weekPeak: weekPeak,
    modelPeak: modelPeak,
    costPeak: costPeak,
    hourPeak: hourPeak,
    compositionPercents: compositionPercents,
    modelCompositionPercents: modelCompositionPercents,
    modelDayPeak: modelDayPeak,
  }
}
