// Pure logic for the alteringux.pulse plugin: the cross-plugin activity feed +
// "this plugin needs action" signal.
//
// Kept free of QML/Quickshell APIs so the same code runs under `node --test`
// and from the bash CLI (via pulse-cli.js). The bash side (omarchy-pulse) owns
// the three state files and every side effect; this module only parses,
// normalises, prunes and summarises.
//
//   ~/.local/state/omarchy/alteringux-activity.jsonl   append-only, one event per line
//   ~/.local/state/omarchy/alteringux-attention.json   { items: { <pluginId>: {...} } }
//   ~/.local/state/omarchy/alteringux-pulse-state.json  { lastReadTs }

var MINUTE = 60000
var HOUR = 60 * MINUTE
var DAY = 24 * HOUR

// Loudness ramp. Index == rank; `pulse` levels drive Kit.AttentionDot's breathe.
var LEVELS = ["info", "warning", "urgent", "critical"]

var MAX_EVENTS = 250
var MAX_AGE_MS = 21 * DAY

// ── level helpers ──────────────────────────────────────────────────────────

function levelRank(level) {
  var i = LEVELS.indexOf(String(level))
  return i < 0 ? 0 : i
}

function clampLevel(level, fallback) {
  var l = String(level == null ? "" : level).toLowerCase()
  return LEVELS.indexOf(l) >= 0 ? l : (fallback || "info")
}

function maxLevel(a, b) {
  return levelRank(a) >= levelRank(b) ? clampLevel(a, "info") : clampLevel(b, "info")
}

// ── defaults ──────────────────────────────────────────────────────────────

function defaultActivity() {
  return { version: 1, events: [] }
}

function defaultAttention() {
  return { version: 1, items: {} }
}

function defaultState() {
  return { version: 1, lastReadTs: 0 }
}

// ── tolerant parsing ──────────────────────────────────────────────────────

function coerceNumber(value, fallback) {
  return typeof value === "number" && isFinite(value) ? value : fallback
}

function coerceString(value, fallback) {
  return typeof value === "string" ? value : (value == null ? (fallback || "") : String(value))
}

function slug(value, fallback) {
  var s = coerceString(value, "").trim()
  return s.length ? s : (fallback || "")
}

// A stable-ish id from ts + a counter, used when an event line has none.
function synthId(ts, i) {
  return "e" + String(ts || 0) + "-" + String(i || 0)
}

function normaliseEvent(raw, i) {
  if (!raw || typeof raw !== "object") return null
  var ts = coerceNumber(raw.ts, 0)
  if (ts <= 0) return null
  var message = slug(raw.message)
  if (!message) return null
  var action = slug(raw.action)
  return {
    id: slug(raw.id, synthId(ts, i)),
    ts: ts,
    plugin: slug(raw.plugin, "unknown"),
    message: message,
    action: action,
    actionLabel: slug(raw.actionLabel, action ? "Open" : ""),
    level: clampLevel(raw.level, "info")
  }
}

// Accepts the raw JSONL text OR an already-parsed { events } object OR an array.
function parseActivity(raw, now) {
  var out = defaultActivity()
  var list = []
  if (Array.isArray(raw)) {
    list = raw
  } else if (raw && typeof raw === "object") {
    list = Array.isArray(raw.events) ? raw.events : []
  } else if (typeof raw === "string" && raw.trim().length) {
    var lines = raw.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      try {
        list.push(JSON.parse(line))
      } catch (e) {
        // tolerate a half-written trailing line / hand-edit
      }
    }
  }

  var seen = {}
  var events = []
  for (var j = 0; j < list.length; j++) {
    var ev = normaliseEvent(list[j], j)
    if (!ev) continue
    if (seen[ev.id]) continue
    seen[ev.id] = true
    events.push(ev)
  }
  out.events = pruneEvents(events, coerceNumber(now, Date.now()))
  return out
}

function pruneEvents(events, now) {
  var cutoff = coerceNumber(now, Date.now()) - MAX_AGE_MS
  var kept = events.filter(function (e) { return e.ts >= cutoff })
  kept.sort(function (a, b) { return b.ts - a.ts })
  return kept.slice(0, MAX_EVENTS)
}

function parseAttentionItem(raw) {
  if (!raw || typeof raw !== "object") return null
  var label = slug(raw.label)
  if (!label) return null
  return {
    level: clampLevel(raw.level, "warning"),
    label: label,
    action: slug(raw.action),
    actionLabel: slug(raw.actionLabel, slug(raw.action) ? "Do it" : ""),
    ts: coerceNumber(raw.ts, 0)
  }
}

function parseAttention(raw) {
  var out = defaultAttention()
  var src
  if (typeof raw === "string") {
    if (!raw.trim().length) return out
    try { src = JSON.parse(raw) } catch (e) { return out }
  } else {
    src = raw
  }
  if (!src || typeof src !== "object") return out
  var items = src.items && typeof src.items === "object" ? src.items : {}
  var keys = Object.keys(items)
  for (var i = 0; i < keys.length; i++) {
    var item = parseAttentionItem(items[keys[i]])
    if (item) out.items[keys[i]] = item
  }
  return out
}

