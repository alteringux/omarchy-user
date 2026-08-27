// Pure helpers for the countdown bar widget. Kept free of QML/Quickshell
// APIs so formatting logic can be reasoned about in isolation.

var MODE_MINUTES = "minutes"
var MODE_SECONDS = "seconds"

function formatRemaining(totalSeconds) {
  var s = Math.max(0, Math.ceil(totalSeconds))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  var mm = (m < 10 ? "0" : "") + m
  var ss = (sec < 10 ? "0" : "") + sec
  if (h > 0) return h + ":" + mm + ":" + ss
  return mm + ":" + ss
}

// Parses the JSON state written by `omarchy-countdown`, e.g.
// {"end_epoch":1755000000,"total_seconds":300,"label":"Overlay test"}
// Returns null on empty/invalid content.
function parseState(raw) {
  if (!raw || raw.length === 0) return null
  try {
    var parsed = JSON.parse(raw)
    if (typeof parsed.end_epoch !== "number") return null
    return parsed
  } catch (e) {
    return null
  }
}

// Whether a chosen duration (minutes for the long mode, seconds for Quick)
// is worth starting. The Quick slider's floor is 0, which isn't a real
// countdown, so it — and anything else non-positive — is rejected here.
function canStart(duration) {
  var n = Number(duration)
  return !isNaN(n) && n >= 1
}

var HISTORY_LIMIT = 200

// Ranks past countdowns by how often each distinct (mode, duration, label)
// combo has been used, most-used first, ties broken by most recent use.
// Used to surface one-tap presets: as usage accumulates, frequent presets
// rise and rarely-used ones fall out of the top `limit` on their own.
function rankPresets(history, limit) {
  if (!Array.isArray(history)) return []
  var counts = {}
  var order = []
  for (var i = 0; i < history.length; i++) {
    var e = history[i]
    if (!e || typeof e.duration !== "number" || !e.mode) continue
    var key = e.mode + "|" + e.duration + "|" + (e.label || "")
    if (!counts[key]) {
      counts[key] = { mode: e.mode, duration: e.duration, label: e.label || "", count: 0, lastUsed: 0 }
      order.push(key)
    }
    counts[key].count += 1
    counts[key].lastUsed = i
  }
  var ranked = order.map(function(k) { return counts[k] })
  ranked.sort(function(a, b) {
    if (b.count !== a.count) return b.count - a.count
    return b.lastUsed - a.lastUsed
  })
  return ranked.slice(0, limit || 4)
}

if (typeof module !== "undefined") {
  module.exports = {
    MODE_MINUTES: MODE_MINUTES,
    MODE_SECONDS: MODE_SECONDS,
    HISTORY_LIMIT: HISTORY_LIMIT,
    formatRemaining: formatRemaining,
    parseState: parseState,
    canStart: canStart,
    rankPresets: rankPresets
  }
}
