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
  var out = {
    level: clampLevel(raw.level, "warning"),
    label: label,
    action: slug(raw.action),
    actionLabel: slug(raw.actionLabel, slug(raw.action) ? "Do it" : ""),
    ts: coerceNumber(raw.ts, 0)
  }
  var source = slug(raw.source)
  if (source) out.source = source
  return out
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
// ── plugin usage (Kit.Usage scanner contract) ─────────────────────────────
//
// Pulse never reads individual usage files. The Kit-owned scanner supplies one
// normalized document, either as JSON text or as an object passed by the CLI.
// Keep this parser total because a scanner may be unavailable while the panel
// is starting up.
function defaultUsage() {
  return {
    version: 1,
    generatedAt: 0,
    thresholdDays: 0,
    plugins: [],
    summary: { tracked: 0, untracked: 0, neverUsed: 0, stale: 0 }
  }
}

function parseUsagePlugin(raw, now, thresholdDays) {
  if (!raw || typeof raw !== "object") return null
  var id = slug(raw.id)
  if (!id) return null
  var tracked = raw.tracked === true
  var uses = Math.max(0, Math.floor(coerceNumber(raw.uses, 0)))
  var lastAt = Math.max(0, coerceNumber(raw.lastAt, 0))
  var neverUsed = raw.neverUsed === true || (tracked && uses === 0 && lastAt === 0)
  var idle = raw.daysIdle
  if (typeof idle !== "number" || !isFinite(idle) || idle < 0) {
    idle = lastAt > 0 ? Math.max(0, Math.floor((now - lastAt) / DAY)) : null
  } else {
    idle = Math.max(0, idle)
  }
  var stale = tracked && (neverUsed || (idle !== null && thresholdDays > 0 && idle >= thresholdDays))
  return {
    id: id,
    label: coerceString(raw.label, id),
    source: coerceString(raw.source, ""),
    enabled: raw.enabled !== false,
    tracked: tracked,
    uses: uses,
    lastAt: lastAt,
    daysIdle: idle,
    neverUsed: neverUsed,
    stale: stale
  }
}

function makeAttentionItem(input, opts) {
  opts = opts || {}
  var now = coerceNumber(opts.now, Date.now())
  var action = slug(input && input.action)
  var out = {
    level: clampLevel(input && input.level, "warning"),
    label: slug(input && input.label),
    action: action,
    actionLabel: slug(input && input.actionLabel, action ? "Do it" : ""),
    ts: now
  }
  var source = slug(input && input.source)
  if (source) out.source = source
  return out
}


function parseUsage(raw, now) {
  var out = defaultUsage()
  var src = raw
  if (typeof src === "string") {
    if (!src.trim().length) return out
    try { src = JSON.parse(src) } catch (e) { return out }
  }
  if (src && typeof src === "object" && src.usage && typeof src.usage === "object") src = src.usage
  if (!src || typeof src !== "object") return out
  var t = coerceNumber(now, Date.now())
  var threshold = Math.max(0, Math.floor(coerceNumber(src.thresholdDays, 0)))
  out.generatedAt = src.generatedAt == null ? 0 : src.generatedAt
  out.thresholdDays = threshold
  var list = Array.isArray(src.plugins) ? src.plugins : []
  for (var i = 0; i < list.length; i++) {
    var p = parseUsagePlugin(list[i], t, threshold)
    if (p) out.plugins.push(p)
  }
  out.plugins.sort(function (a, b) {
    if (b.uses !== a.uses) return b.uses - a.uses
    return b.lastAt - a.lastAt
  })
  var counts = { tracked: 0, untracked: 0, neverUsed: 0, stale: 0 }
  out.plugins.forEach(function (p) {
    if (p.tracked) counts.tracked++
    else counts.untracked++
    if (p.neverUsed) counts.neverUsed++
    if (p.stale) counts.stale++
  })
  out.summary = counts
  return out
}

