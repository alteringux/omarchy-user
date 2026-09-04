// Pure logic for the score plugin: config/state defaults, display
// formatting, and the canUndo predicate. State mutation lives in
// ~/.local/bin/omarchy-score (see docs/adr/0006-cli-first-plugins.md).
// Kept free of QML/Quickshell APIs so it can be reasoned about (and tested)
// in isolation. Same conventions as the sibling plugins' Model.js.

// Coerces a possibly-missing/garbled number to a finite value, falling back
// to `fallback`. A corrupt file must never leak NaN into the parsed score.
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

function canUndo(state) {
  return !!(state && Array.isArray(state.history) && state.history.length > 0)
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
    canUndo: canUndo
  }
}
