// Pure logic for the cliamp bar widget: parsing the two things cliamp emits
// over its control socket and formatting them for display. No QML / Quickshell
// APIs in here so it can be unit-tested with `node --test`.
//
//   `cliamp status --json`  -> one JSON object (see parseStatus). NOTE: the
//                              binary's status JSON has no `visualizer` field —
//                              the current mode only appears in visstream
//                              frames — so parseStatus carries `visualizer`
//                              forward from a previous status when the JSON
//                              omits it.
//   `cliamp visstream`      -> newline-delimited JSON, one frame per line,
//                              each `{ "ok":true, "visualizer":"Bars",
//                              "bands":[10 floats 0..1] }` (see parseVisFrame)
//
// When cliamp is not running every command prints a plain
// "cliamp is not running (no socket at ...)" line and exits non-zero; every
// parser here treats anything it can't read as "not playing" rather than
// throwing.

var BAND_COUNT = 10
var SIMPLE_VERBS = ["play", "pause", "toggle", "next", "prev", "stop", "shuffle", "repeat"]

// Normalize the small command surface exposed by the widget into argv. IPC
// callers can supply the visualizer name, so never pass arbitrary arguments
// through to cliamp (even though execDetached does not invoke a shell).
function safeVerbArgs(args) {
  if (!Array.isArray(args) || args.length === 0 || typeof args[0] !== "string") return null

  var verb = args[0]
  if (SIMPLE_VERBS.indexOf(verb) !== -1) return args.length === 1 ? [verb] : null

  if (verb === "seek") {
    if (args.length !== 2 || typeof args[1] !== "string" || !/^(0|[1-9][0-9]*)$/.test(args[1])) return null
    var seconds = Number(args[1])
    return isFinite(seconds) && seconds <= 2147483647 ? [verb, args[1]] : null
  }

  if (verb === "volume") {
    if (args.length !== 2 || typeof args[1] !== "string" || !/^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$/.test(args[1])) return null
    var db = Number(args[1])
    return isFinite(db) && Math.abs(db) <= 100 ? [verb, args[1]] : null
  }

  if (verb === "vis") {
    var name = args[1]
    if (args.length !== 2 || typeof name !== "string" ||
        !/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(name) ||
        name === "list" || name === "next") return null
    return [verb, name]
  }

  return null
}


function emptyStatus() {
  return {
    running: false,
    state: "stopped", // "playing" | "paused" | "stopped"
    playing: false,
    paused: false,
    title: "",
    artist: "",
    label: "",
    position: 0,
    total: 0,
    visualizer: "",
    shuffle: false,
    repeat: "Off",
    speed: 1
  }
}

// basename without extension, for a local file path with no title metadata.
function baseName(path) {
  if (!path || typeof path !== "string") return ""
  var clean = path.split(/[?#]/)[0]
  var seg = clean.split("/").pop() || clean
  return seg.replace(/\.[A-Za-z0-9]{1,5}$/, "")
}

function parseStatus(raw, prev) {
  var out = emptyStatus()
  if (!raw || typeof raw !== "string") return out
  var text = raw.trim()
  if (!text || text.indexOf("{") === -1) return out // "not running" line, empty, etc.
  var p
  try {
    p = JSON.parse(text.slice(text.indexOf("{")))
  } catch (e) {
    return out
  }
  if (!p || p.ok === false) return out

  out.running = true
  var state = String(p.state || "stopped").toLowerCase()
  out.state = state
  out.playing = state === "playing"
  out.paused = state === "paused"

  var track = p.track || {}
  out.title = String(track.title || "").trim()
  out.artist = String(track.artist || "").trim()
  if (!out.title) out.title = baseName(track.path)
  out.label = out.artist && out.title ? (out.artist + " — " + out.title) : out.title

  out.position = Number(p.position) || 0
  out.total = Number(p.total) || 0
  // The status JSON carries no visualizer field; keep the mode the last
  // visstream frame reported (or that the user just picked) instead of
  // resetting the dropdown to its fallback every 2 s poll.
  out.visualizer = String(p.visualizer || (prev && prev.visualizer) || "")
  out.shuffle = p.shuffle === true
  out.repeat = String(p.repeat || "Off")
  out.speed = Number(p.speed) || 1
  return out
}

// One line of `cliamp visstream`. Returns { bands, visualizer } where bands
// is an array of BAND_COUNT numbers in [0,1], or null if the line isn't a
// usable frame (so the caller keeps the previous frame instead of collapsing
// the bars). Every real frame carries the active visualizer mode's name, so
// this is the widget's source of truth for which mode is selected.
function parseVisFrame(line) {
  if (!line || typeof line !== "string") return null
  var text = line.trim()
  if (!text || text.charAt(0) !== "{") return null
  var p
  try {
    p = JSON.parse(text)
  } catch (e) {
    return null
  }
  if (!p || !Array.isArray(p.bands) || p.bands.length === 0) return null
  var bands = []
  for (var i = 0; i < BAND_COUNT; i++) {
    var v = Number(p.bands[i])
    if (!isFinite(v)) v = 0
    bands.push(v < 0 ? 0 : (v > 1 ? 1 : v))
  }
  return { bands: bands, visualizer: String(p.visualizer || "") }
}

// Bands-only view of parseVisFrame, for callers that don't need the mode.
function parseBands(line) {
  var frame = parseVisFrame(line)
  return frame ? frame.bands : null
}

// A synthesised idle waveform for when nothing is streaming — a slow travelling
// sine so the "synthesiser" still breathes while paused/stopped. `phase` is a
// free-running radian counter the widget bumps on a timer; `amp` scales the
// whole thing (0 collapses it flat).
function idleBands(phase, amp) {
  var a = amp === undefined ? 0.22 : amp
  var out = []
  for (var i = 0; i < BAND_COUNT; i++) {
    var s = Math.sin(phase + i * 0.6) * 0.5 + 0.5
    var envelope = Math.sin((i + 0.5) / BAND_COUNT * Math.PI) // fade the ends
    out.push(a * s * envelope)
  }
  return out
}

function clamp01(x) {
  return x < 0 ? 0 : (x > 1 ? 1 : x)
}

function progressFraction(position, total) {
  if (!(total > 0)) return 0
  return clamp01(position / total)
}

function formatTime(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var m = Math.floor(s / 60)
  var r = s % 60
  return m + ":" + (r < 10 ? "0" + r : r)
}

// Short bar label: elided elsewhere, this just picks the string.
function barLabel(status) {
  if (!status || !status.running) return "cliamp"
  return status.label || "cliamp"
}

function stateMeta(status) {
  if (!status || !status.running) return "Not running"
  if (status.playing) return "Playing"
  if (status.paused) return "Paused"
  return "Stopped"
}

var api = {
  BAND_COUNT: BAND_COUNT,
  emptyStatus: emptyStatus,
  baseName: baseName,
  parseStatus: parseStatus,
  parseVisFrame: parseVisFrame,
  parseBands: parseBands,
  idleBands: idleBands,
  progressFraction: progressFraction,
  safeVerbArgs: safeVerbArgs,
  formatTime: formatTime,
  barLabel: barLabel,
  stateMeta: stateMeta
}

if (typeof module !== "undefined") module.exports = api
