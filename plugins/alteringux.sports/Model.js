// Pure logic for the sports plugin: tolerant parsing of the state file
// written by bin/sports_fetch.py, formatting helpers, favourite-team
// matching, and prediction output parsing. Kept free of QML/Quickshell APIs
// so it can be unit-tested in plain node (see test/model.test.js). The
// guarded module.exports at the bottom is a no-op inside QML.

// Display metadata for TheSportsDB sport names. The catalog is intentionally
// data-only so adding a sport never changes the panel or refresh logic.
var SPORT_GLYPHS = {
  "Soccer": "󰧑",
  "Rugby": "󰣇",
  "Basketball": "󰖄",
  "Ice Hockey": "󰍩",
  "American Football": "󰡊",
  "Baseball": "󰠓",
  "Cricket": "󰆍",
  "Motorsport": "󰋔",
  "Tennis": "󰑮",
  "Fighting": "󰒃",
  "Boxing": "󰒃",
  "Cycling": "󰄋",
  "Golf": "󰘭",
  "Volleyball": "󰩇",
  "Handball": "󰖟"
}

var SPORT_LABELS = {
  "Soccer": "Football",
  "Fighting": "UFC / MMA",
  "American Football": "American Football",
  "Ice Hockey": "Ice Hockey",
  "Motorsport": "Motorsport"
}
var SPORT_COLORS = {
  "Soccer": "#00CC99",
  "Rugby": "#FFCC00",
  "Basketball": "#FF6600",
  "Fighting": "#FF0066",
  "Boxing": "#CC0033",
  "American Football": "#9933FF",
  "Baseball": "#CCCC00",
  "Cricket": "#0099FF",
  "Tennis": "#66CC00",
  "Motorsport": "#FF3399",
  "Ice Hockey": "#00CCFF",
  "Golf": "#00CC66",
  "Cycling": "#6600CC",
  "Volleyball": "#CC3399",
  "Handball": "#CC6600"
}
var FALLBACK_GLYPH = "󰜺" // nf-md-trophy-outline

function sportLabel(sport) {
  return SPORT_LABELS[sport] || sport || "Sports"
}

function sportColor(sport) {
  return SPORT_COLORS[sport] || "#666666"
}

function defaultState() {
  return {
    version: 1, updatedAt: null, matchDataUpdatedAt: null, articleDataUpdatedAt: null,
    refreshHealth: { usedCachedMatches: false, usedCachedArticles: false },
    live: [], upcoming: [], results: [], articles: [],
    players: {}, standings: {}, teams: {}, predictions: {}
  }
}

// Tolerant: a half-written or malformed file yields an empty/default state
// rather than throwing, so the bar just shows its "waiting" state. Same
// convention as alteringux.stocks / alteringux.newsbar parseState.
function parseState(raw) {
  var st = defaultState()
  if (!raw) return st
  var doc
  try { doc = JSON.parse(raw) } catch (e) { return st }
  if (!doc || typeof doc !== "object") return st
  st.updatedAt = (typeof doc.updatedAt === "string") ? doc.updatedAt : null
  st.matchDataUpdatedAt = (typeof doc.matchDataUpdatedAt === "string") ? doc.matchDataUpdatedAt : null
  st.articleDataUpdatedAt = (typeof doc.articleDataUpdatedAt === "string") ? doc.articleDataUpdatedAt : null
  if (doc.refreshHealth && typeof doc.refreshHealth === "object") {
    st.refreshHealth = {
      usedCachedMatches: doc.refreshHealth.usedCachedMatches === true,
      usedCachedArticles: doc.refreshHealth.usedCachedArticles === true
    }
  }
  st.live = asList(doc.live)
  st.upcoming = asList(doc.upcoming)
  st.results = asList(doc.results)
  st.articles = asList(doc.articles)
  st.players = asMap(doc.players)
  st.standings = asMap(doc.standings)
  st.teams = asObjectMap(doc.teams)
  st.predictions = (doc.predictions && typeof doc.predictions === "object") ? doc.predictions : {}
  return st
}

function asList(v) {
  if (!Array.isArray(v)) return []
  return v.filter(function (item) {
    return item && typeof item === "object" && !Array.isArray(item)
  })
}

function asMap(v) {
  if (!v || typeof v !== "object" || Array.isArray(v)) return {}
  var out = {}
  for (var k in v) if (Object.prototype.hasOwnProperty.call(v, k)) out[k] = asList(v[k])
  return out
}

