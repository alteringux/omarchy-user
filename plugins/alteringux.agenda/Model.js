// Pure agenda logic for the alteringux.agenda service. Everything here is
// side-effect free and Node-testable (see test/model.test.js); Service.qml
// owns all the I/O (reading .ics files, writing the state file, firing
// notify-send).
//
// RRULE recurrence is expanded for the supported RFC 5545 frequencies when
// computing an agenda. TZID values are resolved with the platform IANA data;
// floating times retain the host's local-wall-clock semantics.
// DURATION is honored for the end time, but year/month components are rejected
// (they have no fixed length in seconds).

// Resolve a wall-clock date in an explicit IANA timezone without depending on
// the process timezone. The short fixed-point iteration handles DST offsets.
function epochForWall(y, mo, d, hh, mi, ss, tzid) {
  if (!tzid) return Math.floor(new Date(y, mo - 1, d, hh, mi, ss).getTime() / 1000)
  if (/^(UTC|GMT)$/i.test(String(tzid))) return Math.floor(Date.UTC(y, mo - 1, d, hh, mi, ss) / 1000)
  var target = Date.UTC(y, mo - 1, d, hh, mi, ss)
  var guess = target
  try {
    var fmt = new Intl.DateTimeFormat("en-US", {
      timeZone: String(tzid),
      year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", second: "2-digit",
      hourCycle: "h23"
    })
    for (var i = 0; i < 3; i++) {
      var parts = {}
      fmt.formatToParts(new Date(guess)).forEach(function (p) { parts[p.type] = +p.value })
      var wall = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second)
      guess += target - wall
    }
    return Math.floor(guess / 1000)
  } catch (e) {
    // A missing/invalid TZID must not change with the machine's local TZ.
    return Math.floor(target / 1000)
  }
}

function parseWallDate(rawValue) {
  var m = String(rawValue || "").trim().match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/)
  if (!m) return null
  return {
    y: +m[1], mo: +m[2], d: +m[3],
    hh: +(m[4] || 0), mi: +(m[5] || 0), ss: +(m[6] || 0),
    utc: m[7] === "Z", dateOnly: !m[4]
  }
}

// Returns { epoch, allDay } in whole seconds, or null if unparseable.
function parseIcsDate(rawValue, params) {
  var wall = parseWallDate(rawValue)
  if (!wall) return null
  var p = params || {}
  var dateOnly = String(p.VALUE || "").toUpperCase() === "DATE" || wall.dateOnly
  var hour = dateOnly ? 0 : wall.hh
  var minute = dateOnly ? 0 : wall.mi
  var second = dateOnly ? 0 : wall.ss
  var epoch = wall.utc
    ? Math.floor(Date.UTC(wall.y, wall.mo - 1, wall.d, hour, minute, second) / 1000)
    : epochForWall(wall.y, wall.mo, wall.d, hour, minute, second, p.TZID)
  return { epoch: epoch, allDay: dateOnly }
}

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


