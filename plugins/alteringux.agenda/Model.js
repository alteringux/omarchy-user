// Pure agenda logic for the alteringux.agenda service. Everything here is
// side-effect free and Node-testable (see test/model.test.js); Service.qml
// owns all the I/O (reading .ics files, writing the state file, firing
// notify-send).
//
// v1 limitations, deliberately:
//   - RRULE is NOT expanded. Recurring events are flagged (`recurring: true`)
//     off their master VEVENT but only that first instance is considered.
//   - TZID / floating times are treated as local wall-clock. Only trailing-Z
//     (UTC) and VALUE=DATE are handled precisely.

function defaultConfig() {
  return {
    calendarDirs: ["~/.local/share/calendars", "~/.calendars"],
    leadMinutes: 10,
    pollSeconds: 60
  }
}

// Merge a user agenda.json string over defaultConfig(). Bad / missing fields
// fall back rather than throw.
function parseConfig(raw) {
  var cfg = defaultConfig()
  var obj = null
  try { obj = raw ? JSON.parse(raw) : null } catch (e) { obj = null }
  if (!obj || typeof obj !== "object") return cfg

  if (Array.isArray(obj.calendarDirs)) {
    var dirs = obj.calendarDirs.filter(function (d) { return typeof d === "string" && d.length > 0 })
    if (dirs.length > 0) cfg.calendarDirs = dirs
  }
  if (isFiniteNumber(obj.leadMinutes) && obj.leadMinutes >= 0) cfg.leadMinutes = Math.floor(obj.leadMinutes)
  if (isFiniteNumber(obj.pollSeconds) && obj.pollSeconds >= 5) cfg.pollSeconds = Math.floor(obj.pollSeconds)
  return cfg
}

function isFiniteNumber(n) {
  return typeof n === "number" && isFinite(n)
}

// --- ICS parsing -----------------------------------------------------------

// RFC 5545 line unfolding: a CRLF followed by a space or tab continues the
// previous logical line.
function unfoldLines(text) {
  var raw = String(text || "").split(/\r?\n/)
  var out = []
  for (var i = 0; i < raw.length; i++) {
    var line = raw[i]
    if (line.length > 0 && (line[0] === " " || line[0] === "\t") && out.length > 0) {
      out[out.length - 1] += line.slice(1)
    } else {
      out.push(line)
    }
  }
  return out
}

// "DTSTART;TZID=Europe/Berlin:20260830T140000" ->
//   { name: "DTSTART", params: { TZID: "Europe/Berlin" }, value: "20260830T140000" }
function splitProperty(line) {
  var idx = line.indexOf(":")
  if (idx < 0) return { name: line.toUpperCase(), params: {}, value: "" }
  var head = line.slice(0, idx)
  var value = line.slice(idx + 1)
  var parts = head.split(";")
  var name = parts.shift().toUpperCase()
  var params = {}
  for (var i = 0; i < parts.length; i++) {
    var eq = parts[i].indexOf("=")
    if (eq > 0) params[parts[i].slice(0, eq).toUpperCase()] = parts[i].slice(eq + 1)
  }
  return { name: name, params: params, value: value }
}

function unescapeText(value) {
  return String(value || "").replace(/\\([\\;,nN])/g, function (_, c) {
    return (c === "n" || c === "N") ? "\n" : c
  })
}

// Returns { epoch, allDay } in whole seconds, or null if unparseable.
function parseIcsDate(rawValue, params) {
  var v = String(rawValue || "").trim()
  var m = v.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/)
  if (!m) return null

  var y = +m[1], mo = +m[2], d = +m[3]
  var hh = +(m[4] || 0), mi = +(m[5] || 0), ss = +(m[6] || 0)
  var isUtc = m[7] === "Z"
  var dateOnly = (params && String(params.VALUE).toUpperCase() === "DATE") || !m[4]

  var epoch
  if (dateOnly) {
    epoch = Math.floor(new Date(y, mo - 1, d, 0, 0, 0).getTime() / 1000)
  } else if (isUtc) {
    epoch = Math.floor(Date.UTC(y, mo - 1, d, hh, mi, ss) / 1000)
  } else {
    // Floating time or TZID we don't resolve: treat as local wall-clock.
    epoch = Math.floor(new Date(y, mo - 1, d, hh, mi, ss).getTime() / 1000)
  }
  return { epoch: epoch, allDay: dateOnly }
}

// Parse every VEVENT out of one .ics blob (which may itself be several
// concatenated calendars). Returns an array of normalized event objects.
function parseEvents(icsText) {
  var lines = unfoldLines(icsText)
  var events = []
  var cur = null

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "BEGIN:VEVENT") { cur = { recurring: false }; continue }
    if (line === "END:VEVENT") {
      if (cur && typeof cur.start === "number") events.push(finalizeEvent(cur))
      cur = null
      continue
    }
    if (!cur) continue

    var p = splitProperty(line)
    switch (p.name) {
      case "UID": cur.uid = p.value.trim(); break
      case "SUMMARY": cur.summary = unescapeText(p.value); break
      case "LOCATION": cur.location = unescapeText(p.value); break
      case "STATUS": cur.status = p.value.trim().toUpperCase(); break
      case "RRULE": cur.recurring = true; break
      case "DTSTART": {
        var s = parseIcsDate(p.value, p.params)
        if (s) { cur.start = s.epoch; cur.allDay = s.allDay }
        break
      }
      case "DTEND": {
        var e = parseIcsDate(p.value, p.params)
        if (e) cur.end = e.epoch
        break
      }
    }
  }
  return events
}

