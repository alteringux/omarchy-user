// Pure logic for the timers plugin: one flat list of labelled "activity
// timers". Each entry is a label + its creation stamp + a two-part elapsed
// clock:
//   accumulatedMs  frozen elapsed from finished running spans
//   runningSince    epoch-ms the current span started, or 0 when paused
// so elapsed = accumulatedMs + (runningSince ? now - runningSince : 0).
// A legacy entry that only has `createdAt` reads as "running since createdAt",
// i.e. identical elapsed to the old (now - createdAt) model.
//
// Mutations: add (prepend, newest-first), remove (permanent), rename,
// pause / resume. Kept free of QML/Quickshell APIs so it can be tested in
// isolation — same convention as the other alteringux.* plugins.

function defaultState() {
  return { version: 1, entries: [] }
}

// ---- elapsed clock helpers ------------------------------------------------

// The running-span start for an entry, applying the legacy fallback: an
// entry that predates pause/resume has no `runningSince` key and is treated
// as running since `createdAt` (old `now - createdAt` elapsed). An explicit
// `runningSince: 0` means deliberately paused.
function runningSinceOf(entry) {
  if (!entry) return 0
  if (entry.runningSince === undefined || entry.runningSince === null) {
    var c = Number(entry.createdAt)
    return (isFinite(c) && c > 0) ? c : 0
  }
  var rs = Number(entry.runningSince)
  return (isFinite(rs) && rs > 0) ? rs : 0
}

// Elapsed ms for one entry: banked time plus the live span if it's running.
function entryElapsedMs(entry, nowMs) {
  if (!entry) return 0
  var now = isFinite(nowMs) && nowMs > 0 ? nowMs : Date.now()
  var banked = Number(entry.accumulatedMs)
  if (!isFinite(banked) || banked < 0) banked = 0
  var since = runningSinceOf(entry)
  var live = since > 0 ? Math.max(0, now - since) : 0
  return banked + live
}

function isPaused(entry) {
  return runningSinceOf(entry) === 0
}

// Tolerant parse: a half-written, empty, or malformed state file degrades to
// "no timers" rather than throwing and taking the bar widget down with it.
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
    console.warn("timers: state parse failed:", e)
  }
  return state
}

function sanitizeEntry(raw) {
  if (!raw || typeof raw !== "object") return null
  var label = typeof raw.label === "string" ? raw.label.trim() : ""
  var createdAt = Number(raw.createdAt)
  if (label.length === 0) return null
  if (!isFinite(createdAt) || createdAt <= 0) return null
  var id = (typeof raw.id === "string" && raw.id.length > 0) ? raw.id : newId(createdAt)

  var accumulatedMs = Number(raw.accumulatedMs)
  if (!isFinite(accumulatedMs) || accumulatedMs < 0) accumulatedMs = 0

  // Key absent -> legacy entry: running since createdAt (old elapsed model).
  // Key present -> honour it: >0 is a running span start, anything else is
  // paused (0).
  var runningSince
  if (raw.runningSince === undefined || raw.runningSince === null) {
    runningSince = createdAt
  } else {
    var rs = Number(raw.runningSince)
    runningSince = (isFinite(rs) && rs > 0) ? rs : 0
  }

  return { id: id, label: label, createdAt: createdAt, accumulatedMs: accumulatedMs, runningSince: runningSince }
}

function newId(nowMs) {
  var base = isFinite(nowMs) && nowMs > 0 ? Math.floor(nowMs) : Date.now()
  return "t" + base + "-" + Math.random().toString(36).slice(2, 8)
}

// Prepend so the just-added timer shows at the top of the list, right under
// the input. Whitespace-only labels are rejected (state returned unchanged)
// — the panel also disables the button, this is the backstop.
function addEntry(state, label, nowMs) {
  var entries = (state && Array.isArray(state.entries)) ? state.entries.slice() : []
  var clean = typeof label === "string" ? label.trim() : ""
  if (clean.length === 0) return { version: 1, entries: entries }
  var now = isFinite(nowMs) && nowMs > 0 ? Math.floor(nowMs) : Date.now()
  entries.unshift({ id: newId(now), label: clean, createdAt: now, accumulatedMs: 0, runningSince: now })
  return { version: 1, entries: entries }
}