function asObjectMap(v) {
  if (!v || typeof v !== "object" || Array.isArray(v)) return {}
  var out = {}
  for (var k in v) {
    if (Object.prototype.hasOwnProperty.call(v, k) && v[k] && typeof v[k] === "object" && !Array.isArray(v[k]))
      out[k] = v[k]
  }
  return out
}

// ------------------------------------------------------------------ format
function formatScore(home, away) {
  var h = (home === null || home === undefined || home === ""), a = (away === null || away === undefined || away === "")
  if (h || a) return "—"
  return String(home) + " – " + String(away)
}

var LIVE_STATUS_WORDS = {
  "HT": 1, "1H": 1, "2H": 1, "1ST HALF": 1, "2ND HALF": 1,
  "ET": 1, "P": 1, "IN PLAY": 1, "LIVE": 1
}
var ENDED_STATUS_WORDS = {
  "FT": 1, "MATCH FINISHED": 1, "AET": 1, "PEN": 1, "FINISHED": 1,
  "AFTER OVER TIME": 1, "AFTER PENALTIES": 1, "POSTPONED": 1,
  "CANCELLED": 1, "CANCELED": 1, "ABANDONED": 1, "NS": 0,
  "NOT STARTED": 0
}

function statusKey(status) {
  return String(status || "").trim().toUpperCase()
}

function matchStarted(status) {
  var key = statusKey(status)
  if (!key || (ENDED_STATUS_WORDS.hasOwnProperty(key) && ENDED_STATUS_WORDS[key] === 0)) return false
  return !!LIVE_STATUS_WORDS[key] || !!ENDED_STATUS_WORDS[key]
}

function matchEnded(status) {
  var key = statusKey(status)
  return !!(ENDED_STATUS_WORDS.hasOwnProperty(key) && ENDED_STATUS_WORDS[key])
}

// "HT" / "62'" / "Postponed" / "" — elapsed minutes for in-play, else the
// status word, else nothing.
function formatMatchTime(status, elapsed) {
  var key = statusKey(status)
  if (key && LIVE_STATUS_WORDS[key]) {
    if (elapsed !== null && elapsed !== undefined && !isNaN(elapsed)) return String(elapsed) + "'"
    return String(status)
  }
  if (status) return String(status)
  return ""
}

// ------------------------------------------------------------ favourite teams
function isFavourite(teamName, favourites) {
  if (!teamName || !Array.isArray(favourites)) return false
  var t = String(teamName).toLowerCase()
  for (var i = 0; i < favourites.length; i++) {
    if (favourites[i] && String(favourites[i]).toLowerCase() === t) return true
  }
  return false
}

function matchTouchesFavourite(match, favourites) {
  if (!match) return false
  return isFavourite(match.homeTeam, favourites) || isFavourite(match.awayTeam, favourites)
}

function eventHomeLabel(match) {
  return (match && (match.homeTeam || match.eventName)) || "—"
}

function eventAwayLabel(match) {
  return (match && (match.awayTeam || (match.eventName ? "Fight card" : ""))) || "—"
}

function predictionKey(sport, homeTeam, awayTeam) {
  return [sport, homeTeam, awayTeam].map(function (part) {
    return String(part || "").trim().replace(/\s+/g, " ").toLowerCase()
  }).join("|")
}

function predictionForMatch(state, match) {
  if (!state || !match || !match.sport || !match.homeTeam || !match.awayTeam) return null
  var predictions = state.predictions || {}
  return predictions[predictionKey(match.sport, match.homeTeam, match.awayTeam)] || null
}

function youtubeSearchUrl(match, suffix) {
  var name = (match && match.eventName) || formatMatchLabel(match)
  var query = [name, match && match.sport, suffix].filter(Boolean).join(" ")
  return "https://www.youtube.com/results?search_query=" + encodeURIComponent(query)
}

function matchHighlightsUrl(match) {
  return (match && match.youtubeHighlightsUrl) || youtubeSearchUrl(match, "highlights")
}

function matchCoverageUrl(match) {
  return (match && match.officialCoverageUrl) || youtubeSearchUrl(match, "official live coverage")
}