function finalizeEvent(cur) {
  var allDay = !!cur.allDay
  var start = cur.start
  var end = (typeof cur.end === "number" && cur.end > start)
    ? cur.end
    : start + (allDay ? 86400 : 3600)
  var summary = (cur.summary && cur.summary.trim()) ? cur.summary.trim() : "(busy)"
  return {
    uid: cur.uid || (summary + "@" + start),
    summary: summary,
    location: cur.location || "",
    start: start,
    end: end,
    allDay: allDay,
    recurring: !!cur.recurring,
    cancelled: cur.status === "CANCELLED"
  }
}

function startOfLocalDay(epoch) {
  var d = new Date(epoch * 1000)
  return Math.floor(new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0).getTime() / 1000)
}

// --- Agenda ---------------------------------------------------------------

// icsTexts: array of raw .ics strings. Returns:
//   { next, today: [...], upcoming: [...], generatedAt }
// `next` is the soonest non-all-day event that hasn't ended yet; if there
// is none, the soonest all-day event that hasn't ended.
function computeAgenda(icsTexts, nowEpoch, opts) {
  opts = opts || {}
  var all = []
  var texts = Array.isArray(icsTexts) ? icsTexts : [icsTexts]
  for (var i = 0; i < texts.length; i++) {
    all = all.concat(parseEvents(texts[i]))
  }

  all.sort(function (a, b) { return a.start - b.start })

  var seen = {}
  var events = []
  for (var j = 0; j < all.length; j++) {
    var e = all[j]
    if (e.cancelled) continue
    var key = e.uid + "@" + e.start
    if (seen[key]) continue
    seen[key] = true
    events.push(e)
  }

  // "upcoming" = anything that hasn't ended yet, so an event in progress
  // still counts and stays at the front (the list is start-sorted).
  var upcoming = events.filter(function (ev) { return ev.end > nowEpoch })

  var next = null
  for (var k = 0; k < upcoming.length; k++) {
    if (!upcoming[k].allDay) { next = upcoming[k]; break }
  }
  if (!next) next = upcoming.length > 0 ? upcoming[0] : null

  var sod = startOfLocalDay(nowEpoch)
  var eod = sod + 86400
  var today = events.filter(function (ev) { return ev.start >= sod && ev.start < eod })

  return {
    next: next,
    today: today,
    upcoming: upcoming.slice(0, 20),
    generatedAt: nowEpoch
  }
}

// Decide whether the service should fire a notification for agenda.next.
// notifiedKeys is the running list of already-notified "<uid>@<start>" keys;
// the returned `keys` is that list pruned of stale entries (plus the new one
// when notify === true). Caller persists `keys` verbatim.
function shouldNotify(agenda, nowEpoch, leadSeconds, notifiedKeys) {
  var kept = pruneKeys(notifiedKeys || [], nowEpoch)
  var ev = agenda && agenda.next
  if (!ev || ev.allDay) return { notify: false, keys: kept }

  var delta = ev.start - nowEpoch
  var key = (ev.uid || ev.summary) + "@" + ev.start
  var due = delta <= leadSeconds && delta > -60
  var already = kept.indexOf(key) >= 0

  if (due && !already) {
    kept.push(key)
    return {
      notify: true,
      event: ev,
      key: key,
      minutesUntil: Math.max(0, Math.round(delta / 60)),
      keys: kept
    }
  }
  return { notify: false, keys: kept }
}

// Drop keys whose "@<epoch>" suffix is more than a day in the past so the
// persisted list stays bounded.
function pruneKeys(keys, nowEpoch) {
  var cutoff = nowEpoch - 86400
  return (keys || []).filter(function (k) {
    var at = String(k).lastIndexOf("@")
    if (at < 0) return false
    var t = parseInt(String(k).slice(at + 1), 10)
    return isFinite(t) && t >= cutoff
  })
}

// --- Formatting ---------------------------------------------------------

function pad2(n) { return (n < 10 ? "0" : "") + n }

function formatClock(epoch) {
  var d = new Date(epoch * 1000)
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

// seconds -> "now" / "in 8 min" / "in 1 h 5 min" / "in 2 d"
function formatRelative(seconds) {
  if (seconds <= 30) return "now"
  var mins = Math.round(seconds / 60)
  if (mins < 60) return "in " + mins + " min"
  var hours = Math.floor(mins / 60)
  if (hours < 24) {
    var rem = mins % 60
    return rem > 0 ? ("in " + hours + " h " + rem + " min") : ("in " + hours + " h")
  }
  return "in " + Math.round(hours / 24) + " d"
}

// The object serialized to $XDG_RUNTIME_DIR/omarchy-agenda/state for any
// bar widget / CLI that wants to surface the next event.
function stateJson(agenda, nowEpoch) {
  var ev = agenda && agenda.next
  return {
    version: 1,
    generated_at: nowEpoch,
    next: ev ? {
      summary: ev.summary,
      location: ev.location || "",
      start_epoch: ev.start,
      end_epoch: ev.end,
      all_day: !!ev.allDay,
      recurring: !!ev.recurring,
      clock: formatClock(ev.start),
      relative: formatRelative(ev.start - nowEpoch)
    } : null,
    today_count: agenda && agenda.today ? agenda.today.length : 0
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    defaultConfig: defaultConfig,
    parseConfig: parseConfig,
    unfoldLines: unfoldLines,
    splitProperty: splitProperty,
    unescapeText: unescapeText,
    parseIcsDate: parseIcsDate,
    parseEvents: parseEvents,
    computeAgenda: computeAgenda,
    shouldNotify: shouldNotify,
    pruneKeys: pruneKeys,
    formatClock: formatClock,
    formatRelative: formatRelative,
    stateJson: stateJson
  }
}
