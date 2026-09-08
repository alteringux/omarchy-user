.pragma library

function parseState(raw) {
  try {
    var v = (raw && raw.length) ? JSON.parse(raw) : null
    if (!v || typeof v !== "object") return defaultState()
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
  var name = id.split("/").pop()
  return name.replace(/-/g, " ").replace(/_/g, " ")
}

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