// --------------------------------------------------------------- bar summary
// One display string + a small mode tag the BarWidget binds to. Modes:
//   live  — a (favourite if any) live match; text carries the score
//   next  — the next upcoming (favourite if any) match
//   idle  — nothing to show
// liveCount always carries how many matches are in progress overall.
function barSummary(state, favourites) {
  var live = ((state && state.live) || []).filter(function (m) {
    return m && !matchEnded(m.status)
  })
  var upcoming = (state && state.upcoming) || []
  var favLive = live.filter(function (m) { return matchTouchesFavourite(m, favourites) })
  var pickLive = favLive.length ? favLive[0] : (live.length ? live[0] : null)
  if (pickLive) {
    return {
      mode: "live", match: pickLive,
      text: eventHomeLabel(pickLive) + " " + formatScore(pickLive.homeScore, pickLive.awayScore) + " " + eventAwayLabel(pickLive),
      liveCount: live.length
    }
  }
  var favNext = upcoming.filter(function (m) { return matchTouchesFavourite(m, favourites) })
  var next = sortUpcoming(favNext.length ? favNext : upcoming.slice())[0] || null
  if (next) {
    return { mode: "next", match: next, text: eventHomeLabel(next) + " vs " + eventAwayLabel(next), liveCount: live.length }
  }
  return { mode: "idle", match: null, text: "Sports", liveCount: live.length }
}

// ------------------------------------------------------------------ sorting
// Epoch ms of a match's kick-off; Infinity for missing dates so unknowns
// sort last in both directions.
function matchTime(m) {
  if (!m) return Infinity
  if (m.strTimestamp) {
    var t = Date.parse(m.strTimestamp)
    if (!isNaN(t)) return t
  }
  if (m.dateEvent) {
    var d = Date.parse(m.dateEvent)
    if (!isNaN(d)) return d
  }
  return Infinity
}

// Returns a NEW soonest-first array; never mutates the caller's list.
function sortUpcoming(list) {
  return (list || []).slice().sort(function (a, b) { return matchTime(a) - matchTime(b) })
}

// ------------------------------------------------------------- match labels
function formatMatchLabel(m) {
  if (!m) return ""
  return eventHomeLabel(m) + " vs " + eventAwayLabel(m)
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function formatMatchDate(dateEvent) {
  if (!dateEvent) return ""
  var parts = String(dateEvent).split("-")
  if (parts.length < 3) return dateEvent
  var day = parseInt(parts[2], 10)
  var month = parseInt(parts[1], 10) - 1
  if (isNaN(day) || isNaN(month) || month < 0 || month > 11) return dateEvent
  return day + " " + MONTHS[month]
}

function formatMatchTimeOfDay(m) {
  if (!m || !m.strTimestamp) return ""
  var t = Date.parse(m.strTimestamp)
  if (isNaN(t)) return ""
  var d = new Date(t)
  var hh = d.getHours(), mm = d.getMinutes()
  return (hh < 10 ? "0" : "") + hh + ":" + (mm < 10 ? "0" : "") + mm
}

// --------------------------------------------------------------- prediction
// Shape from bin/omarchy-sports-predict's JSON output. Null (never throw)
// for empty/malformed output; error messages surface to the panel card.
function parsePrediction(raw) {
  if (!raw) return null
  var doc
  try { doc = JSON.parse(raw) } catch (e) { return null }
  if (!doc || typeof doc !== "object") return null
  return {
    version: doc.version || 1,
    sport: doc.sport || null,
    homeTeam: doc.homeTeam || null,
    awayTeam: doc.awayTeam || null,
    predictedWinner: doc.error ? null : (doc.predictedWinner || null),
    confidence: (typeof doc.confidence === "number") ? doc.confidence : null,
    breakdown: (doc.breakdown && typeof doc.breakdown === "object") ? doc.breakdown : null,
    reason: doc.reason || null,
    error: doc.error || null
  }
}

// ------------------------------------------------------------------- icons
function sportGlyph(sport) {
  if (!sport) return FALLBACK_GLYPH
  return SPORT_GLYPHS[sport] || FALLBACK_GLYPH
}

// Exposed only for the Node test harness under test/; QML's JS import
// mechanism has no `module` global, so this is a no-op there.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    defaultState: defaultState,
    parseState: parseState,
    formatScore: formatScore,
    matchStarted: matchStarted,
    matchEnded: matchEnded,
    formatMatchTime: formatMatchTime,
    isFavourite: isFavourite,
    matchTouchesFavourite: matchTouchesFavourite,
    barSummary: barSummary,
    matchTime: matchTime,
    sortUpcoming: sortUpcoming,
    formatMatchLabel: formatMatchLabel,
    formatMatchDate: formatMatchDate,
    predictionKey: predictionKey,
    predictionForMatch: predictionForMatch,
    formatMatchTimeOfDay: formatMatchTimeOfDay,
    youtubeSearchUrl: youtubeSearchUrl,
    matchHighlightsUrl: matchHighlightsUrl,
    matchCoverageUrl: matchCoverageUrl,
    parsePrediction: parsePrediction,
    sportGlyph: sportGlyph,
    sportLabel: sportLabel,
    sportColor: sportColor
  }
}
