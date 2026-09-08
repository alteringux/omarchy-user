// Pure logic for the grip plugin: the intrusion decision engine.
//
// Kept free of QML/Quickshell APIs so the daemon's behaviour (when does a
// check-in become due, when does it escalate to a fullscreen takeover, how the
// adaptive cadence bends) can be reasoned about and Node-tested in isolation.
// The bash CLI (omarchy-grip) owns the JSON files and side effects; this module
// is the shared brain both it and the bar widget read from.

var MINUTE = 60000
var HOUR = 60 * MINUTE

var PROMPT_KINDS = ["checkin", "takeover"]
var TASK_SOURCES = ["typed", "routine", "reminder", "agenda", "executive"]

// ── defaults ───────────────────────────────────────────────────────────────

function defaultConfig() {
  return {
    version: 1,
    // Adaptive check-in cadence, in minutes. The engine sits at base, bends
    // down toward min while things are overdue or you keep dismissing, and
    // stretches to max when the wall is clear.
    baseIntervalMin: 20,
    minIntervalMin: 8,
    maxIntervalMin: 45,
    // A task overdue by this many hours escalates the next prompt to a
    // fullscreen takeover.
    overdueTakeoverHours: 2,
    // This many dismissed check-ins in a row escalates too.
    dismissTakeoverStreak: 3,
    // Snooze buttons offered on a prompt, in minutes.
    snoozeMinutes: [15, 60],
    // Daily routine checklist: [{ id, text }]. Regenerated as open tasks each
    // morning by syncRoutines().
    routines: []
  }
}

function defaultState() {
  return {
    version: 1,
    // Off until `omarchy-grip on`. The daemon does nothing while false.
    enabled: false,
    // null | { kind: "checkin" | "takeover", since: <epoch ms> }
    prompt: null,
    // Dismissed check-ins since the last one you actually engaged with.
    dismissStreak: 0,
    // When the last prompt was resolved (acked). The cadence measures from here.
    lastPromptMs: 0,
    // All prompts muted until this wall-clock ms (pause / snooze).
    pauseUntilMs: 0,
    // The day (YYYY-MM-DD) the routine rows were last seeded for.
    routinesDate: ""
  }
}

function defaultTasks() {
  return { version: 1, tasks: [] }
}

// ── tolerant parsing ───────────────────────────────────────────────────────

function coerceNumber(value, fallback) {
  return typeof value === "number" && isFinite(value) ? value : fallback
}

function parseConfig(raw) {
  var parsed = defaultConfig()
  if (!raw || raw.length === 0) return parsed
  var stored
  try {
    stored = JSON.parse(raw)
  } catch (e) {
    return parsed
  }
  if (!stored || typeof stored !== "object" || Array.isArray(stored)) return parsed

  parsed.baseIntervalMin = clampPositive(stored.baseIntervalMin, parsed.baseIntervalMin)
  parsed.minIntervalMin = clampPositive(stored.minIntervalMin, parsed.minIntervalMin)
  parsed.maxIntervalMin = clampPositive(stored.maxIntervalMin, parsed.maxIntervalMin)
  parsed.overdueTakeoverHours = clampPositive(stored.overdueTakeoverHours, parsed.overdueTakeoverHours)
  parsed.dismissTakeoverStreak = Math.max(1, Math.floor(coerceNumber(stored.dismissTakeoverStreak, parsed.dismissTakeoverStreak)))
  if (Array.isArray(stored.snoozeMinutes)) {
    var mins = stored.snoozeMinutes.filter(function (m) { return typeof m === "number" && m > 0 })
    if (mins.length) parsed.snoozeMinutes = mins
  }
  parsed.routines = parseRoutines(stored.routines)

  // Keep the band coherent even if hand-edited into nonsense.
  if (parsed.minIntervalMin > parsed.maxIntervalMin) parsed.maxIntervalMin = parsed.minIntervalMin
  if (parsed.baseIntervalMin < parsed.minIntervalMin) parsed.baseIntervalMin = parsed.minIntervalMin
  if (parsed.baseIntervalMin > parsed.maxIntervalMin) parsed.baseIntervalMin = parsed.maxIntervalMin
  return parsed
}

