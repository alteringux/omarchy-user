// Pure logic for the conductor plugin: tolerant parsing of the two state
// files the `omarchy-conductor` CLI owns (conductor-state.json,
// conductor-snapshot.json), plus the little formatters the bar widget and
// panel render. No QML / Quickshell APIs so it stays Node-testable
// (test/model.test.js). Same conventions as the sibling plugins' Model.js.

function num(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function str(value, fallback) {
  return typeof value === "string" ? value : (fallback || "")
}

function defaultState() {
  return {
    version: 1,
    active: false,
    ritual: null,
    label: "",
    phase: "idle",
    startedAt: 0,
    lastStepAt: 0,
    pomodoroPhaseSeen: "IDLE",
    steps: [],
    lastSummary: ""
  }
}

// Tolerant parse for conductor-state.json — a half-written or malformed file
// degrades to "idle, nothing running" rather than throwing and taking the
// bar widget down.
function parseState(raw) {
  var out = defaultState()
  if (!raw || raw.length === 0) return out
  try {
    var s = JSON.parse(raw)
    if (s && typeof s === "object") {
      out.active = s.active === true
      out.ritual = s.ritual == null ? null : String(s.ritual)
      out.label = str(s.label, "")
      out.phase = str(s.phase, "idle")
      out.startedAt = num(s.startedAt, 0)
      out.lastStepAt = num(s.lastStepAt, 0)
      out.pomodoroPhaseSeen = str(s.pomodoroPhaseSeen, "IDLE")
      out.lastSummary = str(s.lastSummary, "")
      if (Array.isArray(s.steps)) {
        out.steps = s.steps.map(function (st) {
          st = st && typeof st === "object" ? st : {}
          return {
            cli: st.cli == null ? "" : String(st.cli),
            args: Array.isArray(st.args) ? st.args.map(String) : [],
            when: str(st.when, "start"),
            speak: str(st.speak, ""),
            optional: st.optional !== false,
            status: str(st.status, "pending"),
            ms: num(st.ms, 0),
            error: st.error == null ? null : String(st.error)
          }
        })
      }
    }
  } catch (e) {
    console.warn && console.warn("conductor: state parse failed:", e)
  }
  return out
}

// { done, total, ok, skipped, failed, pending }
function stepCounts(state) {
  var steps = (state && Array.isArray(state.steps)) ? state.steps : []
  var c = { done: 0, total: steps.length, ok: 0, skipped: 0, failed: 0, pending: 0 }
  for (var i = 0; i < steps.length; i++) {
    var st = steps[i].status
    if (st === "ok") c.ok++
    else if (st === "skipped") c.skipped++
    else if (st === "failed") c.failed++
    else { c.pending++; continue }
    c.done++
  }
  return c
}

var PHASE_LABELS = {
  idle: "idle",
  start: "starting",
  running: "in session",
  work: "deep work",
  "break": "break",
  end: "wrapping up"
}

function phaseLabel(state) {
  var p = state && state.phase ? state.phase : "idle"
  return PHASE_LABELS[p] || p
}

// Bar text: nothing noisy when idle (the icon carries it), "Focus 3/9" while
// a ritual runs.
function widgetLabel(state) {
  if (!state || !state.active) return ""
  var c = stepCounts(state)
  var name = ritualName(state)
  return name + "  " + c.done + "/" + c.total
}

function ritualName(state) {
  if (!state) return ""
  if (state.label && state.label.length > 0) return state.label
  if (state.ritual && state.ritual.length > 0) return state.ritual
  return "ritual"
}

// Panel sub-line under the progress bar.
function progressText(state) {
  var c = stepCounts(state)
  if (c.total === 0) return "no steps"
  var bits = [c.done + " / " + c.total + " steps"]
  var tail = []
  if (c.ok) tail.push(c.ok + " ok")
  if (c.skipped) tail.push(c.skipped + " skipped")
  if (c.failed) tail.push(c.failed + " failed")
  if (tail.length) bits.push(tail.join(", "))
  return bits.join("  ·  ")
}

function stepGlyph(status) {
  if (status === "ok") return "✓"       // check
  if (status === "skipped") return "·"  // middle dot
  if (status === "failed") return "✗"   // ballot x
  return "○"                             // hollow circle (pending)
}

function stepText(step) {
  var s = step && typeof step === "object" ? step : {}
  var parts = [s.cli || "(no cli)"]
  if (Array.isArray(s.args) && s.args.length) parts.push(s.args.join(" "))
  return parts.join(" ")
}

// ---- ritual catalogue (from `omarchy-conductor list`) -------------------

function parseRitualList(raw) {
  var arr = []
  try {
    var v = JSON.parse(raw || "[]")
    if (Array.isArray(v)) {
      arr = v.filter(function (r) { return r && typeof r === "object" && r.id }).map(function (r) {
        return {
          id: String(r.id),
          label: str(r.label, String(r.id)),
          description: str(r.description, ""),
          steps: num(r.steps, 0),
          phases: Array.isArray(r.phases) ? r.phases.map(String) : []
        }
      })
    }
  } catch (e) { /* leave empty */ }
  return arr
}

function ritualSubtitle(ritual) {
  var r = ritual || {}
  var bits = [(num(r.steps, 0)) + " steps"]
  if (Array.isArray(r.phases) && r.phases.length > 1) bits.push(r.phases.join(" → "))
  return bits.join("  ·  ")
}

// ---- cockpit snapshot (from conductor-snapshot.json) -------------------

function parseSnapshot(raw) {
  try {
    var v = JSON.parse(raw || "{}")
    if (v && typeof v === "object") return v
  } catch (e) { /* fall through */ }
  return {}
}

function fmtMs(ms) {
  ms = num(ms, 0)
  if (ms <= 0) return "0m"
  var mins = Math.floor(ms / 60000)
  if (mins < 60) return mins + "m"
  var h = Math.floor(mins / 60)
  return h + "h " + (mins % 60) + "m"
}

// [{ label, value }] — one row per plugin, skipping any the snapshot lacks.
function snapshotLines(snap) {
  snap = snap && typeof snap === "object" ? snap : {}
  var out = []

  var p = snap.pomodoro || {}
  if (p.phase !== undefined) {
    var pv = String(p.phase || "IDLE").toLowerCase().replace(/_/g, " ")
    if (num(p.streak, 0) > 0) pv += "  ·  streak " + num(p.streak, 0)
    if (num(p.completedToday, 0) > 0) pv += "  ·  " + num(p.completedToday, 0) + " today"
    out.push({ label: "Pomodoro", value: pv })
  }

  var t = snap.timers || {}
  if (t.count !== undefined) {
    var tv = num(t.count, 0) + " running"
    if (num(t.longestMs, 0) > 0) tv += "  ·  longest " + fmtMs(t.longestMs)
    out.push({ label: "Timers", value: tv })
  }

  var c = snap.countdowns || {}
  if (c.count !== undefined) {
    var cv = num(c.count, 0) + " tracked"
    if (c.soonestDays !== undefined && c.soonestDays !== null) cv += "  ·  soonest in " + num(c.soonestDays, 0) + "d"
    out.push({ label: "Countdowns", value: cv })
  }

  var sc = snap.score || {}
  if (sc.score !== undefined) out.push({ label: "Score", value: String(num(sc.score, 0)) })

  var r = snap.reminders
  var rn = Array.isArray(r) ? r.length : (r && Array.isArray(r.reminders) ? r.reminders.length : null)
  if (rn !== null) out.push({ label: "Reminders", value: rn + " pending" })

  var v = snap.vpn || {}
  if (v.connected !== undefined) {
    var vv = v.connected ? "connected" : "off"
    if (v.connected && v.country) vv += "  ·  " + v.country
    out.push({ label: "VPN", value: vv })
  }

  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultState: defaultState,
    parseState: parseState,
    stepCounts: stepCounts,
    phaseLabel: phaseLabel,
    widgetLabel: widgetLabel,
    ritualName: ritualName,
    progressText: progressText,
    stepGlyph: stepGlyph,
    stepText: stepText,
    parseRitualList: parseRitualList,
    ritualSubtitle: ritualSubtitle,
    parseSnapshot: parseSnapshot,
    fmtMs: fmtMs,
    snapshotLines: snapshotLines
  }
}
