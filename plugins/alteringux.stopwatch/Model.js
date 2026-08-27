// Pure helpers for the stopwatch bar overlay. Kept free of QML/Quickshell
// APIs so formatting logic can be reasoned about in isolation.

function formatElapsed(totalSeconds) {
  var s = Math.max(0, Math.floor(totalSeconds))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  var mm = (m < 10 ? "0" : "") + m
  var ss = (sec < 10 ? "0" : "") + sec
  if (h > 0) return h + ":" + mm + ":" + ss
  return mm + ":" + ss
}

// Parses the JSON state written by `omarchy-stopwatch`, e.g.
// {"start_epoch":1755000000,"interval_minutes":5,"label":"Focus"}
// Returns null on empty/invalid content.
function parseState(raw) {
  if (!raw || raw.length === 0) return null
  try {
    var parsed = JSON.parse(raw)
    if (typeof parsed.start_epoch !== "number") return null
    return parsed
  } catch (e) {
    return null
  }
}

// Parses the JSON history blob written by `omarchy-stopwatch`'s cmd_cancel,
// e.g. {"version":1,"sessions":[{"label":"Focus","interval_minutes":5,
// "elapsed_seconds":623,"ended_at":"..."}]}. Always returns a well-formed
// object so callers never need to null-check it.
function parseHistory(raw) {
  var empty = { version: 1, sessions: [] }
  if (!raw || raw.length === 0) return empty
  try {
    var parsed = JSON.parse(raw)
    if (!parsed || !Array.isArray(parsed.sessions)) return empty
    return parsed
  } catch (e) {
    return empty
  }
}

// Average elapsed_seconds across past sessions sharing the same label
// (empty-string label is its own bucket, so unlabeled sessions are only
// compared against other unlabeled sessions). Returns null when there's
// no prior session to compare against.
function historyAverage(history, label) {
  if (!history || !Array.isArray(history.sessions)) return null
  var target = label || ""
  var matches = history.sessions.filter(function(s) { return (s.label || "") === target })
  if (matches.length === 0) return null
  var sum = matches.reduce(function(acc, s) { return acc + (s.elapsed_seconds || 0) }, 0)
  return sum / matches.length
}

// Renders a just-finished session's length against a rolling average as a
// short, value-neutral phrase (shorter isn't framed as "better" since a
// stopwatch is used for both workouts and focus sessions alike).
function formatDelta(currentSeconds, avgSeconds) {
  if (avgSeconds === null || avgSeconds === undefined || avgSeconds <= 0) return ""
  var diff = currentSeconds - avgSeconds
  var pct = Math.round(Math.abs(diff) / avgSeconds * 100)
  if (pct === 0) return "right on your average"
  return pct + "% " + (diff < 0 ? "shorter" : "longer") + " than your average"
}

if (typeof module !== "undefined") {
  module.exports = {
    formatElapsed: formatElapsed,
    parseState: parseState,
    parseHistory: parseHistory,
    historyAverage: historyAverage,
    formatDelta: formatDelta
  }
}
