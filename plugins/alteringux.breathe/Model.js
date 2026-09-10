// Pure logic for the breathe plugin: the technique catalogue, the phase state
// machine that turns "milliseconds since the session started" into "which
// breath are we on", the orb-scale envelope both guides animate from, and the
// metrics reducers the panel renders. Kept free of QML/Quickshell APIs so it
// can be reasoned about (and tested) in isolation.
//
// The catalogue below is a verbatim copy of techniques.json. QML's JS import
// mechanism cannot read a file, and ~/.local/bin/omarchy-breathe embeds the
// same array in bash, so the same data necessarily exists three times;
// test/catalogue.test.sh is what stops the copies drifting apart.

var PHASE = {
  INHALE: "INHALE",
  HOLD_IN: "HOLD_IN",
  EXHALE: "EXHALE",
  HOLD_OUT: "HOLD_OUT",
  INHALE_TOP: "INHALE_TOP",
  RETENTION: "RETENTION",
  RECOVERY: "RECOVERY",
  SWITCH: "SWITCH",
  POWER_BREATHS: "POWER_BREATHS"
}

// The orb never fully collapses: an empty-lung hold still needs something on
// screen to look at, and a scale of 0 reads as "the app died" rather than
// "you are holding". 0.32 is small enough to feel empty, big enough to breathe.
var SCALE_MIN = 0.32
var SCALE_MAX = 1.0

// The plugin's own mark, used on the bar, in the panel head and as the phase
// glyph of last resort: U+F087E (lungs) from the Nerd Font symbol range.
// Written as its surrogate pair because a \u escape takes exactly four hex
// digits, so the literal "\uF087E" would silently mean U+F087 followed by "E".
var PLUGIN_GLYPH = "\uDB82\uDC7E"

var DAILY_HISTORY_DAYS = 90
var SESSION_HISTORY_MAX = 300
var MAX_CYCLE_SECONDS = 600

