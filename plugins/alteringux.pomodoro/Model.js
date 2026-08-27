// Pure logic for the pomodoro plugin: phase state machine, formatting,
// sound-fallback resolution, and stats/streak bookkeeping. Kept free of
// QML/Quickshell APIs so it can be reasoned about (and tested) in isolation.

var PHASE_IDLE = "IDLE"
var PHASE_WORK = "WORK"
var PHASE_SHORT_BREAK = "SHORT_BREAK"
var PHASE_LONG_BREAK = "LONG_BREAK"

var DEFAULT_SOUND = "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga"

var DAILY_HISTORY_DAYS = 90

var SESSION_HISTORY_MAX = 200
var MIN_SESSIONS_FOR_SUGGESTION = 5
var SUGGESTION_LOOKBACK = 8

function defaultConfig() {
  return {
    version: 1,
    workMinutes: 25,
    shortBreakMinutes: 5,
    longBreakMinutes: 15,
    longBreakCycle: 4,
    reminderMinutes: 5,
    sounds: { workStart: "", breakStart: "", longBreakStart: "" }
  }
}

// How often to re-notify the user while a finished phase is sitting
// "ready", waiting for them to start the next one.
function reminderIntervalMs(config) {
  var minutes = (config && config.reminderMinutes !== undefined) ? config.reminderMinutes : 5
  return Math.max(1, minutes) * 60000
}

// Notification shown each time the reminder fires. `phase` is the phase
// that is ready and waiting to be started (i.e. the phase completePhase
// just transitioned into).
function reminderNotification(phase) {
  return {
    summary: phaseIcon(phase) + " " + phaseLabel(phase) + " ready",
    body: "Press Super+Alt+P (or click the bar timer) to start it."
  }
}

function defaultStats() {
  return {
    version: 1,
    streak: 0,
    lastActiveDate: "",
    daily: {}
  }
}

// What phase follows a completion of `currentPhase`, given how many
// pomodoros have completed in this session (before crediting the one that
// just finished) and the configured long-break cadence.
function nextPhase(currentPhase, completedPomodoros, longBreakCycle) {
  if (currentPhase === PHASE_WORK) {
    var cycle = longBreakCycle > 0 ? longBreakCycle : 4
    var justCompleted = completedPomodoros + 1
    return (justCompleted % cycle === 0) ? PHASE_LONG_BREAK : PHASE_SHORT_BREAK
  }
  return PHASE_WORK
}

function phaseDurationMs(phase, config) {
  var minutes
  if (phase === PHASE_WORK) minutes = config.workMinutes
  else if (phase === PHASE_SHORT_BREAK) minutes = config.shortBreakMinutes
  else if (phase === PHASE_LONG_BREAK) minutes = config.longBreakMinutes
  else minutes = 0
  return Math.max(0, minutes) * 60000
}