function clampPositive(value, fallback) {
  var n = coerceNumber(value, fallback)
  return n > 0 ? n : fallback
}

function parseRoutines(value) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    var r = value[i]
    if (!r || typeof r !== "object") continue
    var id = typeof r.id === "string" ? r.id.trim() : ""
    var text = typeof r.text === "string" ? r.text.trim() : ""
    if (!id || !text) continue
    out.push({ id: id, text: text })
  }
  return out
}

function parseState(raw) {
  var parsed = defaultState()
  if (!raw || raw.length === 0) return parsed
  var stored
  try {
    stored = JSON.parse(raw)
  } catch (e) {
    return parsed
  }
  if (!stored || typeof stored !== "object" || Array.isArray(stored)) return parsed

  parsed.enabled = stored.enabled === true
  parsed.dismissStreak = Math.max(0, Math.floor(coerceNumber(stored.dismissStreak, 0)))
  parsed.lastPromptMs = Math.max(0, coerceNumber(stored.lastPromptMs, 0))
  parsed.pauseUntilMs = Math.max(0, coerceNumber(stored.pauseUntilMs, 0))
  parsed.routinesDate = typeof stored.routinesDate === "string" ? stored.routinesDate : ""
  parsed.prompt = parsePrompt(stored.prompt)
  return parsed
}

function parsePrompt(value) {
  if (!value || typeof value !== "object") return null
  if (PROMPT_KINDS.indexOf(value.kind) === -1) return null
  return { kind: value.kind, since: Math.max(0, coerceNumber(value.since, 0)) }
}

function parseTasks(raw) {
  var out = defaultTasks()
  if (!raw || raw.length === 0) return out
  var stored
  try {
    stored = JSON.parse(raw)
  } catch (e) {
    return out
  }
  if (!stored || typeof stored !== "object" || !Array.isArray(stored.tasks)) return out
  out.tasks = normaliseTasks(stored.tasks)
  return out
}

function normaliseTasks(list) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    var t = normaliseTask(list[i])
    if (t) out.push(t)
  }
  return out
}

function normaliseTask(t) {
  if (!t || typeof t !== "object") return null
  var id = typeof t.id === "string" ? t.id : (typeof t.id === "number" ? String(t.id) : "")
  var text = typeof t.text === "string" ? t.text.trim() : ""
  if (!id || !text) return null
  var source = TASK_SOURCES.indexOf(t.source) !== -1 ? t.source : "typed"
  var due = (typeof t.due === "number" && isFinite(t.due)) ? t.due : null
  return {
    id: id,
    text: text,
    source: source,
    due: due,
    hard: t.hard === true || t.hard === 1,
    done: t.done === true,
    created: Math.max(0, coerceNumber(t.created, 0))
  }
}

// ── task queries ───────────────────────────────────────────────────────────

function tasksArray(tasks) {
  return tasks && Array.isArray(tasks.tasks) ? tasks.tasks : []
}

function openTasks(tasks) {
  return tasksArray(tasks).filter(function (t) { return !t.done })
}

function overdueTasks(tasks, now) {
  return openTasks(tasks).filter(function (t) { return t.due != null && t.due <= now })
}

// hard first, then soonest due (a due date beats no due date), then oldest.
function compareTasks(a, b) {
  if (a.hard !== b.hard) return a.hard ? -1 : 1
  var ad = a.due == null ? Infinity : a.due
  var bd = b.due == null ? Infinity : b.due
  if (ad !== bd) return ad - bd
  return a.created - b.created
}

function topTasks(tasks, now, n) {
  var sorted = openTasks(tasks).slice().sort(compareTasks)
  return typeof n === "number" ? sorted.slice(0, n) : sorted
}

// ── adaptive cadence ───────────────────────────────────────────────────────

