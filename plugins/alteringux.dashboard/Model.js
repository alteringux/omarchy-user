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
function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function stringOrNull(value) {
  return typeof value === "string" ? value : null
}

function parseNewsItems(items) {
  if (!Array.isArray(items)) return []
  return items.reduce(function (out, item) {
    if (!isRecord(item) || typeof item.title !== "string" || item.title.length === 0) return out
    var parsed = { title: item.title }
    var url = stringOrNull(item.url)
    var meta = stringOrNull(item.meta)
    if (url) parsed.url = url
    if (meta) parsed.meta = meta
    out.push(parsed)
    return out
  }, [])
}

function parseTextItems(items, withTimestamp) {
  if (!Array.isArray(items)) return []
  return items.reduce(function (out, item) {
    if (!isRecord(item) || typeof item.text !== "string" || item.text.length === 0) return out
    var parsed = { text: item.text }
    if (withTimestamp && typeof item.at === "string") parsed.at = item.at
    out.push(parsed)
    return out
  }, [])
}

function parseState(raw) {
  var state = defaultState()
  if (!raw || raw.length === 0) return state
  try {
    var parsed = JSON.parse(raw)
    if (isRecord(parsed.notes)) state.notes.items = parseTextItems(parsed.notes.items, true)
    if (isRecord(parsed.news)) {
      state.news.updatedAt = stringOrNull(parsed.news.updatedAt)
      state.news.items = parseNewsItems(parsed.news.items)
    }
    if (isRecord(parsed.system)) {
      state.system.updatedAt = stringOrNull(parsed.system.updatedAt)
      state.system.items = parseTextItems(parsed.system.items, false)
    }
    if (isRecord(parsed.engagement) && isRecord(parsed.engagement.news)) {
      state.engagement.news = parsed.engagement.news
    }
    if (isRecord(parsed.digest)) {
      state.digest.text = typeof parsed.digest.text === "string" ? parsed.digest.text : ""
      state.digest.updatedAt = stringOrNull(parsed.digest.updatedAt)
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