function formatRemaining(ms) {
  var totalSeconds = Math.max(0, Math.ceil(ms / 1000))
  var minutes = Math.floor(totalSeconds / 60)
  var seconds = totalSeconds % 60
  return (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
}

function phaseLabel(phase) {
  if (phase === PHASE_WORK) return "Work"
  if (phase === PHASE_SHORT_BREAK) return "Short Break"
  if (phase === PHASE_LONG_BREAK) return "Long Break"
  return "Pomodoro"
}

// Shown instead of the phase icon while a finished phase is "ready" and
// waiting on the user, so the bar visibly changes state rather than
// looking identical to a running/paused timer.
function readyIcon() {
  return "⏰"
}

function phaseIcon(phase) {
  if (phase === PHASE_WORK) return "🍅"
  if (phase === PHASE_SHORT_BREAK) return "☕"
  if (phase === PHASE_LONG_BREAK) return "🌙"
  return "🍅"
}

// transitionKey: "workStart" | "breakStart" | "longBreakStart"
function soundForTransition(config, transitionKey) {
  var sounds = (config && config.sounds) || {}
  var configured = sounds[transitionKey]
  return (configured && configured.length > 0) ? configured : DEFAULT_SOUND
}

// argv for playing a sound file without assuming any one player is
// installed: tries mpv, then paplay, then pw-play, then canberra-gtk-play,
// exec'ing the first that resolves. Returned as an execDetached-ready
// array (no shell interpolation of `path` — it's passed as $1).
function soundPlayCommand(path) {
  var script = "command -v mpv >/dev/null 2>&1 && exec mpv --no-video --really-quiet \"$1\"; " +
               "command -v paplay >/dev/null 2>&1 && exec paplay \"$1\"; " +
               "command -v pw-play >/dev/null 2>&1 && exec pw-play \"$1\"; " +
               "exec canberra-gtk-play -f \"$1\""
  return ["sh", "-c", script, "sh", path]
}

function transitionKeyForPhase(phase) {
  if (phase === PHASE_WORK) return "workStart"
  if (phase === PHASE_SHORT_BREAK) return "breakStart"
  if (phase === PHASE_LONG_BREAK) return "longBreakStart"
  return ""
}

function todayDateString(date) {
  var d = date || new Date()
  var y = d.getFullYear()
  var m = d.getMonth() + 1
  var day = d.getDate()
  return y + "-" + (m < 10 ? "0" : "") + m + "-" + (day < 10 ? "0" : "") + day
}

function yesterdayDateString(todayStr) {
  var parts = todayStr.split("-").map(Number)
  var d = new Date(parts[0], parts[1] - 1, parts[2])
  d.setDate(d.getDate() - 1)
  return todayDateString(d)
}

// Increments the streak when today follows the last active day
// consecutively, resets it to 1 on any gap, and leaves it alone if today
// was already recorded (a second pomodoro in the same day doesn't double
// the streak).
function updateStreak(stats, todayStr) {
  if (stats.lastActiveDate === todayStr) return stats.streak
  if (stats.lastActiveDate === yesterdayDateString(todayStr)) return stats.streak + 1
  return 1
}

// Ensures today's bucket exists and trims history beyond the retention
// window so the stats file doesn't grow without bound.
function rollDailyStats(stats, todayStr) {
  if (!stats.daily[todayStr]) stats.daily[todayStr] = { completed: 0, focusedMs: 0 }

  var keys = Object.keys(stats.daily).sort()
  while (keys.length > DAILY_HISTORY_DAYS) {
    delete stats.daily[keys.shift()]
  }
}

function weeklyTotals(stats, todayStr) {
  var keys = Object.keys(stats.daily).sort().slice(-7)
  var completed = 0
  var focusedMs = 0
  for (var i = 0; i < keys.length; i++) {
    completed += stats.daily[keys[i]].completed || 0
    focusedMs += stats.daily[keys[i]].focusedMs || 0
  }
  return { completed: completed, focusedMs: focusedMs }
}

function allTimeFocusedMs(stats) {
  var keys = Object.keys(stats.daily)
  var total = 0
  for (var i = 0; i < keys.length; i++) total += stats.daily[keys[i]].focusedMs || 0
  return total
}

function defaultHistory() {
  return { version: 1, sessions: [] }
}

// Appends one WORK-phase outcome and trims to the retention window. Mutates
// and returns `history` so callers can chain it straight into a save.
function recordWorkSession(history, minutes, completed, date) {
  history.sessions.push({ minutes: minutes, completed: !!completed, date: date || todayDateString() })
  if (history.sessions.length > SESSION_HISTORY_MAX) {
    history.sessions.splice(0, history.sessions.length - SESSION_HISTORY_MAX)
  }
  return history
}

// Looks at the most recent work sessions run at the currently configured
// length and nudges toward a different default when the pattern is
// lopsided: frequent interruptions mean the block is too long; an unbroken
// streak of full completions means there's room to push it longer. Returns
// null when there isn't enough same-length history yet, or the mix is
// balanced enough that no change is warranted.
function suggestedWorkMinutes(history, currentMinutes) {
  var sessions = (history && history.sessions) || []
  var atCurrent = sessions.filter(function(s) { return s.minutes === currentMinutes })
  var recent = atCurrent.slice(-SUGGESTION_LOOKBACK)
  if (recent.length < MIN_SESSIONS_FOR_SUGGESTION) return null

  var completedCount = recent.filter(function(s) { return s.completed }).length
  var rate = completedCount / recent.length

  if (rate < 0.5) return Math.max(10, currentMinutes - 5)
  if (rate === 1) return Math.min(50, currentMinutes + 5)
  return null
}

function formatDuration(ms) {
  var totalMinutes = Math.round(ms / 60000)
  var hours = Math.floor(totalMinutes / 60)
  var minutes = totalMinutes % 60
  if (hours > 0) return hours + "h " + minutes + "m"
  return minutes + "m"
}

// Exposed only for the Node test harness under test/; QML's JS import
// mechanism has no `module` global, so this is a no-op there.
if (typeof module !== "undefined") {
  module.exports = {
    PHASE_IDLE: PHASE_IDLE,
    PHASE_WORK: PHASE_WORK,
    PHASE_SHORT_BREAK: PHASE_SHORT_BREAK,
    PHASE_LONG_BREAK: PHASE_LONG_BREAK,
    defaultConfig: defaultConfig,
    defaultStats: defaultStats,
    defaultHistory: defaultHistory,
    recordWorkSession: recordWorkSession,
    suggestedWorkMinutes: suggestedWorkMinutes,
    nextPhase: nextPhase,
    phaseDurationMs: phaseDurationMs,
    formatRemaining: formatRemaining,
    phaseLabel: phaseLabel,
    phaseIcon: phaseIcon,
    readyIcon: readyIcon,
    soundForTransition: soundForTransition,
    soundPlayCommand: soundPlayCommand,
    transitionKeyForPhase: transitionKeyForPhase,
    todayDateString: todayDateString,
    yesterdayDateString: yesterdayDateString,
    updateStreak: updateStreak,
    rollDailyStats: rollDailyStats,
    weeklyTotals: weeklyTotals,
    allTimeFocusedMs: allTimeFocusedMs,
    formatDuration: formatDuration,
    reminderIntervalMs: reminderIntervalMs,
    reminderNotification: reminderNotification
  }
}