function nextIntervalMinutes(config, state, tasks, now) {
  var open = openTasks(tasks)
  if (open.length === 0) return config.maxIntervalMin

  var minutes = config.baseIntervalMin
  if (overdueTasks(tasks, now).length > 0) {
    minutes = config.minIntervalMin
  } else if (state.dismissStreak >= 2) {
    // each dismissal past the first shaves 5 minutes off the wait
    minutes = config.baseIntervalMin - (state.dismissStreak - 1) * 5
  }
  return Math.max(config.minIntervalMin, Math.min(config.maxIntervalMin, minutes))
}

function nextIntervalMs(config, state, tasks, now) {
  return nextIntervalMinutes(config, state, tasks, now) * MINUTE
}

// ── escalation ─────────────────────────────────────────────────────────────

// null | "deadline" | "overdue" | "dismissed", in descending order of urgency.
function escalationReason(config, state, tasks, now) {
  var open = openTasks(tasks)

  var deadline = open.some(function (t) { return t.hard && t.due != null && t.due <= now })
  if (deadline) return "deadline"

  var window = config.overdueTakeoverHours * HOUR
  var badlyOverdue = open.some(function (t) { return t.due != null && (now - t.due) >= window })
  if (badlyOverdue) return "overdue"

  if (state.dismissStreak >= config.dismissTakeoverStreak) return "dismissed"

  return null
}

// ── the decision ───────────────────────────────────────────────────────────
//
// Returns { prompt, reason, nextIntervalMs, intervalElapsed }.
//   prompt  null | "checkin" | "takeover"  — what to show now
//   reason  escalation reason when prompt === "takeover", else null
//
// A "deadline" escalation fires a takeover immediately, ignoring the cadence.
// Every other escalation still waits for the (shortened) interval so the
// takeover can't strobe.
function decide(config, state, tasks, now) {
  var interval = nextIntervalMs(config, state, tasks, now)
  var elapsed = (now - state.lastPromptMs) >= interval
  var base = { prompt: null, reason: null, nextIntervalMs: interval, intervalElapsed: elapsed }

  if (!state.enabled) return base
  if (now < state.pauseUntilMs) return base

  // A prompt already on screen is left exactly as it is — no mid-flight upgrade
  // from check-in to takeover, that would yank the surface out from under a
  // click.
  if (state.prompt && PROMPT_KINDS.indexOf(state.prompt.kind) !== -1) {
    base.prompt = state.prompt.kind
    return base
  }

  // Nothing open → nothing to check in about. Stay quiet.
  if (openTasks(tasks).length === 0) return base

  var reason = escalationReason(config, state, tasks, now)

  if (reason === "deadline") {
    base.prompt = "takeover"
    base.reason = "deadline"
    return base
  }

  if (!elapsed) return base

  if (reason) {
    base.prompt = "takeover"
    base.reason = reason
    return base
  }

  base.prompt = "checkin"
  return base
}

// ── mutations (return a fresh object or the input unchanged) ────────────────

function cloneTasks(tasks) {
  return { version: 1, tasks: tasksArray(tasks).map(function (t) { return t }) }
}

function addTask(tasks, input, opts) {
  var text = input && typeof input.text === "string" ? input.text.trim() : ""
  if (!text) return tasks
  opts = opts || {}
  var next = cloneTasks(tasks)
  // grip-cli.js's payload is external input (the bash side hands over whatever
  // it parsed from argv/stdin) — an absent id used to fall through to
  // String(undefined) === "undefined", silently colliding every un-ided task
  // onto the same identity, so complete/drop would match all of them at once.
  var hasId = opts.id !== undefined && opts.id !== null && String(opts.id).length > 0
  var id = hasId ? String(opts.id) : ("task-" + coerceNumber(opts.now, 0) + "-" + next.tasks.length)
  next.tasks = next.tasks.concat([{
    id: id,
    text: text,
    source: "typed",
    due: (input.due != null && isFinite(input.due)) ? input.due : null,
    hard: input.hard === true,
    done: false,
    created: coerceNumber(opts.now, 0)
  }])
  return next
}

function completeTask(tasks, id) {
  var next = cloneTasks(tasks)
  next.tasks = next.tasks.map(function (t) {
    return t.id === id ? Object.assign({}, t, { done: true }) : t
  })
  return next
}

