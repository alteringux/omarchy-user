// Pure logic for the countdown plugin: a flat list of "countdowns", each just
// a label + an absolute target instant (local midnight of the target calendar
// day, epoch-ms). Days remaining is ALWAYS derived from the stored target,
// never persisted, so a countdown keeps ticking down across restarts and rolls
// over on its own at local midnight. Mutations: add (prepend, newest-first),
// remove (permanent), clear. No QML/Quickshell APIs in here so it can be
// unit-tested with plain node — same convention as the other alteringux.*
// plugins.

var DAY_MS = 86400000

function defaultState() {
  return { version: 1, entries: [] }
}

// Local midnight of the day `epochMs` falls in.
function startOfLocalDay(epochMs) {
  var d = new Date(isFinite(epochMs) ? epochMs : Date.now())
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

// Local midnight `days` whole calendar days from `nowMs`. Walks the date field
// rather than adding days*DAY_MS so a DST boundary in between can't shift it
// off midnight.
function targetEpochFor(days, nowMs) {
  var n = Math.round(Number(days))
  if (!isFinite(n)) n = 0
  var d = new Date(isFinite(nowMs) && nowMs > 0 ? nowMs : Date.now())
  d.setHours(0, 0, 0, 0)
  d.setDate(d.getDate() + n)
  return d.getTime()
}

// Whole calendar days from today to the target day. 0 = the target day itself,
// negative = already past. Decrements at local midnight.
function daysRemaining(targetEpoch, nowMs) {
  var a = startOfLocalDay(nowMs)
  var b = startOfLocalDay(targetEpoch)
  return Math.round((b - a) / DAY_MS)
}

function newId(nowMs) {
  var base = isFinite(nowMs) && nowMs > 0 ? Math.floor(nowMs) : Date.now()
  return "c" + base + "-" + Math.random().toString(36).slice(2, 8)
}

function sanitizeEntry(raw) {
  if (!raw || typeof raw !== "object") return null
  var label = typeof raw.label === "string" ? raw.label.trim() : ""
  var targetEpoch = Number(raw.targetEpoch)
  if (label.length === 0) return null
  if (!isFinite(targetEpoch) || targetEpoch <= 0) return null
  var createdAt = Number(raw.createdAt)
  if (!isFinite(createdAt) || createdAt <= 0) createdAt = Date.now()
  var id = (typeof raw.id === "string" && raw.id.length > 0) ? raw.id : newId(createdAt)
  return { id: id, label: label, targetEpoch: targetEpoch, createdAt: createdAt }
}

// Tolerant: a half-written, empty, or malformed state file degrades to
// "no countdowns" rather than throwing and taking the bar widget down.
function parseState(raw) {
  var state = defaultState()
  if (!raw || raw.length === 0) return state
  try {
    var parsed = JSON.parse(raw)
    if (parsed && Array.isArray(parsed.entries)) {
      state.entries = parsed.entries
        .map(sanitizeEntry)
        .filter(function (e) { return e !== null })
    }
  } catch (e) {
    console.warn("countdown: state parse failed:", e)
  }
  return state
}

// Prepend (newest-first, like the timers plugin). `days` is whole days from
// now; blank labels and day counts below 1 are rejected — the panel disables
// the button too, this is the backstop.
function addEntry(state, label, days, nowMs) {
  var entries = (state && Array.isArray(state.entries)) ? state.entries.slice() : []
  var clean = typeof label === "string" ? label.trim() : ""
  var n = Math.round(Number(days))
  if (clean.length === 0) return { version: 1, entries: entries }
  if (!isFinite(n) || n < 1) return { version: 1, entries: entries }
  var now = isFinite(nowMs) && nowMs > 0 ? Math.floor(nowMs) : Date.now()
  entries.unshift({
    id: newId(now),
    label: clean,
    targetEpoch: targetEpochFor(n, now),
    createdAt: now
  })
  return { version: 1, entries: entries }
}

// Add by an absolute target instant (what the panel's date picker produces)
// rather than a day count. The target is normalised to local midnight and
// must be strictly in the future — today and any past day are rejected, so a
// disabled/expired grid cell that slips through still can't create an entry.
function addEntryAt(state, label, targetEpoch, nowMs) {
  var entries = (state && Array.isArray(state.entries)) ? state.entries.slice() : []
  var clean = typeof label === "string" ? label.trim() : ""
  var t = Number(targetEpoch)
  if (clean.length === 0) return { version: 1, entries: entries }
  if (!isFinite(t) || t <= 0) return { version: 1, entries: entries }
  var now = isFinite(nowMs) && nowMs > 0 ? Math.floor(nowMs) : Date.now()
  var target = startOfLocalDay(t)
  if (target <= startOfLocalDay(now)) return { version: 1, entries: entries }
  entries.unshift({ id: newId(now), label: clean, targetEpoch: target, createdAt: now })
  return { version: 1, entries: entries }
}

function removeEntry(state, id) {
  var entries = (state && Array.isArray(state.entries)) ? state.entries.slice() : []
  return { version: 1, entries: entries.filter(function (e) { return e.id !== id }) }
}

// Edit-in-place backing (see docs/adr/0003): retarget one entry's label,
// leaving its id / targetEpoch / createdAt untouched. A blank label is
// rejected — the state is returned unchanged, matching addEntry's backstop.
function renameEntry(state, id, label) {
  var entries = (state && Array.isArray(state.entries)) ? state.entries.slice() : []
  var clean = typeof label === "string" ? label.trim() : ""
  if (clean.length === 0) return { version: 1, entries: entries }
  return {
    version: 1,
    entries: entries.map(function (e) {
      if (e.id !== id) return e
      return { id: e.id, label: clean, targetEpoch: e.targetEpoch, createdAt: e.createdAt }
    })
  }
}

// Soonest target first; ties broken by most-recently-added first.
function sortedBySoonest(entries) {
  var list = (entries || []).slice()
  list.sort(function (a, b) {
    if (a.targetEpoch !== b.targetEpoch) return a.targetEpoch - b.targetEpoch
    return b.createdAt - a.createdAt
  })
  return list
}

// Human phrasing for a card: "21 days", "Tomorrow", "Today", "3 days ago".
function formatRemaining(days) {
  var n = Math.round(Number(days))
  if (!isFinite(n)) return ""
  if (n === 0) return "Today"
  if (n === 1) return "Tomorrow"
  if (n === -1) return "Yesterday"
  if (n > 1) return n + " days"
  return Math.abs(n) + " days ago"
}
// Minutes until the target instant. Positive values round up so a countdown
// never shows zero while any fraction of a minute remains; past targets round
// down to report fully elapsed minutes.
function minutesRemaining(targetEpoch, nowMs) {
  var target = Number(targetEpoch)
  var now = Number(nowMs)
  if (!isFinite(target) || !isFinite(now)) return NaN
  var delta = (target - now) / 60000
  return delta >= 0 ? Math.ceil(delta) : Math.floor(delta)
}

// Exact-time alternative for the card's day countdown.
function formatMinutesRemaining(minutes) {
  var n = Math.round(Number(minutes))
  if (!isFinite(n)) return ""
  if (n === 0) return "Less than a minute left"
  if (n === 1) return "1 minute left"
  if (n > 1) return n + " minutes left"
  if (n === -1) return "1 minute ago"
  return Math.abs(n) + " minutes ago"
}

// Compact form for the bar marquee: "21d", "0d", "-3d".
function formatShort(days) {
  var n = Math.round(Number(days))
  if (!isFinite(n)) return "?"
  return n + "d"
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var MONTHS_LONG = ["January", "February", "March", "April", "May", "June",
                   "July", "August", "September", "October", "November", "December"]
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function pad2(n) {
  var v = Number(n)
  return (v < 10 ? "0" : "") + v
}

// "Sat 21 Sep 2026"
function formatTarget(targetEpoch) {
  var d = new Date(targetEpoch)
  if (isNaN(d.getTime())) return ""
  return WEEKDAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear()
}

// ---- calendar-grid helpers (the panel's date picker) ------------------
// Days are identified by a "yyyy-MM-dd" key. That format sorts
// lexicographically in chronological order, so "is this day in the future?"
// is a plain string compare against today's key — no Date objects dragged
// through QML bindings.

function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForEpoch(epochMs) {
  var d = new Date(epochMs)
  if (isNaN(d.getTime())) return ""
  return dateKey(d.getFullYear(), d.getMonth(), d.getDate())
}

function todayKey(nowMs) {
  return keyForEpoch(isFinite(nowMs) && nowMs > 0 ? nowMs : Date.now())
}

// Local midnight for a "yyyy-MM-dd" key; 0 for anything that isn't one.
function epochForKey(key) {
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ""))
  if (!m) return 0
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 0, 0, 0, 0).getTime()
}