var TECHNIQUES = [
  {
    id: "box",
    name: "Box",
    pattern: "4-4-4-4",
    family: "core",
    tone: "info",
    blurb: "Equal inhale, hold, exhale, hold. The steady one — settles a racing head without making you sleepy.",
    use: "Focus, pre-meeting nerves, resetting mid-task.",
    defaultCycles: 8,
    phases: [
      { kind: "INHALE", seconds: 4, label: "Inhale" },
      { kind: "HOLD_IN", seconds: 4, label: "Hold" },
      { kind: "EXHALE", seconds: 4, label: "Exhale" },
      { kind: "HOLD_OUT", seconds: 4, label: "Hold" }
    ]
  },
  {
    id: "relaxing478",
    name: "4-7-8 Relaxing",
    pattern: "4-7-8",
    family: "core",
    tone: "positive",
    blurb: "A short inhale, a long hold, and a very long exhale. Weighted hard toward the parasympathetic side.",
    use: "Falling asleep, winding down, coming off adrenaline.",
    defaultCycles: 4,
    phases: [
      { kind: "INHALE", seconds: 4, label: "Inhale" },
      { kind: "HOLD_IN", seconds: 7, label: "Hold" },
      { kind: "EXHALE", seconds: 8, label: "Exhale" }
    ]
  },
  {
    id: "coherent",
    name: "Coherent",
    pattern: "5-5",
    family: "core",
    tone: "info",
    blurb: "Six breaths a minute, no holds. Sits near the resonant frequency where heart-rate variability peaks.",
    use: "Long calm stretches, HRV training, background breathing while you work.",
    defaultCycles: 12,
    phases: [
      { kind: "INHALE", seconds: 5, label: "Inhale" },
      { kind: "EXHALE", seconds: 5, label: "Exhale" }
    ]
  },
  {
    id: "physiological-sigh",
    name: "Physiological Sigh",
    pattern: "2+1-6",
    family: "core",
    tone: "positive",
    blurb: "A full inhale, a second sip on top of it, then a long slow release. Reinflates collapsed alveoli and dumps CO2 fast.",
    use: "Acute stress, the fastest way down from a spike. Two or three is often enough.",
    defaultCycles: 5,
    phases: [
      { kind: "INHALE", seconds: 2, label: "Inhale" },
      { kind: "INHALE_TOP", seconds: 1, label: "Sip more" },
      { kind: "EXHALE", seconds: 6, label: "Let it go" }
    ]
  },
  {
    id: "extended-exhale",
    name: "Extended Exhale",
    pattern: "4-8",
    family: "core",
    tone: "positive",
    blurb: "Exhale twice as long as the inhale. The simplest lever on the vagus nerve there is.",
    use: "General downshift when you want no holds and nothing to count wrong.",
    defaultCycles: 10,
    phases: [
      { kind: "INHALE", seconds: 4, label: "Inhale" },
      { kind: "EXHALE", seconds: 8, label: "Exhale" }
    ]
  },
  {
    id: "wim-hof",
    name: "Wim Hof",
    pattern: "30 breaths + hold",
    family: "energising",
    tone: "warning",
    blurb: "Thirty full power breaths, then empty the lungs and hold, then one recovery breath held at the top.",
    use: "Energy, cold exposure, deliberate stress. Never in water, never driving.",
    warning: "Sit or lie down. Lightheadedness is expected; blacking out is not. Never do this in or near water.",
    defaultCycles: 3,
    phases: [
      { kind: "POWER_BREATHS", seconds: 60, label: "Power breaths", breaths: 30 },
      { kind: "RETENTION", seconds: 90, label: "Hold empty" },
      { kind: "INHALE", seconds: 3, label: "Recovery breath" },
      { kind: "RECOVERY", seconds: 15, label: "Hold full" },
      { kind: "EXHALE", seconds: 2, label: "Release" }
    ]
  },
  {
    id: "bellows",
    name: "Bellows",
    pattern: "1-1 rapid",
    family: "energising",
    tone: "warning",
    blurb: "Fast, forceful, equal in and out through the nose. Bhastrika — a stimulant, not a sedative.",
    use: "Waking up, shaking off an afternoon slump.",
    warning: "Stop if you feel dizzy. Not for pregnancy, uncontrolled hypertension, or on a full stomach.",
    amplitude: 0.8,
    defaultCycles: 20,
    phases: [
      { kind: "INHALE", seconds: 1, label: "In" },
      { kind: "EXHALE", seconds: 1, label: "Out" }
    ]
  },
  {
    id: "triangle",
    name: "Triangle",
    pattern: "4-4-4",
    family: "energising",
    tone: "info",
    blurb: "Box breathing minus the bottom hold. Keeps a light forward momentum instead of fully parking.",
    use: "Alert calm — steady but not sleepy.",
    defaultCycles: 10,
    phases: [
      { kind: "INHALE", seconds: 4, label: "Inhale" },
      { kind: "HOLD_IN", seconds: 4, label: "Hold" },
      { kind: "EXHALE", seconds: 4, label: "Exhale" }
    ]
  },
  {
    id: "vortex",
    name: "Vortex",
    pattern: "13-8-5-3-2-1",
    family: "energising",
    tone: "info",
    blurb: "A descending run down the Fibonacci sequence — 13, 8, 5, 3, 2, 1 seconds a breath, each one lighter than the last. The shortening pace does the settling; you just follow it down.",
    use: "Morning practice, clearing a busy head, dropping into a rhythm without counting. Let the short breaths stay light — no need to force them.",
    defaultCycles: 4,
    phases: [
      { kind: "INHALE", seconds: 6.5, label: "Inhale" },
      { kind: "EXHALE", seconds: 6.5, label: "Exhale" },
      { kind: "INHALE", seconds: 4, label: "Inhale" },
      { kind: "EXHALE", seconds: 4, label: "Exhale" },
      { kind: "INHALE", seconds: 2.5, label: "Inhale" },
      { kind: "EXHALE", seconds: 2.5, label: "Exhale" },
      { kind: "INHALE", seconds: 1.5, label: "Inhale" },
      { kind: "EXHALE", seconds: 1.5, label: "Exhale" },
      { kind: "INHALE", seconds: 1, label: "Inhale" },
      { kind: "EXHALE", seconds: 1, label: "Exhale" },
      { kind: "INHALE", seconds: 0.5, label: "Inhale" },
      { kind: "EXHALE", seconds: 0.5, label: "Exhale" }
    ]
  },
  {
    id: "buteyko",
    name: "Buteyko",
    pattern: "3-4-5",
    family: "clinical",
    tone: "neutral",
    blurb: "Deliberately light, reduced breathing with a pause after each exhale. Builds tolerance to CO2 rather than chasing more air.",
    use: "Over-breathing, mouth breathing, air hunger. Breathe less than feels natural.",
    amplitude: 0.55,
    defaultCycles: 10,
    phases: [
      { kind: "INHALE", seconds: 3, label: "Light inhale" },
      { kind: "EXHALE", seconds: 4, label: "Light exhale" },
      { kind: "HOLD_OUT", seconds: 5, label: "Pause" }
    ]
  },
  {
    id: "nadi-shodhana",
    name: "Alternate Nostril",
    pattern: "4-4-4 both sides",
    family: "clinical",
    tone: "neutral",
    blurb: "Nadi Shodhana. Close one nostril, breathe, switch, repeat. One cycle covers both sides.",
    use: "Balancing, pre-meditation, when box breathing feels too mechanical.",
    defaultCycles: 6,
    phases: [
      { kind: "INHALE", seconds: 4, label: "Inhale left" },
      { kind: "HOLD_IN", seconds: 4, label: "Hold" },
      { kind: "EXHALE", seconds: 4, label: "Exhale right" },
      { kind: "SWITCH", seconds: 1, label: "Switch" },
      { kind: "INHALE", seconds: 4, label: "Inhale right" },
      { kind: "HOLD_IN", seconds: 4, label: "Hold" },
      { kind: "EXHALE", seconds: 4, label: "Exhale left" },
      { kind: "SWITCH", seconds: 1, label: "Switch" }
    ]
  },
  {
    id: "pursed-lip",
    name: "Pursed Lip",
    pattern: "2-4",
    family: "clinical",
    tone: "positive",
    blurb: "In through the nose, out slowly through pursed lips as if cooling soup. Keeps the airways open against back-pressure.",
    use: "Breathlessness, recovery after exertion, tight chest.",
    defaultCycles: 12,
    phases: [
      { kind: "INHALE", seconds: 2, label: "Inhale (nose)" },
      { kind: "EXHALE", seconds: 4, label: "Exhale (pursed)" }
    ]
  }
]