function parseState(raw) {
  var out = defaultState()
  var src
  if (typeof raw === "string") {
    if (!raw.trim().length) return out
    try { src = JSON.parse(raw) } catch (e) { return out }
  } else {
    src = raw
  }
  if (src && typeof src === "object") {
    out.lastReadTs = coerceNumber(src.lastReadTs, 0)
  }
  return out
}

// ── builders (pulse-cli.js hands these back for the bash side to write) ────

// input: { plugin, message, action?, actionLabel?, level? }
function makeEvent(input, opts) {
  opts = opts || {}
  var now = coerceNumber(opts.now, Date.now())
  var action = slug(input && input.action)
  return {
    id: slug(opts.id, synthId(now, Math.floor(Math.random() * 100000))),
    ts: now,
    plugin: slug(input && input.plugin, "unknown"),
    message: slug(input && input.message),
    action: action,
    actionLabel: slug(input && input.actionLabel, action ? "Open" : ""),
    level: clampLevel(input && input.level, "info")
  }
}

// input: { plugin, label, action?, actionLabel?, level? } -> the item object
// stored under attention.items[plugin].
function makeAttentionItem(input, opts) {
  opts = opts || {}
  var now = coerceNumber(opts.now, Date.now())
  var action = slug(input && input.action)
  return {
    level: clampLevel(input && input.level, "warning"),
    label: slug(input && input.label),
    action: action,
    actionLabel: slug(input && input.actionLabel, action ? "Do it" : ""),
    ts: now
  }
}

// ── read side ────────────────────────────────────────────────────────────

// attention.items map -> array, loudest first then newest first.
function attentionList(attention) {
  var att = attention && attention.items ? attention.items : {}
  return Object.keys(att).map(function (plugin) {
    var it = att[plugin]
    return {
      plugin: plugin,
      level: it.level,
      label: it.label,
      action: it.action,
      actionLabel: it.actionLabel,
      ts: it.ts
    }
  }).sort(function (a, b) {
    var d = levelRank(b.level) - levelRank(a.level)
    return d !== 0 ? d : b.ts - a.ts
  })
}

function unreadEvents(activity, state) {
  var since = state && state.lastReadTs ? state.lastReadTs : 0
  var events = activity && activity.events ? activity.events : []
  return events.filter(function (e) { return e.ts > since })
}

// The single "do this next" pick: loudest outstanding attention item, else the
// most recent unread event that carries an action.
function nextAction(activity, attention, state) {
  var atts = attentionList(attention)
  if (atts.length) {
    var top = atts[0]
    return {
      source: "attention",
      plugin: top.plugin,
      label: top.label,
      action: top.action,
      actionLabel: top.actionLabel || "Do it",
      level: top.level
    }
  }
  var unread = unreadEvents(activity, state).filter(function (e) { return e.action })
  if (unread.length) {
    var e = unread[0] // events are newest-first
    return {
      source: "activity",
      plugin: e.plugin,
      label: e.message,
      action: e.action,
      actionLabel: e.actionLabel || "Open",
      level: e.level
    }
  }
  return null
}

function summary(activity, attention, state) {
  var atts = attentionList(attention)
  var unread = unreadEvents(activity, state)
  var topLevel = ""
  for (var i = 0; i < atts.length; i++) topLevel = maxLevel(topLevel || "info", atts[i].level)
  if (!atts.length) topLevel = ""
  return {
    unread: unread.length,
    total: activity && activity.events ? activity.events.length : 0,
    needAction: atts.length,
    topLevel: atts.length ? topLevel : "",
    nextAction: nextAction(activity, attention, state)
  }
}

// ── formatting (omarchy-pulse list) ──────────────────────────────────────

function relTime(deltaMs) {
  var d = Math.max(0, deltaMs)
  if (d < 45 * 1000) return "just now"
  if (d < 90 * 1000) return "1m ago"
  if (d < HOUR) return Math.round(d / MINUTE) + "m ago"
  if (d < 22 * HOUR) return Math.round(d / HOUR) + "h ago"
  return Math.round(d / DAY) + "d ago"
}

function formatList(activity, now, n) {
  var t = coerceNumber(now, Date.now())
  var events = (activity && activity.events ? activity.events : []).slice(0, n > 0 ? n : 20)
  if (!events.length) return "No activity yet."
  return events.map(function (e) {
    var flag = levelRank(e.level) >= levelRank("urgent") ? "!" : " "
    var when = relTime(t - e.ts)
    var act = e.action ? "   -> " + e.action : ""
    return flag + " " + e.plugin.replace(/^alteringux\./, "").padEnd(10).slice(0, 10) +
      "  " + when.padEnd(9) + "  " + e.message + act
  }).join("\n")
}

// ── exports ──────────────────────────────────────────────────────────────

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    LEVELS: LEVELS,
    levelRank: levelRank,
    clampLevel: clampLevel,
    maxLevel: maxLevel,
    defaultActivity: defaultActivity,
    defaultAttention: defaultAttention,
    defaultState: defaultState,
    parseActivity: parseActivity,
    parseAttention: parseAttention,
    parseState: parseState,
    pruneEvents: pruneEvents,
    makeEvent: makeEvent,
    makeAttentionItem: makeAttentionItem,
    attentionList: attentionList,
    unreadEvents: unreadEvents,
    nextAction: nextAction,
    summary: summary,
    relTime: relTime,
    formatList: formatList
  }
}