function removeEntry(state, id) {
  var entries = (state && Array.isArray(state.entries)) ? state.entries.slice() : []
  return { version: 1, entries: entries.filter(function (e) { return e.id !== id }) }
}

// Pause one running timer: bank the live span into accumulatedMs and clear
// runningSince. No-op for an already-paused or unknown entry.
function pauseEntry(state, id, nowMs) {
  var entries = (state && Array.isArray(state.entries)) ? state.entries.slice() : []
  var now = isFinite(nowMs) && nowMs > 0 ? Math.floor(nowMs) : Date.now()
  return {
    version: 1,
    entries: entries.map(function (e) {
      if (e.id !== id || isPaused(e)) return e
      return {
        id: e.id, label: e.label, createdAt: e.createdAt,
        accumulatedMs: entryElapsedMs(e, now), runningSince: 0
      }
    })
  }
}

// Resume one paused timer: open a fresh running span from now. No-op for an
// already-running or unknown entry.
function resumeEntry(state, id, nowMs) {
  var entries = (state && Array.isArray(state.entries)) ? state.entries.slice() : []
  var now = isFinite(nowMs) && nowMs > 0 ? Math.floor(nowMs) : Date.now()
  return {
    version: 1,
    entries: entries.map(function (e) {
      if (e.id !== id || !isPaused(e)) return e
      var banked = Number(e.accumulatedMs)
      if (!isFinite(banked) || banked < 0) banked = 0
      return {
        id: e.id, label: e.label, createdAt: e.createdAt,
        accumulatedMs: banked, runningSince: now
      }
    })
  }
}

function togglePause(state, id, nowMs) {
  var entry = null
  var list = (state && Array.isArray(state.entries)) ? state.entries : []
  for (var i = 0; i < list.length; i++) if (list[i].id === id) { entry = list[i]; break }
  if (!entry) return { version: 1, entries: list.slice() }
  return isPaused(entry) ? resumeEntry(state, id, nowMs) : pauseEntry(state, id, nowMs)
}

// Edit-in-place backing (see docs/adr/0003): rename one timer, leaving its id
// and createdAt (and so its elapsed clock) untouched. A blank label is
// rejected — state returned unchanged, matching addEntry's backstop.
function renameEntry(state, id, label) {
  var entries = (state && Array.isArray(state.entries)) ? state.entries.slice() : []
  var clean = typeof label === "string" ? label.trim() : ""
  if (clean.length === 0) return { version: 1, entries: entries }
  return {
    version: 1,
    entries: entries.map(function (e) {
      if (e.id !== id) return e
      return {
        id: e.id, label: clean, createdAt: e.createdAt,
        accumulatedMs: e.accumulatedMs, runningSince: e.runningSince
      }
    })
  }
}

// Adaptive, largest-two-units, seconds only while under a minute:
//   0..59s      -> "42s"
//   1..59m      -> "17m"
//   1h..23h59m  -> "3h 08m"
//   >= 24h      -> "2d 05h"
function formatElapsed(ms) {
  var totalSec = Math.floor((isFinite(ms) && ms > 0 ? ms : 0) / 1000)
  if (totalSec < 60) return totalSec + "s"
  var totalMin = Math.floor(totalSec / 60)
  if (totalMin < 60) return totalMin + "m"
  var totalHr = Math.floor(totalMin / 60)
  var minRem = totalMin % 60
  if (totalHr < 24) return totalHr + "h " + pad2(minRem) + "m"
  var days = Math.floor(totalHr / 24)
  var hrRem = totalHr % 24
  return days + "d " + pad2(hrRem) + "h"
}

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function longestElapsedMs(entries, nowMs) {
  var now = isFinite(nowMs) && nowMs > 0 ? nowMs : Date.now()
  var max = 0
  var list = entries || []
  for (var i = 0; i < list.length; i++) {
    var d = entryElapsedMs(list[i], now)
    if (d > max) max = d
  }
  return max
}

// Bar-widget label: icon + count of running timers, e.g. "⏳ 3". No elapsed
// time on the bar itself — the count-up only lives in the panel cards. Just
// the icon + word when nothing is running.
function formatBadge(entries) {
  var list = entries || []
  if (list.length === 0) return "  Timers"
  var running = 0
  for (var i = 0; i < list.length; i++) if (!isPaused(list[i])) running++
  // Every timer paused -> parenthesise the count so the bar shows nothing
  // is actively ticking.
  if (running === 0) return "(" + list.length + ")"
  // Some (not all) paused -> "running/total", so the badge distinguishes
  // "3 timers, all ticking" from "3 timers, only 2 actually running"
  // without opening the panel.
  if (running < list.length) return "  " + running + "/" + list.length
  return "  " + list.length
}