function usageMostUsed(usage, n) {
  var list = usage && Array.isArray(usage.plugins) ? usage.plugins.slice() : []
  list.sort(function (a, b) {
    if (b.uses !== a.uses) return b.uses - a.uses
    return b.lastAt - a.lastAt
  })
  return list.slice(0, n > 0 ? n : 3)
}
function usageLeastUsed(usage, n) {
  var list = usage && Array.isArray(usage.plugins) ? usage.plugins.slice() : []
  list.sort(function (a, b) {
    if (a.uses !== b.uses) return a.uses - b.uses
    return a.lastAt - b.lastAt
  })
  return list.slice(0, n > 0 ? n : 3)
}


function usageStale(usage) {
  return usage && Array.isArray(usage.plugins)
    ? usage.plugins.filter(function (p) { return p.tracked && p.stale })
    : []
}


// ── builders (pulse-cli.js hands these back for the bash side to write) ────
// One stable attention item for all stale tracked plugins. Keeping this as a
// model builder makes the shell bridge data-only: no scanner output is ever
// interpreted as shell code.
function makeUsageAttention(usage, opts) {
  opts = opts || {}
  var acknowledged = opts.acknowledged && typeof opts.acknowledged === "object"
    ? opts.acknowledged : {}
  var stale = usageStale(usage).filter(function (p) {
    var ack = acknowledged[p.id]
    if (!ack || typeof ack !== "object") return true
    return Number(ack.lastAt || 0) !== Number(p.lastAt || 0)
      || Number(ack.uses || 0) !== Number(p.uses || 0)
  })
  if (!stale.length) return null
  var parts = stale.map(function (p) {
    return p.id + " (" + (p.neverUsed ? "never used" : String(Math.floor(p.daysIdle)) + "d idle") + ")"
  })
  return makeAttentionItem({
    label: "Plugin usage stale: " + parts.join(", "),
    level: "warning",
    action: "omarchy-pulse usage",
    actionLabel: "Refresh",
    source: "plugin-usage"
  }, opts)
}


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


// ── read side ────────────────────────────────────────────────────────────

// attention.items map -> array, loudest first then newest first.
function attentionList(attention) {
  var att = attention && attention.items ? attention.items : {}
  return Object.keys(att).map(function (plugin) {
    var it = att[plugin]
    var out = {
      plugin: plugin,
      level: it.level,
      label: it.label,
      action: it.action,
      actionLabel: it.actionLabel,
      ts: it.ts
    }
    if (it.source) out.source = it.source
    return out
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

function summary(activity, attention, state, usage) {
  var atts = attentionList(attention)
  var unread = unreadEvents(activity, state)
  var pluginUsage = parseUsage(usage)
  var stalePlugins = usageStale(pluginUsage)
  var topLevel = ""
  for (var i = 0; i < atts.length; i++) topLevel = maxLevel(topLevel || "info", atts[i].level)
  if (!atts.length) topLevel = ""
  var result = {
    unread: unread.length,
    total: activity && activity.events ? activity.events.length : 0,
    needAction: atts.length,
    topLevel: atts.length ? topLevel : "",
    nextAction: nextAction(activity, attention, state)
  }
  if (usage !== undefined && usage !== null) {
    result.usage = pluginUsage
    result.pluginUsage = pluginUsage
    result.mostUsed = usageMostUsed(pluginUsage, 3)
    result.leastUsed = usageLeastUsed(pluginUsage, 3)
    result.stalePlugins = stalePlugins
  }
  return result
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
    defaultUsage: defaultUsage,
    parseActivity: parseActivity,
    parseAttention: parseAttention,
    parseState: parseState,
    parseUsage: parseUsage,
    pruneEvents: pruneEvents,
    makeEvent: makeEvent,
    makeAttentionItem: makeAttentionItem,
    makeUsageAttention: makeUsageAttention,
    attentionList: attentionList,
    unreadEvents: unreadEvents,
    nextAction: nextAction,
    usageMostUsed: usageMostUsed,
    usageLeastUsed: usageLeastUsed,
    usageStale: usageStale,
    summary: summary,
    relTime: relTime,
    formatList: formatList
  }
}
