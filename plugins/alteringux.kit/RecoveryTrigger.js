.pragma library

// Input owners must supply final dispatch outcomes and monotonic milliseconds.
// This policy observes metadata only; it has no command or focus API.
var attemptWindowMs = 4000
var cooldownMs = 30000
var distinctMissesRequired = 3

function createState() {
  return { attempts: [], visible: false, cooldownUntil: 0, lastTime: null, context: null }
}

function clear(state) { state.attempts = [] }

function dismiss(state, now) {
  if (typeof now !== "number" || !isFinite(now)) return
  clear(state)
  state.visible = false
  state.cooldownUntil = now + cooldownMs
  state.lastTime = now
}

function observe(state, event, now) {
  if (typeof now !== "number" || !isFinite(now)) return false
  // Reject a clock discontinuity instead of bypassing dismissal cooldown.
  if (state.lastTime !== null && now < state.lastTime) {
    clear(state)
    return false
  }
  state.lastTime = now
  if (state.context !== event.context) {
    clear(state)
    state.context = event.context
  }
  if (!event.enabled || !event.owned || event.editor || event.composing
      || event.focusLost || event.outcome === "handled" || event.outcome === "unavailable") {
    clear(state)
    return false
  }
  if (state.visible || now < state.cooldownUntil || event.outcome !== "unhandled"
      || !event.commandModifier || event.typing || event.modifierOnly || event.autoRepeat || !event.chord
      || event.pressId === undefined || event.pressId === null) return false
  if (state.attempts.length && now - state.attempts[0].time >= attemptWindowMs) clear(state)
  if (state.attempts.some(function(attempt) {
    return attempt.chord === event.chord || attempt.pressId === event.pressId
  })) return false
  state.attempts.push({ chord: event.chord, pressId: event.pressId, time: now })
  if (state.attempts.length < distinctMissesRequired) return false
  clear(state)
  state.visible = true
  return true
}