function dropTask(tasks, id) {
  var next = cloneTasks(tasks)
  next.tasks = next.tasks.filter(function (t) { return t.id !== id })
  return next
}

function routineRowId(routineId, dayStr) {
  return "routine:" + routineId + ":" + dayStr
}

// Drop every routine row not belonging to `dayStr`, then ensure exactly one row
// per configured routine for that day — preserving the `done` flag of a row
// that already exists so a mid-day re-sync doesn't un-tick your morning.
function syncRoutines(tasks, config, dayStr) {
  var kept = tasksArray(tasks).filter(function (t) {
    return t.source !== "routine" || t.id.indexOf("routine:") === 0 && endsWith(t.id, ":" + dayStr)
  })
  var byId = {}
  kept.forEach(function (t) { byId[t.id] = t })

  var routines = Array.isArray(config.routines) ? config.routines : []
  var wantedIds = {}
  routines.forEach(function (r) {
    var rowId = routineRowId(r.id, dayStr)
    wantedIds[rowId] = true
    if (!byId[rowId]) {
      kept.push({
        id: rowId,
        text: r.text,
        source: "routine",
        due: null,
        hard: false,
        done: false,
        created: 0
      })
      byId[rowId] = true
    }
  })

  // A routine removed from config loses its row for the day too.
  var pruned = kept.filter(function (t) {
    return t.source !== "routine" || wantedIds[t.id] === true
  })

  return { version: 1, tasks: pruned }
}

function endsWith(str, suffix) {
  return str.length >= suffix.length && str.lastIndexOf(suffix) === (str.length - suffix.length)
}

// ── formatting ─────────────────────────────────────────────────────────────

function formatDue(deltaMs, _now) {
  if (deltaMs == null) return ""
  var future = deltaMs >= 0
  var abs = Math.abs(deltaMs)
  var text
  if (abs < HOUR) {
    text = Math.max(1, Math.round(abs / MINUTE)) + "m"
  } else if (abs < 24 * HOUR) {
    text = Math.round(abs / HOUR) + "h"
  } else {
    text = Math.round(abs / (24 * HOUR)) + "d"
  }
  return future ? ("in " + text) : (text + " overdue")
}

// A compact rollup for the bar widget: counts plus the single loudest tone,
// checked in this priority order:
//   off      → disabled
//   prompt   → a check-in / takeover is pending
//   paused   → prompts muted right now
//   overdue  → something is past due
//   calm     → open tasks, none overdue
//   clear    → nothing open
function summary(tasks, state, now) {
  var open = openTasks(tasks)
  var overdue = overdueTasks(tasks, now)
  var tone
  if (!state.enabled) tone = "off"
  else if (state.prompt) tone = "prompt"
  else if (now < state.pauseUntilMs) tone = "paused"
  else if (overdue.length > 0) tone = "overdue"
  else if (open.length > 0) tone = "calm"
  else tone = "clear"
  return {
    open: open.length,
    overdue: overdue.length,
    tone: tone,
    promptKind: state.prompt ? state.prompt.kind : null
  }
}

// ── exports ────────────────────────────────────────────────────────────────

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    MINUTE: MINUTE,
    HOUR: HOUR,
    PROMPT_KINDS: PROMPT_KINDS,
    TASK_SOURCES: TASK_SOURCES,
    defaultConfig: defaultConfig,
    defaultState: defaultState,
    defaultTasks: defaultTasks,
    parseConfig: parseConfig,
    parseState: parseState,
    parseTasks: parseTasks,
    parseRoutines: parseRoutines,
    openTasks: openTasks,
    overdueTasks: overdueTasks,
    compareTasks: compareTasks,
    topTasks: topTasks,
    nextIntervalMinutes: nextIntervalMinutes,
    nextIntervalMs: nextIntervalMs,
    escalationReason: escalationReason,
    decide: decide,
    addTask: addTask,
    completeTask: completeTask,
    dropTask: dropTask,
    routineRowId: routineRowId,
    syncRoutines: syncRoutines,
    formatDue: formatDue,
    summary: summary
  }
}
