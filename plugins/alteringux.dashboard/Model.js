// Pure logic for the dashboard plugin: state normalization and display
// formatting. Kept free of QML/Quickshell APIs so it's easy to reason about
// in isolation. The state file itself is only ever written by the bin/
// scripts (refresh + note), never by QML — this module just parses and
// formats whatever it finds on disk.

function defaultState() {
  return {
    version: 1,
    notes: { items: [] },
    news: { updatedAt: null, items: [] },
    system: { updatedAt: null, items: [] },
    engagement: { news: {} },
    digest: { text: "", updatedAt: null }
  }
}

// Tolerant parse: missing/malformed sections fall back to empty defaults
// rather than throwing, so a half-written or stale file never blanks the
// whole panel.
function parseState(raw) {
  var state = defaultState()
  if (!raw || raw.length === 0) return state
  try {
    var parsed = JSON.parse(raw)
    if (parsed.notes && Array.isArray(parsed.notes.items)) state.notes.items = parsed.notes.items
    if (parsed.news) {
      state.news.updatedAt = parsed.news.updatedAt || null
      if (Array.isArray(parsed.news.items)) state.news.items = parsed.news.items
    }
    if (parsed.system) {
      state.system.updatedAt = parsed.system.updatedAt || null
      if (Array.isArray(parsed.system.items)) state.system.items = parsed.system.items
    }
    if (parsed.engagement && parsed.engagement.news && typeof parsed.engagement.news === "object") {
      state.engagement.news = parsed.engagement.news
    }
    if (parsed.digest) {
      state.digest.text = parsed.digest.text || ""
      state.digest.updatedAt = parsed.digest.updatedAt || null
    }
  } catch (e) {
    console.warn("dashboard: state parse failed:", e)
  }
  return state
}

function formatRelative(iso) {
  if (!iso) return ""
  var then = Date.parse(iso)
  if (isNaN(then)) return ""
  var diffMs = Date.now() - then
  if (diffMs < 0) diffMs = 0
  var minutes = Math.floor(diffMs / 60000)
  if (minutes < 1) return "just now"
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  return days + "d ago"
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultState: defaultState,
    parseState: parseState,
    formatRelative: formatRelative
  }
}