// RFC 5545 dur-value, e.g. "PT90M", "P1DT12H", "P2W". Returns whole seconds
// (signed), or null if unparseable. Year/month components have no fixed
// length and are rejected.
function parseIcsDuration(rawValue) {
  var v = String(rawValue || "").trim()
  var m = v.match(/^([+-]?)P(?:(\d+)W|(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?)$/)
  if (!m) return null
  if (!m[2] && !m[3] && !m[4] && !m[5] && !m[6] && !m[7] && !m[8]) return null // bare "P" / "PT"
  var sign = m[1] === "-" ? -1 : 1
  var years = +(m[3] || 0)
  var months = +(m[4] || 0)
  if (years > 0 || months > 0) return null
  var total =
    +(m[2] || 0) * 604800 +
    +(m[5] || 0) * 86400 +
    +(m[6] || 0) * 3600 +
    +(m[7] || 0) * 60 +
    +(m[8] || 0)
  if (total === 0) return null
  return sign * total
}

function parseRecurrenceRule(rawValue, tzid) {
  var out = { freq: "", interval: 1, count: 0, until: 0, byday: [], bymonthday: [], bymonth: [] }
  String(rawValue || "").split(";").forEach(function (part) {
    var bits = part.split("=")
    if (bits.length < 2) return
    var key = bits[0].toUpperCase()
    var value = bits.slice(1).join("=").toUpperCase()
    if (key === "FREQ") out.freq = value
    else if (key === "INTERVAL" && +value > 0) out.interval = Math.floor(+value)
    else if (key === "COUNT" && +value > 0) out.count = Math.floor(+value)
    else if (key === "UNTIL") {
      var untilWall = parseWallDate(value)
      var parsed = parseIcsDate(value, { TZID: tzid })
      if (parsed) {
        if (untilWall && untilWall.dateOnly) {
          var next = addUtcDays(Date.UTC(untilWall.y, untilWall.mo - 1, untilWall.d), 1)
          out.until = epochForWall(next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate(), 0, 0, 0, tzid) - 1
        } else {
          out.until = parsed.epoch
        }
      }
    } else if (key === "BYDAY") {
      out.byday = value.split(",").map(function (d) {
        var m = d.match(/([+-]?\d+)?(SU|MO|TU|WE|TH|FR|SA)$/)
        return m ? ["SU", "MO", "TU", "WE", "TH", "FR", "SA"].indexOf(m[2]) : -1
      }).filter(function (d) { return d >= 0 })
    } else if (key === "BYMONTHDAY") {
      out.bymonthday = value.split(",").map(Number).filter(function (d) { return d >= 1 && d <= 31 })
    } else if (key === "BYMONTH") {
      out.bymonth = value.split(",").map(Number).filter(function (m) { return m >= 1 && m <= 12 })
    }
  })
  return out.freq ? out : null
}

function datePartsFromRaw(rawValue) {
  var p = parseWallDate(rawValue)
  return p && { y: p.y, mo: p.mo, d: p.d, hh: p.hh, mi: p.mi, ss: p.ss }
}

function addUtcDays(epochMs, days) {
  return new Date(epochMs + days * 86400000)
}

function occurrenceEpoch(date, tzid) {
  return epochForWall(date.y, date.mo, date.d, date.hh, date.mi, date.ss, tzid)
}

function makeOccurrence(event, start) {
  var copy = {}
  Object.keys(event).forEach(function (key) { copy[key] = event[key] })
  copy.start = start
  copy.end = start + (event.end - event.start)
  return copy
}

function expandRecurrence(event, rawRule, tzid, rawStart, options) {
  if (!options || typeof options.nowEpoch !== "number") return [event]
  var rule = parseRecurrenceRule(rawRule, tzid)
  var base = datePartsFromRaw(rawStart)
  if (!rule || !base) return [event]
  if (!["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].includes(rule.freq)) return [event]
  var horizon = options.nowEpoch + 366 * 86400
  var results = []
  var seen = {}
  var generated = 0
  var period = 0
  var stopped = false
  var weekday = new Date(Date.UTC(base.y, base.mo - 1, base.d)).getUTCDay()
  var byday = rule.byday.length ? rule.byday : [weekday]

  while (!stopped && period < 10000) {
    var candidates = []
    if (rule.freq === "DAILY") {
      var daily = addUtcDays(Date.UTC(base.y, base.mo - 1, base.d), period * rule.interval)
      candidates.push({ y: daily.getUTCFullYear(), mo: daily.getUTCMonth() + 1, d: daily.getUTCDate(), hh: base.hh, mi: base.mi, ss: base.ss })
    } else if (rule.freq === "WEEKLY") {
      var week = addUtcDays(Date.UTC(base.y, base.mo - 1, base.d), -weekday + period * rule.interval * 7)
      byday.forEach(function (day) {
        var date = addUtcDays(week.getTime(), day)
        candidates.push({ y: date.getUTCFullYear(), mo: date.getUTCMonth() + 1, d: date.getUTCDate(), hh: base.hh, mi: base.mi, ss: base.ss })
      })
    } else if (rule.freq === "MONTHLY") {
      var month = new Date(Date.UTC(base.y, base.mo - 1 + period * rule.interval, 1))
      var days = rule.bymonthday.length ? rule.bymonthday : [base.d]
      days.forEach(function (day) {
        var date = new Date(Date.UTC(month.getUTCFullYear(), month.getUTCMonth(), day))
        if (date.getUTCMonth() === month.getUTCMonth() && date.getUTCDate() === day) {
          candidates.push({ y: date.getUTCFullYear(), mo: date.getUTCMonth() + 1, d: day, hh: base.hh, mi: base.mi, ss: base.ss })
        }
      })
    } else if (rule.freq === "YEARLY") {
      var year = base.y + period * rule.interval
      var months = rule.bymonth || [base.mo]
      var yearDays = rule.bymonthday.length ? rule.bymonthday : [base.d]
      months.forEach(function (monthNumber) {
        yearDays.forEach(function (day) {
          var date = new Date(Date.UTC(year, monthNumber - 1, day))
          if (date.getUTCMonth() === monthNumber - 1 && date.getUTCDate() === day) {
            candidates.push({ y: year, mo: monthNumber, d: day, hh: base.hh, mi: base.mi, ss: base.ss })
          }
        })
      })
    } else {
      return [event]
    }
    candidates.sort(function (a, b) { return occurrenceEpoch(a, tzid) - occurrenceEpoch(b, tzid) })
    for (var i = 0; i < candidates.length; i++) {
      var start = occurrenceEpoch(candidates[i], tzid)
      if (start < event.start || seen[start]) continue
      seen[start] = true
      if (rule.until && start > rule.until) { stopped = true; break }
      generated++
      if (rule.count && generated > rule.count) { stopped = true; break }
      if (start > horizon) { stopped = true; break }
      results.push(makeOccurrence(event, start))
    }
    period++
  }
  return results.length ? results : [event]
}

// Parse every VEVENT out of one .ics blob (which may itself be several
// concatenated calendars). Returns an array of normalized event objects.
function parseEvents(icsText, options) {
  var lines = unfoldLines(icsText)
  var events = []
  var cur = null
  var inAlarm = false

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "BEGIN:VEVENT") { cur = { recurring: false }; inAlarm = false; continue }
    if (line === "END:VEVENT") {
      if (cur && typeof cur.start === "number") {
        var event = finalizeEvent(cur)
        events = events.concat(cur.rrule ? expandRecurrence(event, cur.rrule, cur.tzid, cur.startRaw, options) : [event])
      }
      cur = null
      inAlarm = false
      continue
    }
    if (!cur) continue
    if (line === "BEGIN:VALARM") { inAlarm = true; continue }
    if (line === "END:VALARM") { inAlarm = false; continue }
    if (inAlarm) continue

    var p = splitProperty(line)
    switch (p.name) {
      case "UID": cur.uid = p.value.trim(); break
      case "SUMMARY": cur.summary = unescapeText(p.value); break
      case "LOCATION": cur.location = unescapeText(p.value); break
      case "STATUS": cur.status = p.value.trim().toUpperCase(); break
      case "RRULE": cur.recurring = true; cur.rrule = p.value.trim(); break
      case "DTSTART": {
        var s = parseIcsDate(p.value, p.params)
        if (s) {
          cur.start = s.epoch
          cur.allDay = s.allDay
          cur.startRaw = p.value
          cur.tzid = p.params.TZID || (/[Z]$/.test(p.value.trim()) ? "UTC" : "")
        }
        break
      }
      case "DTEND": {
        var e = parseIcsDate(p.value, p.params)
        if (e) cur.end = e.epoch
        break
      }
      case "DURATION": {
        var dur = parseIcsDuration(p.value)
        if (dur) cur.duration = dur
        break
      }
    }
  }
  return events
}

function finalizeEvent(cur) {
  var allDay = !!cur.allDay
  var start = cur.start
  var end
  if (typeof cur.end === "number" && cur.end > start) {
    end = cur.end
  } else if (typeof cur.duration === "number" && cur.duration > 0) {
    end = start + cur.duration
  } else {
    end = start + (allDay ? 86400 : 3600)
  }
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
    all = all.concat(parseEvents(texts[i], { nowEpoch: nowEpoch }))
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
    parseIcsDuration: parseIcsDuration,
    parseEvents: parseEvents,
    computeAgenda: computeAgenda,
    shouldNotify: shouldNotify,
    pruneKeys: pruneKeys,
    formatClock: formatClock,
    formatRelative: formatRelative,
    stateJson: stateJson
  }
}
