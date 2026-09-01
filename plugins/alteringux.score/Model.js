// Pure logic for the score plugin: config/state defaults, display
// formatting, and the increment/decrement/reset/trim reducers. Kept free of
// QML/Quickshell APIs so it can be reasoned about (and tested) in isolation.
// Same conventions as the sibling plugins' Model.js.

// Coerces a possibly-missing/garbled numeric config field to a finite
// number, falling back to `fallback`. A corrupt config file must never turn
// a reducer's arithmetic into NaN and poison the persisted score.
function num(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function defaultConfig() {
  return {
    initialValue: 0,
    step: 1,
    showIcon: true,
    icon: ""
  }
}

function defaultState() {
  return {
    score: 0,
    history: []
  }
}

// Tolerant parse for score-config.json: unknown/missing keys fall back to the
// default, a malformed file degrades to all-defaults rather than throwing and
// taking the bar widget down. Only keys already present in defaultConfig() are
// adopted from the stored file.
function parseConfig(raw) {
  var parsed = defaultConfig()
  if (!raw || raw.length === 0) return parsed
  try {
    var stored = JSON.parse(raw)
    if (stored && typeof stored === "object") {
      for (var key in parsed) if (stored[key] !== undefined) parsed[key] = stored[key]
    }
  } catch (e) {
    console.warn("score: config parse failed:", e)
  }
  return parsed
}

// Tolerant parse for score-state.json: a half-written or malformed file
// degrades to score 0 / empty history.
function parseState(raw) {
  var parsed = defaultState()
  if (!raw || raw.length === 0) return parsed
  try {
    var stored = JSON.parse(raw)
    if (stored && typeof stored === "object") {
      parsed.score = num(stored.score, 0)
      if (Array.isArray(stored.history)) parsed.history = stored.history
    }
  } catch (e) {
    console.warn("score: state parse failed:", e)
  }
  return parsed
}

function formatScore(score, config) {
  var cfg = config || {}
  if (cfg.showIcon) {
    return (cfg.icon || "") + " " + score
  }
  return String(score)
}

function increment(state, config) {
  var newState = JSON.parse(JSON.stringify(state))
  newState.score = num(newState.score, 0) + num(config.step, 1)
  ;(newState.history || (newState.history = [])).push({
    action: "increment",
    value: num(config.step, 1),
    timestamp: Date.now()
  })
  return newState
}

function decrement(state, config) {
  var newState = JSON.parse(JSON.stringify(state))
  newState.score = num(newState.score, 0) - num(config.step, 1)
  ;(newState.history || (newState.history = [])).push({
    action: "decrement",
    value: num(config.step, 1),
    timestamp: Date.now()
  })
  return newState
}

function reset(state, config) {
  var newState = JSON.parse(JSON.stringify(state))
  var oldScore = num(newState.score, 0)
  newState.score = num(config.initialValue, 0)
  ;(newState.history || (newState.history = [])).push({
    action: "reset",
    from: oldScore,
    to: num(config.initialValue, 0),
    timestamp: Date.now()
  })
  return newState
}

function setScore(state, newScore) {
  var newState = JSON.parse(JSON.stringify(state))
  newState.score = newScore
  return newState
}

// Reverse the most recent history entry and drop it: increment/decrement
// undo their delta, reset restores the pre-reset value. A no-op (state
// cloned unchanged) when there's nothing to undo. Undo walks the log
// backwards — it does not record an "undo" entry of its own.
function undo(state) {
  var newState = JSON.parse(JSON.stringify(state))
  var hist = Array.isArray(newState.history) ? newState.history : (newState.history = [])
  if (hist.length === 0) return newState
  var last = hist[hist.length - 1]
  var score = num(newState.score, 0)
  if (last.action === "increment") score -= num(last.value, 0)
  else if (last.action === "decrement") score += num(last.value, 0)
  else if (last.action === "reset") score = num(last.from, score)
  newState.score = score
  hist.pop()
  return newState
}

function canUndo(state) {
  return !!(state && Array.isArray(state.history) && state.history.length > 0)
}

function trimHistory(state, maxEntries) {
  var newState = JSON.parse(JSON.stringify(state))
  if (newState.history && newState.history.length > maxEntries) {
    newState.history = newState.history.slice(-maxEntries)
  }
  return newState
}

// Exposed only for the Node test harness under test/; QML's JS import
// mechanism has no `module` global, so this is a no-op there.
if (typeof module !== "undefined") {
  module.exports = {
    defaultConfig: defaultConfig,
    defaultState: defaultState,
    parseConfig: parseConfig,
    parseState: parseState,
    formatScore: formatScore,
    increment: increment,
    decrement: decrement,
    reset: reset,
    setScore: setScore,
    undo: undo,
    canUndo: canUndo,
    trimHistory: trimHistory
  }
}