// ---- "total today" summary (new panel feature) --------------------------

function isSameLocalDay(a, b) {
  var da = new Date(a), db = new Date(b)
  return da.getFullYear() === db.getFullYear()
      && da.getMonth() === db.getMonth()
      && da.getDate() === db.getDate()
}

// Summed elapsed across every active timer right now.
function totalActiveMs(entries, nowMs) {
  var now = isFinite(nowMs) && nowMs > 0 ? nowMs : Date.now()
  var sum = 0
  var list = entries || []
  for (var i = 0; i < list.length; i++) sum += entryElapsedMs(list[i], now)
  return sum
}

// Summed duration of completions that ended earlier today (local calendar).
function completedTodayMs(completed, nowMs) {
  var now = isFinite(nowMs) && nowMs > 0 ? nowMs : Date.now()
  var sum = 0
  var list = completed || []
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if (c && isFinite(c.endedAt) && isSameLocalDay(c.endedAt, now)) {
      var d = Number(c.durationMs)
      if (isFinite(d) && d > 0) sum += d
    }
  }
  return sum
}

// One-line footer summary, e.g. "1h 20m running  .  35m done today". Omits
// a side that is zero; returns "" when there is nothing to show.
function formatTotals(entries, completed, nowMs) {
  var active = totalActiveMs(entries, nowMs)
  var done = completedTodayMs(completed, nowMs)
  var parts = []
  if (active > 0) parts.push(formatElapsed(active) + " running")
  if (done > 0) parts.push(formatElapsed(done) + " done today")
  return parts.join("  \u00b7  ")
}


// ============================================================ self-improvement
// The active list (defaultState / parseState above) is deliberately kept
// history-free. Everything below works off a SEPARATE rolling log of
// completed timers — written to ~/.local/state/omarchy/timers-history.json
// when an entry is removed or cleared — and is pure derivation from it:
//   - rankLabels():  the most-used labels, surfaced as one-tap chips
//   - baselineFor(): a label's typical run time, so the panel can flag a
//                    live timer that has run well past its own norm
// None of this is shown as a history view; it only feeds the two features.

var HISTORY_CAP = 200          // keep the last N completed timers, newest first
var BASELINE_MIN_SAMPLES = 2   // need at least this many completions of a label
var LONG_FACTOR = 1.5          // "running long" = elapsed > median * this

function defaultHistory() {
  return { version: 1, completed: [] }
}

// Same tolerant contract as parseState: a missing/half-written/garbage file
// degrades to "no history yet" rather than throwing.
function parseHistory(raw) {
  var history = defaultHistory()
  if (!raw || raw.length === 0) return history
  try {
    var parsed = JSON.parse(raw)
    if (parsed && Array.isArray(parsed.completed)) {
      history.completed = parsed.completed
        .map(sanitizeCompletion)
        .filter(function (c) { return c !== null })
        .slice(0, HISTORY_CAP)
    }
  } catch (e) {
    console.warn("timers: history parse failed:", e)
  }
  return history
}

function sanitizeCompletion(raw) {
  if (!raw || typeof raw !== "object") return null
  var label = typeof raw.label === "string" ? raw.label.trim() : ""
  var startedAt = Number(raw.startedAt)
  var endedAt = Number(raw.endedAt)
  if (label.length === 0) return null
  if (!isFinite(startedAt) || startedAt <= 0) return null
  if (!isFinite(endedAt) || endedAt <= 0) return null
  var durationMs = Number(raw.durationMs)
  if (!isFinite(durationMs) || durationMs < 0) durationMs = Math.max(0, endedAt - startedAt)
  return { label: label, startedAt: startedAt, endedAt: endedAt, durationMs: durationMs }
}