function stepMonth(year, month, delta) {
  var t = new Date(Number(year), Number(month) + Number(delta), 1)
  return { year: t.getFullYear(), month: t.getMonth() }
}

// 6 rows of 7 { key, year, month, day, inMonth } cells, first column being
// `weekStart` (0=Sun … 6=Sat; the panel uses 1=Mon).
function monthGrid(year, month, weekStart) {
  var start = ((Math.round(Number(weekStart)) % 7) + 7) % 7
  if (!isFinite(start)) start = 1
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var weeks = []
  for (var w = 0; w < 6; w++) {
    var days = []
    for (var d = 0; d < 7; d++) {
      var cy = cursor.getFullYear()
      var cm = cursor.getMonth()
      var cd = cursor.getDate()
      days.push({
        key: dateKey(cy, cm, cd),
        year: cy, month: cm, day: cd,
        inMonth: cm === month && cy === year
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    weeks.push(days)
  }
  return weeks
}

// "September 2026"
function monthLabel(year, month) {
  var m = ((Math.round(Number(month)) % 12) + 12) % 12
  return MONTHS_LONG[m] + " " + year
}

// A "yyyy-MM-dd" key strictly after today — the only days the picker allows.
function isFutureKey(key, nowMs) {
  var k = String(key || "")
  return k.length > 0 && k > todayKey(nowMs)
}

// Whether the month view is already at (or before) the current month, so the
// panel can disable "previous month".
function isCurrentOrPastMonth(viewYear, viewMonth, nowMs) {
  var now = new Date(isFinite(nowMs) && nowMs > 0 ? nowMs : Date.now())
  var vy = Number(viewYear), vm = Number(viewMonth)
  if (vy < now.getFullYear()) return true
  if (vy > now.getFullYear()) return false
  return vm <= now.getMonth()
}

// The scrolling bar text: every countdown, soonest first, as
// "21d · Disneyland" segments joined by a bullet. No leading icon — the
// widget prepends that once.
function marqueeText(entries, nowMs) {
  var list = sortedBySoonest(entries)
  var parts = []
  for (var i = 0; i < list.length; i++) {
    parts.push(formatShort(daysRemaining(list[i].targetEpoch, nowMs)) + " · " + list[i].label)
  }
  return parts.join("      •      ")
}

// One countdown per line, for the widget's hover tooltip.
function listText(entries, nowMs) {
  var list = sortedBySoonest(entries)
  var lines = []
  for (var i = 0; i < list.length; i++) {
    lines.push(formatRemaining(daysRemaining(list[i].targetEpoch, nowMs)) + " — " + list[i].label)
  }
  return lines.join("\n")
}

// Bar label when the marquee isn't showing (no countdowns).
function formatBadge(entries) {
  var list = entries || []
  if (list.length === 0) return "  Countdown"
  return "  " + list.length
}

// Nearest countdown's day count (for IPC status). null when the list is empty.
function soonestDays(entries, nowMs) {
  var list = sortedBySoonest(entries)
  if (list.length === 0) return null
  return daysRemaining(list[0].targetEpoch, nowMs)
}

// ============================================================ self-improvement
// A SEPARATE rolling log of every countdown you've added — written to
// ~/.local/state/omarchy/countdown-history.json, capped — feeds one panel
// feature: your most-used labels as one-tap chips that prefill both the label
// and the day count you last used for it. The active list stays history-free.

var HISTORY_CAP = 200

function defaultHistory() {
  return { version: 1, added: [] }
}

function sanitizeAdd(raw) {
  if (!raw || typeof raw !== "object") return null
  var label = typeof raw.label === "string" ? raw.label.trim() : ""
  if (label.length === 0) return null
  var days = Number(raw.days)
  if (!isFinite(days)) days = 0
  var addedAt = Number(raw.addedAt)
  if (!isFinite(addedAt) || addedAt <= 0) addedAt = Date.now()
  return { label: label, days: Math.round(days), addedAt: addedAt }
}

// Tolerant like parseState. Also swallows the old spoken-countdown plugin's
// unrelated history schema (no `added` array) as "no history yet".
function parseHistory(raw) {
  var history = defaultHistory()
  if (!raw || raw.length === 0) return history
  try {
    var parsed = JSON.parse(raw)
    if (parsed && Array.isArray(parsed.added)) {
      history.added = parsed.added
        .map(sanitizeAdd)
        .filter(function (c) { return c !== null })
        .slice(0, HISTORY_CAP)
    }
  } catch (e) {
    console.warn("countdown: history parse failed:", e)
  }
  return history
}

// Fold one just-added countdown into the log (newest first), capped.
function recordAdd(history, label, days, nowMs) {
  var added = (history && Array.isArray(history.added)) ? history.added.slice() : []
  var clean = typeof label === "string" ? label.trim() : ""
  if (clean.length === 0) return { version: 1, added: added.slice(0, HISTORY_CAP) }
  var now = isFinite(nowMs) && nowMs > 0 ? Math.floor(nowMs) : Date.now()
  var n = Math.round(Number(days))
  added.unshift({ label: clean, days: isFinite(n) ? n : 0, addedAt: now })
  return { version: 1, added: added.slice(0, HISTORY_CAP) }
}

// Drop every remembered add whose label matches `label` (trimmed,
// case-insensitive) — the per-chip × in the panel's "usual labels" row.
// Other remembered labels are kept.
function forgetLabel(history, label) {
  var added = (history && Array.isArray(history.added)) ? history.added.slice() : []
  var target = (typeof label === "string" ? label.trim() : "").toLowerCase()
  if (target.length === 0) return { version: 1, added: added.slice(0, HISTORY_CAP) }
  var kept = added.filter(function (c) {
    return !c || typeof c.label !== "string" || c.label.trim().toLowerCase() !== target
  })
  return { version: 1, added: kept.slice(0, HISTORY_CAP) }
}

// Most-used past labels that aren't already on the active list — occurrence
// count desc, then most-recent use desc. Each carries the day count from its
// most recent use so a chip can prefill both fields.
function rankLabels(added, activeEntries, limit) {
  var list = added || []
  var active = {}
  ;(activeEntries || []).forEach(function (e) {
    if (e && typeof e.label === "string") active[e.label.toLowerCase()] = true
  })

  var stats = {}
  var order = []
  list.forEach(function (c, i) {
    if (!c || typeof c.label !== "string") return
    var key = c.label
    if (!stats[key]) {
      stats[key] = { label: key, count: 0, mostRecentIndex: i, days: c.days }
      order.push(key)
    }
    stats[key].count += 1
    // list is newest-first: the smallest index seen is the most recent use
    if (i < stats[key].mostRecentIndex) {
      stats[key].mostRecentIndex = i
      stats[key].days = c.days
    }
  })

  return order
    .map(function (k) { return stats[k] })
    .filter(function (s) { return !active[s.label.toLowerCase()] })
    .sort(function (a, b) {
      if (b.count !== a.count) return b.count - a.count
      return a.mostRecentIndex - b.mostRecentIndex
    })
    .slice(0, limit || 4)
}

// Exposed only for the node test harness under test/; QML's JS import has no
// `module` global, so this block is a no-op there.
if (typeof module !== "undefined") {
  module.exports = {
    DAY_MS: DAY_MS,
    HISTORY_CAP: HISTORY_CAP,
    defaultState: defaultState,
    startOfLocalDay: startOfLocalDay,
    targetEpochFor: targetEpochFor,
    daysRemaining: daysRemaining,
    minutesRemaining: minutesRemaining,
    newId: newId,
    sanitizeEntry: sanitizeEntry,
    parseState: parseState,
    addEntry: addEntry,
    addEntryAt: addEntryAt,
    removeEntry: removeEntry,
    renameEntry: renameEntry,
    sortedBySoonest: sortedBySoonest,
    pad2: pad2,
    dateKey: dateKey,
    keyForEpoch: keyForEpoch,
    todayKey: todayKey,
    epochForKey: epochForKey,
    stepMonth: stepMonth,
    monthGrid: monthGrid,
    monthLabel: monthLabel,
    isFutureKey: isFutureKey,
    isCurrentOrPastMonth: isCurrentOrPastMonth,
    formatRemaining: formatRemaining,
    formatMinutesRemaining: formatMinutesRemaining,
    formatShort: formatShort,
    formatTarget: formatTarget,
    marqueeText: marqueeText,
    listText: listText,
    formatBadge: formatBadge,
    soonestDays: soonestDays,
    defaultHistory: defaultHistory,
    sanitizeAdd: sanitizeAdd,
    parseHistory: parseHistory,
    recordAdd: recordAdd,
    forgetLabel: forgetLabel,
    rankLabels: rankLabels
  }
}