// ── small helpers ──────────────────────────────────────────────────────────

function clamp(n, lo, hi) { return n < lo ? lo : (n > hi ? hi : n) }

function isFiniteNumber(n) { return typeof n === "number" && isFinite(n) }

function num(value, fallback) {
  var n = Number(value)
  return isFiniteNumber(n) ? n : fallback
}

function copy(value) {
  try { return JSON.parse(JSON.stringify(value)) } catch (e) { return value }
}

function slugify(text) {
  return String(text || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
}

// ── catalogue ──────────────────────────────────────────────────────────────

// A phase's duration is authoritative in seconds; everything downstream works
// in milliseconds, so convert once here rather than at every call site.
function phaseMs(phase) {
  return Math.max(0, num(phase && phase.seconds, 0)) * 1000
}

function cycleSeconds(technique) {
  if (!technique || !technique.phases) return 0
  var total = 0
  for (var i = 0; i < technique.phases.length; i++) total += Math.max(0, num(technique.phases[i].seconds, 0))
  return total
}

function sessionSeconds(technique, cycles) {
  return cycleSeconds(technique) * Math.max(0, num(cycles, 0))
}

function allTechniques(config) {
  var customs = (config && config.customTechniques) ? config.customTechniques : []
  if (!customs || !customs.length) return TECHNIQUES.slice()
  var out = TECHNIQUES.slice()
  for (var i = 0; i < customs.length; i++) {
    if (customs[i] && customs[i].id) out.push(customs[i])
  }
  return out
}

function techniqueById(id, config) {
  var all = allTechniques(config)
  for (var i = 0; i < all.length; i++) if (all[i].id === id) return all[i]
  return null
}

function isBuiltIn(id) {
  for (var i = 0; i < TECHNIQUES.length; i++) if (TECHNIQUES[i].id === id) return true
  return false
}

// Fallback wording when a phase carries no label of its own. Every built-in
// phase does, so this only fires for a hand-edited or custom technique.
function phaseLabel(kind) {
  switch (kind) {
    case PHASE.INHALE: return "Inhale"
    case PHASE.HOLD_IN: return "Hold"
    case PHASE.EXHALE: return "Exhale"
    case PHASE.HOLD_OUT: return "Hold"
    case PHASE.INHALE_TOP: return "Sip more"
    case PHASE.RETENTION: return "Hold empty"
    case PHASE.RECOVERY: return "Hold full"
    case PHASE.SWITCH: return "Switch"
    case PHASE.POWER_BREATHS: return "Power breaths"
    default: return "Breathe"
  }
}

function phaseGlyph(kind) {
  switch (kind) {
    case PHASE.INHALE: return ""        // arrow up — drawing in
    case PHASE.INHALE_TOP: return ""    // double arrow up — the sip on top
    case PHASE.EXHALE: return ""        // arrow down — letting go
    case PHASE.HOLD_IN: return ""       // pause — held full
    case PHASE.HOLD_OUT: return ""
    case PHASE.RETENTION: return ""     // pause circle — the long empty hold
    case PHASE.RECOVERY: return ""
    case PHASE.SWITCH: return ""        // exchange — change nostril
    case PHASE.POWER_BREATHS: return "" // bolt — the fast block
    default: return PLUGIN_GLYPH
  }
}

// A phase whose whole point is that nothing moves. The guides count UP through
// these instead of down, because during a hold the interesting quantity is how
// long you have lasted, not how long is left.
function isHold(kind) {
  return kind === PHASE.HOLD_IN || kind === PHASE.HOLD_OUT
    || kind === PHASE.RETENTION || kind === PHASE.RECOVERY
}

// ── the orb-scale envelope ─────────────────────────────────────────────────
//
// Both guides animate one number: how big the orb is, 0.32 .. 1.0. Getting it
// right needs more than the current phase's kind — a plain "INHALE rises to
// 1.0" rule tears at two seams:
//
//   * the physiological sigh inhales, then sips MORE on top. If the first
//     inhale already reached 1.0 the sip would have to jump backwards to have
//     anywhere to rise from.
//   * Wim Hof ends a round holding a full breath and begins the next one
//     empty, so the orb must actually be walked back down in between.
//
// So the envelope is computed per technique, once: every phase gets an
// explicit `from` and `to`, where `from` is simply the previous phase's `to`
// (wrapping, so the last phase hands off to the first). Continuity is then
// true by construction rather than by careful per-kind arithmetic, and
// scaleEnvelope() is the single place that knows the shape of a breath.
//
// `amplitude` scales how far a technique swells at all — Buteyko's entire
// premise is breathing LESS than feels natural, so rendering it at the same
// full sweep as a Wim Hof power breath would teach the wrong thing.

function peakScale(technique) {
  var amplitude = clamp(num(technique && technique.amplitude, 1), 0.2, 1)
  return SCALE_MIN + (SCALE_MAX - SCALE_MIN) * amplitude
}

// Where a phase leaves the orb. Holds and switches park wherever they arrived,
// which is what makes them holds.
function phaseTargetScale(kind, nextKind, arriving, peak) {
  switch (kind) {
    case PHASE.INHALE:
      // Stop short when a sip follows, so the sip has headroom to rise into.
      return nextKind === PHASE.INHALE_TOP ? arriving + (peak - arriving) * 0.78 : peak
    case PHASE.INHALE_TOP: return peak
    case PHASE.EXHALE: return SCALE_MIN
    case PHASE.POWER_BREATHS: return SCALE_MIN
    default: return arriving
  }
}

// Per-phase { from, to, kind, breaths } for one cycle of a technique.
function scaleEnvelope(technique) {
  var phases = (technique && technique.phases) ? technique.phases : []
  if (!phases.length) return []
  var peak = peakScale(technique)

  // Two passes: the first settles on a resting point to start from, the second
  // is the envelope proper. Starting both passes from SCALE_MIN and letting the
  // first one run the cycle once means a technique that never fully exhales
  // (a pure hold pattern, say) still opens where it will later loop back to.
  var cursor = SCALE_MIN
  var pass, i
  for (pass = 0; pass < 2; pass++) {
    var envelope = []
    for (i = 0; i < phases.length; i++) {
      var kind = phases[i].kind
      var nextKind = phases[(i + 1) % phases.length].kind
      var to = phaseTargetScale(kind, nextKind, cursor, peak)
      envelope.push({
        kind: kind,
        from: cursor,
        to: to,
        breaths: Math.max(1, Math.round(num(phases[i].breaths, 1)))
      })
      cursor = to
    }
    if (pass === 1) return envelope
  }
  return []
}

// Ease in and out of a swell rather than moving linearly: real breath has no
// constant velocity, and a linear ramp is the single thing that makes a
// breathing animation feel mechanical.
function easeInOutSine(f) { return 0.5 - 0.5 * Math.cos(Math.PI * clamp(f, 0, 1)) }

function easeOutSine(f) { return Math.sin(clamp(f, 0, 1) * Math.PI / 2) }

// The orb radius for a position inside one phase of one technique, 0.32 .. 1.0.
// This is the ONLY easing source: the fullscreen guide and the compact panel
// guide both call it, which is what keeps them breathing in lockstep instead
// of drifting apart as two hand-tuned animations.
function orbScale(technique, phaseIndex, phaseFraction) {
  var envelope = scaleEnvelope(technique)
  if (!envelope.length) return SCALE_MIN
  var seg = envelope[clamp(Math.floor(num(phaseIndex, 0)), 0, envelope.length - 1)]
  var f = clamp(num(phaseFraction, 0), 0, 1)

  if (seg.kind === PHASE.POWER_BREATHS) {
    // Rapid oscillation: one full swell per breath, `breaths` of them across
    // the phase. Starts and ends empty so it meets its neighbours cleanly.
    var within = (f * seg.breaths) % 1
    return SCALE_MIN + (peakScale(technique) - SCALE_MIN) * (0.5 - 0.5 * Math.cos(2 * Math.PI * within))
  }

  if (seg.from === seg.to) return seg.from   // a hold, a switch — nothing moves
  var eased = seg.kind === PHASE.INHALE_TOP ? easeOutSine(f) : easeInOutSine(f)
  return seg.from + (seg.to - seg.from) * eased
}

// ── session position ───────────────────────────────────────────────────────

function defaultSession() {
  return {
    version: 1,
    state: "IDLE",
    techniqueId: "",
    cycles: 0,
    sessionId: "",
    startedAtMs: 0,
    savedAtMs: 0,
    elapsedMs: 0,
    silent: false,
    // Keep restarting the same technique when a pass finishes, until the
    // captain stops it. Set from --loop or the config default at start.
    loop: false,
    // Milliseconds jumped past by "skip a hold". Banked here so crediting can
    // subtract time that was skipped rather than breathed.
    skipMs: 0
  }
}

function parseSession(raw) {
  var parsed = defaultSession()
  if (!raw || !raw.length) return parsed
  try {
    var stored = JSON.parse(raw)
    if (stored && typeof stored === "object") {
      for (var key in parsed) if (stored[key] !== undefined) parsed[key] = stored[key]
    }
  } catch (e) { /* keep defaults — a torn write must not take the bar down */ }
  parsed.elapsedMs = Math.max(0, num(parsed.elapsedMs, 0))
  parsed.skipMs = Math.max(0, num(parsed.skipMs, 0))
  parsed.loop = parsed.loop === true
  parsed.cycles = Math.max(0, Math.round(num(parsed.cycles, 0)))
  return parsed
}

// How far into the session we are right now. A RUNNING session keeps counting
// from the daemon's last heartbeat write; a PAUSED one is frozen exactly where
// it stopped. This is why the widget never needs a per-frame write from the CLI.
function effectiveElapsedMs(session, nowMs) {
  if (!session) return 0
  var base = Math.max(0, num(session.elapsedMs, 0))
  if (session.state !== "RUNNING") return base
  var since = num(nowMs, 0) - num(session.savedAtMs, 0)
  return base + Math.max(0, since)
}

function restingResolve(technique) {
  var phases = (technique && technique.phases) ? technique.phases : []
  var first = phases.length ? phases[0] : null
  return {
    phaseIndex: 0,
    phase: first,
    phaseKind: first ? first.kind : PHASE.INHALE,
    phaseLabel: first ? (first.label || phaseLabel(first.kind)) : phaseLabel(PHASE.INHALE),
    phaseElapsedMs: 0,
    phaseDurationMs: first ? phaseMs(first) : 0,
    phaseRemainingMs: first ? phaseMs(first) : 0,
    phaseFraction: 0,
    isHold: first ? isHold(first.kind) : false,
    cycleIndex: 0,
    cycleCount: 0,
    sessionElapsedMs: 0,
    sessionDurationMs: 0,
    sessionFraction: 0,
    breathIndex: null,
    breathCount: null,
    orbScale: technique ? orbScale(technique, 0, 0) : SCALE_MIN,
    done: false
  }
}

// Map elapsed milliseconds onto the repeating phase list. Total and pure: any
// combination of missing technique, zero-length cycle, past-the-end position
// or paused session lands on a sane shape rather than throwing or returning
// NaN into a QML binding (where it would silently blank the whole panel).
function resolve(session, technique, nowMs) {
  if (!technique || !technique.phases || !technique.phases.length) return restingResolve(technique)

  var phases = technique.phases
  var cycleMs = cycleSeconds(technique) * 1000
  var cycleCount = Math.max(1, Math.round(num(session && session.cycles, 0) || num(technique.defaultCycles, 1)))
  var sessionDurationMs = cycleMs * cycleCount

  if (!session || session.state === "IDLE" || cycleMs <= 0) {
    var resting = restingResolve(technique)
    resting.cycleCount = cycleCount
    resting.sessionDurationMs = sessionDurationMs
    return resting
  }

  var elapsed = effectiveElapsedMs(session, nowMs)
  var done = elapsed >= sessionDurationMs

  // Clamp a finished session a hair inside its last phase rather than at the
  // exact boundary: landing on sessionDurationMs itself would wrap round to
  // cycle 0 phase 0 and show a completed session as if it were starting over.
  var position = done ? Math.max(0, sessionDurationMs - 1) : elapsed

  var cycleIndex = Math.floor(position / cycleMs)
  var intoCycle = position - cycleIndex * cycleMs

  var phaseIndex = 0
  var phaseStart = 0
  for (var i = 0; i < phases.length; i++) {
    var span = phaseMs(phases[i])
    if (intoCycle < phaseStart + span || i === phases.length - 1) { phaseIndex = i; break }
    phaseStart += span
  }

  var phase = phases[phaseIndex]
  var phaseDurationMs = phaseMs(phase)
  var phaseElapsedMs = clamp(intoCycle - phaseStart, 0, phaseDurationMs)
  var phaseFraction = phaseDurationMs > 0 ? phaseElapsedMs / phaseDurationMs : 1

  var breathCount = phase.kind === PHASE.POWER_BREATHS
    ? Math.max(1, Math.round(num(phase.breaths, 1))) : null
  var breathIndex = breathCount === null ? null
    : clamp(Math.floor(phaseFraction * breathCount), 0, breathCount - 1)

  return {
    phaseIndex: phaseIndex,
    phase: phase,
    phaseKind: phase.kind,
    phaseLabel: phase.label || phaseLabel(phase.kind),
    phaseElapsedMs: phaseElapsedMs,
    phaseDurationMs: phaseDurationMs,
    phaseRemainingMs: Math.max(0, phaseDurationMs - phaseElapsedMs),
    phaseFraction: phaseFraction,
    isHold: isHold(phase.kind),
    cycleIndex: clamp(cycleIndex, 0, cycleCount - 1),
    cycleCount: cycleCount,
    sessionElapsedMs: Math.min(elapsed, sessionDurationMs),
    sessionDurationMs: sessionDurationMs,
    sessionFraction: sessionDurationMs > 0 ? clamp(elapsed / sessionDurationMs, 0, 1) : 0,
    breathIndex: breathIndex,
    breathCount: breathCount,
    orbScale: orbScale(technique, phaseIndex, phaseFraction),
    done: done
  }
}

// ── formatting ─────────────────────────────────────────────────────────────

// A phase countdown reads as a bare number of seconds ("4"), because that is
// how the count is actually spoken while breathing. Anything a minute or over
// gets a clock, which in practice only happens on a long retention.
function formatClock(ms) {
  var totalSeconds = Math.max(0, Math.ceil(num(ms, 0) / 1000))
  if (totalSeconds < 60) return String(totalSeconds)
  var minutes = Math.floor(totalSeconds / 60)
  var seconds = totalSeconds % 60
  return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
}

function formatDuration(seconds) {
  var total = Math.max(0, Math.round(num(seconds, 0)))
  if (total < 60) return total + " sec"
  var minutes = Math.round(total / 60)
  if (minutes < 60) return minutes + " min"
  var hours = Math.floor(minutes / 60)
  var rest = minutes % 60
  return rest === 0 ? hours + " h" : hours + " h " + rest + " min"
}

// ── custom techniques ──────────────────────────────────────────────────────

var VALID_TONES = ["neutral", "info", "positive", "warning", "negative"]

// Validate a user-authored pattern from the builder. Errors are phrased for a
// human reading them next to the field they broke, not for a log.
function validateCustom(candidate) {
  var errors = []
  var source = (candidate && typeof candidate === "object") ? candidate : {}

  var name = String(source.name || "").trim()
  if (!name.length) errors.push("Give the pattern a name.")
  if (name.length > 40) errors.push("That name is too long — keep it under 40 characters.")

  var phases = []
  var rawPhases = source.phases && source.phases.length ? source.phases : []
  if (!rawPhases.length) errors.push("Add at least one phase.")

  for (var i = 0; i < rawPhases.length; i++) {
    var raw = rawPhases[i] || {}
    var kind = raw.kind
    if (!PHASE[kind]) {
      errors.push("Phase " + (i + 1) + " has an unknown kind.")
      continue
    }
    var seconds = num(raw.seconds, 0)
    if (seconds <= 0) {
      errors.push("Phase " + (i + 1) + " needs a duration above zero.")
      continue
    }
    var entry = { kind: kind, seconds: Math.round(seconds * 10) / 10, label: String(raw.label || phaseLabel(kind)) }
    if (kind === PHASE.POWER_BREATHS) entry.breaths = Math.max(1, Math.round(num(raw.breaths, 30)))
    phases.push(entry)
  }

  var total = 0
  for (var j = 0; j < phases.length; j++) total += phases[j].seconds
  if (phases.length && total > MAX_CYCLE_SECONDS) {
    errors.push("One cycle is " + formatDuration(total) + " — keep it under " + formatDuration(MAX_CYCLE_SECONDS) + ".")
  }

  // An id is derived from the name, so a name that collides with a built-in is
  // reported against the name — the field the user can actually fix.
  var id = String(source.id || "").length ? String(source.id) : "custom-" + slugify(name)
  if (isBuiltIn(id)) errors.push("That name collides with a built-in technique — pick another.")
  if (!slugify(name).length && name.length) errors.push("That name needs at least one letter or number.")

  var tone = VALID_TONES.indexOf(source.tone) >= 0 ? source.tone : "neutral"
  var cycles = Math.max(1, Math.round(num(source.defaultCycles, 8)))

  var technique = {
    id: id,
    name: name,
    pattern: phases.length ? phases.map(function (p) { return String(p.seconds) }).join("-") : "",
    family: "custom",
    tone: tone,
    blurb: String(source.blurb || ""),
    use: String(source.use || ""),
    defaultCycles: cycles,
    phases: phases
  }
  if (isFiniteNumber(source.amplitude)) technique.amplitude = clamp(source.amplitude, 0.2, 1)

  return { ok: errors.length === 0, errors: errors, technique: technique }
}

// ── config ─────────────────────────────────────────────────────────────────

function defaultConfig() {
  return {
    version: 1,
    defaultTechniqueId: "box",
    defaultCycles: 8,
    silent: false,
    loop: false,
    phaseSound: "",
    endSound: "",
    notifyOnEnd: true,
    overlayOnStart: true,
    overlayDim: 0.82,
    reduceMotion: false,
    showBarCountdown: true,
    nudge: {
      enabled: false,
      everyMinutes: 90,
      quietFrom: "22:00",
      quietTo: "08:00",
      techniqueId: "physiological-sigh"
    },
    customTechniques: []
  }
}

// Tolerant parse: adopts only keys already present in defaultConfig(), so an
// older or hand-mangled file keeps whatever is still valid instead of being
// discarded wholesale. `nudge` is merged key-by-key rather than taken whole so
// a file written before a nudge field existed still gains its default.
function parseConfig(raw) {
  var parsed = defaultConfig()
  if (!raw || !raw.length) return parsed
  try {
    var stored = JSON.parse(raw)
    if (stored && typeof stored === "object") {
      for (var key in parsed) {
        if (stored[key] === undefined) continue
        if (key === "nudge") {
          if (stored.nudge && typeof stored.nudge === "object") {
            for (var nk in parsed.nudge) if (stored.nudge[nk] !== undefined) parsed.nudge[nk] = stored.nudge[nk]
          }
        } else {
          parsed[key] = stored[key]
        }
      }
    }
  } catch (e) { /* keep defaults */ }

  if (!parsed.customTechniques || !parsed.customTechniques.length) parsed.customTechniques = []
  parsed.loop = parsed.loop === true
  parsed.overlayDim = clamp(num(parsed.overlayDim, 0.82), 0, 1)
  parsed.defaultCycles = Math.max(1, Math.round(num(parsed.defaultCycles, 8)))
  return parsed
}

function serializeConfig(config) {
  return JSON.stringify(config, null, 2) + "\n"
}

// ── stats and history ──────────────────────────────────────────────────────

function defaultStats() {
  return {
    version: 1,
    streak: 0,
    bestStreak: 0,
    lastActiveDate: "",
    daily: {},
    totals: { sessions: 0, seconds: 0, cycles: 0 }
  }
}

function parseStats(raw) {
  var parsed = defaultStats()
  if (!raw || !raw.length) return parsed
  try {
    var stored = JSON.parse(raw)
    if (stored && typeof stored === "object") {
      for (var key in parsed) if (stored[key] !== undefined) parsed[key] = stored[key]
    }
  } catch (e) { /* keep defaults */ }
  if (!parsed.daily || typeof parsed.daily !== "object") parsed.daily = {}
  if (!parsed.totals || typeof parsed.totals !== "object") parsed.totals = { sessions: 0, seconds: 0, cycles: 0 }
  return parsed
}

function defaultHistory() {
  return { version: 1, sessions: [] }
}

function parseHistory(raw) {
  var parsed = defaultHistory()
  if (!raw || !raw.length) return parsed
  try {
    var stored = JSON.parse(raw)
    if (stored && typeof stored === "object" && stored.sessions && stored.sessions.length) {
      parsed.sessions = stored.sessions
      if (stored.version !== undefined) parsed.version = stored.version
    }
  } catch (e) { /* keep defaults */ }
  if (!parsed.sessions || !parsed.sessions.length) parsed.sessions = []
  return parsed
}

// A history record written by a torn or hand-edited file can be missing
// anything; every reducer runs through this rather than trusting a record.
function usableSession(entry) {
  if (!entry || typeof entry !== "object") return null
  var startedAtMs = num(entry.startedAtMs, 0)
  if (startedAtMs <= 0) return null
  return {
    id: String(entry.id || ""),
    techniqueId: String(entry.techniqueId || ""),
    startedAtMs: startedAtMs,
    seconds: Math.max(0, num(entry.seconds, 0)),
    cycles: Math.max(0, num(entry.cycles, 0)),
    plannedCycles: Math.max(0, num(entry.plannedCycles, 0)),
    completed: entry.completed === true
  }
}

function dateStringOf(ms) {
  var d = new Date(num(ms, 0))
  var month = d.getMonth() + 1
  var day = d.getDate()
  return d.getFullYear() + "-" + (month < 10 ? "0" : "") + month + "-" + (day < 10 ? "0" : "") + day
}

function todayDateString(nowMs) {
  return dateStringOf(isFiniteNumber(nowMs) ? nowMs : Date.now())
}

// ── metrics reducers ───────────────────────────────────────────────────────

// A dense oldest-first window, zero days included: the panel draws a bar per
// day and a sparse map would silently compress a gap into looking like a
// streak.
function dailyBuckets(stats, days, nowMs) {
  var parsed = (stats && stats.daily) ? stats : defaultStats()
  var span = Math.max(1, Math.round(num(days, 7)))
  var now = isFiniteNumber(nowMs) ? nowMs : Date.now()
  var out = []
  for (var i = span - 1; i >= 0; i--) {
    var date = dateStringOf(now - i * 86400000)
    var bucket = parsed.daily[date]
    out.push({
      date: date,
      sessions: Math.max(0, num(bucket && bucket.sessions, 0)),
      seconds: Math.max(0, num(bucket && bucket.seconds, 0)),
      cycles: Math.max(0, num(bucket && bucket.cycles, 0))
    })
  }
  return out
}

function streakOf(stats) {
  var parsed = stats ? stats : defaultStats()
  var current = Math.max(0, Math.round(num(parsed.streak, 0)))
  var best = Math.max(0, Math.round(num(parsed.bestStreak, 0)))
  return { current: current, best: Math.max(best, current) }
}

function totals(stats) {
  var t = (stats && stats.totals) ? stats.totals : null
  return {
    sessions: Math.max(0, num(t && t.sessions, 0)),
    seconds: Math.max(0, num(t && t.seconds, 0)),
    cycles: Math.max(0, num(t && t.cycles, 0))
  }
}

function sessionsWithin(history, days, nowMs) {
  var parsed = (history && history.sessions) ? history : defaultHistory()
  var now = isFiniteNumber(nowMs) ? nowMs : Date.now()
  var span = Math.max(1, Math.round(num(days, 30)))
  var cutoff = now - span * 86400000
  var out = []
  for (var i = 0; i < parsed.sessions.length; i++) {
    var entry = usableSession(parsed.sessions[i])
    if (entry && entry.startedAtMs >= cutoff && entry.startedAtMs <= now) out.push(entry)
  }
  return out
}

function techniqueBreakdown(history, days, nowMs, config) {
  var sessions = sessionsWithin(history, days, nowMs)
  var byId = {}
  var totalSeconds = 0
  for (var i = 0; i < sessions.length; i++) {
    var entry = sessions[i]
    if (!byId[entry.techniqueId]) byId[entry.techniqueId] = { id: entry.techniqueId, sessions: 0, seconds: 0 }
    byId[entry.techniqueId].sessions += 1
    byId[entry.techniqueId].seconds += entry.seconds
    totalSeconds += entry.seconds
  }
  var out = []
  for (var id in byId) {
    var technique = techniqueById(id, config)
    out.push({
      id: id,
      name: technique ? technique.name : id,
      tone: technique ? technique.tone : "neutral",
      sessions: byId[id].sessions,
      seconds: byId[id].seconds,
      pct: totalSeconds > 0 ? byId[id].seconds / totalSeconds : 0
    })
  }
  out.sort(function (a, b) { return b.seconds - a.seconds })
  return out
}

// 24 buckets by local hour of day: answers "when do I actually do this", which
// is the question that turns a nudge schedule from a guess into a decision.
function hourHeatmap(history, days, nowMs) {
  var sessions = sessionsWithin(history, days, nowMs)
  var out = []
  for (var h = 0; h < 24; h++) out.push(0)
  for (var i = 0; i < sessions.length; i++) {
    var hour = new Date(sessions[i].startedAtMs).getHours()
    if (hour >= 0 && hour < 24) out[hour] += 1
  }
  return out
}

function completionRate(history, days, nowMs) {
  var sessions = sessionsWithin(history, days, nowMs)
  var completed = 0
  for (var i = 0; i < sessions.length; i++) if (sessions[i].completed) completed += 1
  var abandoned = sessions.length - completed
  return {
    completed: completed,
    abandoned: abandoned,
    total: sessions.length,
    pct: sessions.length > 0 ? completed / sessions.length : 0
  }
}

// A hint, never enforcement: the panel shows it as something to act on or
// ignore. Returns null rather than reaching for a weak signal, because a
// suggestion that fires on two data points stops being worth reading.
function suggestTechnique(history, stats, nowMs, config) {
  var now = isFiniteNumber(nowMs) ? nowMs : Date.now()
  var recent = sessionsWithin(history, 14, now)
  if (recent.length < 4) return null

  var hour = new Date(now).getHours()

  // Late enough that the relaxing pattern is the obviously right tool, and it
  // is not already what you reach for.
  if (hour >= 21 || hour < 5) {
    var usedRelaxing = false
    for (var i = 0; i < recent.length; i++) {
      if (recent[i].techniqueId === "relaxing478" || recent[i].techniqueId === "extended-exhale") usedRelaxing = true
    }
    if (!usedRelaxing) {
      return { techniqueId: "relaxing478", reason: "It's late — 4-7-8 is built for winding down." }
    }
  }

  // One technique to the exclusion of everything else, for a while.
  var counts = {}
  var dominantId = ""
  var dominantCount = 0
  for (var j = 0; j < recent.length; j++) {
    var id = recent[j].techniqueId
    counts[id] = (counts[id] || 0) + 1
    if (counts[id] > dominantCount) { dominantCount = counts[id]; dominantId = id }
  }
  if (recent.length >= 6 && dominantCount === recent.length) {
    var alternative = dominantId === "box" ? "coherent" : "box"
    var altTechnique = techniqueById(alternative, config)
    return {
      techniqueId: alternative,
      reason: "Every session lately has been " + (techniqueById(dominantId, config) || { name: dominantId }).name
        + ". " + (altTechnique ? altTechnique.name : alternative) + " is a change of pace."
    }
  }

  // Abandoning most of what you start usually means the sessions are too long,
  // not that the technique is wrong.
  var rate = completionRate(history, 14, now)
  if (rate.total >= 5 && rate.pct < 0.5) {
    return { techniqueId: "physiological-sigh", reason: "Most sessions get cut short — the physiological sigh takes under a minute." }
  }

  return null
}

// Exposed only for the Node test harness under test/; QML's JS import
// mechanism has no `module` global, so this is a no-op there.
if (typeof module !== "undefined") {
  module.exports = {
    PHASE: PHASE,
    PLUGIN_GLYPH: PLUGIN_GLYPH,
    TECHNIQUES: TECHNIQUES,
    SCALE_MIN: SCALE_MIN,
    SCALE_MAX: SCALE_MAX,
    DAILY_HISTORY_DAYS: DAILY_HISTORY_DAYS,
    SESSION_HISTORY_MAX: SESSION_HISTORY_MAX,
    MAX_CYCLE_SECONDS: MAX_CYCLE_SECONDS,
    allTechniques: allTechniques,
    techniqueById: techniqueById,
    isBuiltIn: isBuiltIn,
    phaseLabel: phaseLabel,
    phaseGlyph: phaseGlyph,
    phaseMs: phaseMs,
    isHold: isHold,
    cycleSeconds: cycleSeconds,
    sessionSeconds: sessionSeconds,
    peakScale: peakScale,
    scaleEnvelope: scaleEnvelope,
    orbScale: orbScale,
    defaultSession: defaultSession,
    parseSession: parseSession,
    effectiveElapsedMs: effectiveElapsedMs,
    resolve: resolve,
    formatClock: formatClock,
    formatDuration: formatDuration,
    validateCustom: validateCustom,
    slugify: slugify,
    defaultConfig: defaultConfig,
    parseConfig: parseConfig,
    serializeConfig: serializeConfig,
    defaultStats: defaultStats,
    parseStats: parseStats,
    defaultHistory: defaultHistory,
    parseHistory: parseHistory,
    dateStringOf: dateStringOf,
    todayDateString: todayDateString,
    dailyBuckets: dailyBuckets,
    streakOf: streakOf,
    totals: totals,
    sessionsWithin: sessionsWithin,
    techniqueBreakdown: techniqueBreakdown,
    hourHeatmap: hourHeatmap,
    completionRate: completionRate,
    suggestTechnique: suggestTechnique
  }
}