// Fold one just-removed active entry into the history log (newest first),
// capped at HISTORY_CAP so rankings track recent habits, not all time.
function recordCompletion(history, entry, nowMs) {
  var completed = (history && Array.isArray(history.completed)) ? history.completed.slice() : []
  if (!entry || typeof entry.label !== "string" || entry.label.trim().length === 0) {
    return { version: 1, completed: completed.slice(0, HISTORY_CAP) }
  }
  var now = isFinite(nowMs) && nowMs > 0 ? Math.floor(nowMs) : Date.now()
  var startedAt = Number(entry.createdAt)
  if (!isFinite(startedAt) || startedAt <= 0) startedAt = now
  // Duration is the timer's own elapsed clock (banked + live span), so a
  // timer that spent time paused records the time it actually ran, not the
  // wall-clock gap since it was created.
  completed.unshift({
    label: entry.label.trim(),
    startedAt: startedAt,
    endedAt: now,
    durationMs: entryElapsedMs(entry, now)
  })
  return { version: 1, completed: completed.slice(0, HISTORY_CAP) }
}

// Most-used labels for the one-tap chip row. Labels that already have a live
// timer are dropped (you can still re-type them for a deliberate duplicate).
// Order: occurrence count desc, then most-recent use desc.
function rankLabels(completed, activeEntries, limit) {
  var list = completed || []
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
      stats[key] = { label: key, count: 0, mostRecentIndex: i }
      order.push(key)
    }
    stats[key].count += 1
    // list is newest-first, so the smallest index seen is the most recent use
    if (i < stats[key].mostRecentIndex) stats[key].mostRecentIndex = i
  })

  return order
    .map(function (k) { return stats[k] })
    .filter(function (s) { return !active[s.label.toLowerCase()] })
    .sort(function (a, b) {
      if (b.count !== a.count) return b.count - a.count
      return a.mostRecentIndex - b.mostRecentIndex
    })
    .slice(0, limit || 4)
    .map(function (s) { return s.label })
}

function median(nums) {
  var arr = (nums || []).filter(function (n) { return isFinite(n) }).slice().sort(function (a, b) { return a - b })
  if (arr.length === 0) return 0
  var mid = Math.floor(arr.length / 2)
  return arr.length % 2 === 0 ? (arr[mid - 1] + arr[mid]) / 2 : arr[mid]
}

// A label's typical run time, from past completions of that exact label.
// null until there are at least BASELINE_MIN_SAMPLES of them — no baseline,
// no "running long" styling.
function baselineFor(completed, label) {
  if (!label) return null
  var durations = (completed || [])
    .filter(function (c) { return c && c.label === label && isFinite(c.durationMs) })
    .map(function (c) { return c.durationMs })
  if (durations.length < BASELINE_MIN_SAMPLES) return null
  return { median: median(durations), samples: durations.length }
}

// True when a live timer's elapsed time has run well past its label's norm.
function isRunningLong(elapsedMs, baseline) {
  if (!baseline || !isFinite(baseline.median) || baseline.median <= 0) return false
  return elapsedMs > baseline.median * LONG_FACTOR
}

// Exposed only for the Node test harness under test/; QML's JS import
// mechanism has no `module` global, so this block is a no-op there.
if (typeof module !== "undefined") {
  module.exports = {
    defaultState: defaultState,
    parseState: parseState,
    sanitizeEntry: sanitizeEntry,
    newId: newId,
    entryElapsedMs: entryElapsedMs,
    isPaused: isPaused,
    addEntry: addEntry,
    removeEntry: removeEntry,
    pauseEntry: pauseEntry,
    resumeEntry: resumeEntry,
    togglePause: togglePause,
    renameEntry: renameEntry,
    formatElapsed: formatElapsed,
    longestElapsedMs: longestElapsedMs,
    formatBadge: formatBadge,
    isSameLocalDay: isSameLocalDay,
    totalActiveMs: totalActiveMs,
    completedTodayMs: completedTodayMs,
    formatTotals: formatTotals,
    HISTORY_CAP: HISTORY_CAP,
    BASELINE_MIN_SAMPLES: BASELINE_MIN_SAMPLES,
    LONG_FACTOR: LONG_FACTOR,
    defaultHistory: defaultHistory,
    parseHistory: parseHistory,
    sanitizeCompletion: sanitizeCompletion,
    recordCompletion: recordCompletion,
    rankLabels: rankLabels,
    median: median,
    baselineFor: baselineFor,
    isRunningLong: isRunningLong
  }
}
