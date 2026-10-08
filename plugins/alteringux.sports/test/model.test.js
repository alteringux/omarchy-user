// Plain-node tests for the pure logic in Model.js. Run with:
//   node test/model.test.js
// Model.js exposes a guarded `module.exports` at the bottom purely for this
// harness; that export is a no-op inside QML.
const assert = require("assert")
const Model = require("../Model.js")

function test(name, fn) {
  try { fn(); console.log("ok   - " + name) }
  catch (e) { console.log("FAIL - " + name); console.log("       " + (e && e.message || e)); process.exitCode = 1 }
}

// ---------------------------------------------------------------- parseState
// Same tolerant-parse convention as the stocks/newsbar models: a malformed
// or half-written state file falls back to defaults per-field instead of
// throwing and blanking the panel.
test("parseState returns defaults for empty input", () => {
  assert.deepStrictEqual(Model.parseState(""), Model.defaultState())
})

test("parseState returns defaults for unparseable JSON instead of throwing", () => {
  assert.deepStrictEqual(Model.parseState("{not json"), Model.defaultState())
})

test("parseState reads a well-formed state file", () => {
  const st = Model.parseState(JSON.stringify({
    version: 1, updatedAt: "2026-09-13T10:00:00Z",
    matchDataUpdatedAt: "2026-09-12T20:00:00Z",
    articleDataUpdatedAt: "2026-09-12T19:00:00Z",
    refreshHealth: { usedCachedMatches: true, usedCachedArticles: false },
    live: [{ id: "1", sport: "Rugby", homeTeam: "A", awayTeam: "B", homeScore: 10, awayScore: 7, status: "2H", elapsed: 62 }],
    upcoming: [{ id: "2", sport: "Rugby", homeTeam: "A", awayTeam: "C", dateEvent: "2026-09-20", strTimestamp: "2026-09-20T15:00:00" }],
    results: [{ id: "3", sport: "Rugby", homeTeam: "A", awayTeam: "D", dateEvent: "2026-09-06", homeScore: 20, awayScore: 15 }],
    players: { Rugby: [{ idPlayer: "9", strPlayer: "X" }] },
    standings: { Soccer: [{ intRank: "1", strTeam: "Liverpool", intPoints: "84" }] },
    predictions: {},
    articles: [{ title: "UFC preview", url: "https://example.test/ufc" }],
    teams: { "9": { idTeam: "9", strTeam: "Arsenal", strTeamBadge: "https://example.test/badge.png" } }
  }))
  assert.strictEqual(st.updatedAt, "2026-09-13T10:00:00Z")
  assert.strictEqual(st.matchDataUpdatedAt, "2026-09-12T20:00:00Z")
  assert.strictEqual(st.articleDataUpdatedAt, "2026-09-12T19:00:00Z")
  assert.deepStrictEqual(st.refreshHealth, { usedCachedMatches: true, usedCachedArticles: false })
  assert.strictEqual(st.live.length, 1)
  assert.strictEqual(st.upcoming.length, 1)
  assert.strictEqual(st.results.length, 1)
  assert.strictEqual(st.players.Rugby.length, 1)
  assert.strictEqual(st.standings.Soccer.length, 1)
  assert.strictEqual(st.teams["9"].strTeam, "Arsenal")
})

test("parseState falls back to empty lists when a section is malformed", () => {
  const st = Model.parseState(JSON.stringify({
    version: 1, updatedAt: "2026-09-13T10:00:00Z",
    live: "not-a-list", upcoming: 42, results: null,
    players: "x", standings: []
  }))
  assert.deepStrictEqual(st.live, [])
  assert.deepStrictEqual(st.upcoming, [])
  assert.deepStrictEqual(st.results, [])
  assert.deepStrictEqual(st.players, {})
  assert.deepStrictEqual(st.standings, {})
})

test("parseState drops malformed rows without discarding valid panel data", () => {
  const st = Model.parseState(JSON.stringify({
    live: [null, "broken", { id: "live-1", status: "2H" }],
    articles: [{ title: "Story" }, 17],
    teams: { Arsenal: null, Chelsea: { sport: "Soccer" } }
  }))
  assert.deepStrictEqual(st.live, [{ id: "live-1", status: "2H" }])
  assert.deepStrictEqual(st.articles, [{ title: "Story" }])
  assert.deepStrictEqual(st.teams, { Chelsea: { sport: "Soccer" } })
})

test("parseState keeps updatedAt null when missing", () => {
  assert.strictEqual(Model.parseState("{}").updatedAt, null)
})

// ------------------------------------------------------------------ formatScore
test("formatScore renders two integers joined by an en dash", () => {
  assert.strictEqual(Model.formatScore(24, 18), "24 – 18")
})

test("formatScore renders an em dash for a missing score", () => {
  assert.strictEqual(Model.formatScore(null, 3), "—")
  assert.strictEqual(Model.formatScore(0, undefined), "—")
})

test("formatScore renders zero-zero as a real score", () => {
  assert.strictEqual(Model.formatScore(0, 0), "0 – 0")
})

// ------------------------------------------------------------- formatMatchTime
test("formatMatchTime maps status words straight through", () => {
  assert.strictEqual(Model.formatMatchTime("HT"), "HT")
  assert.strictEqual(Model.matchStarted("HT"), true)
  assert.strictEqual(Model.matchEnded("FT"), true)
  assert.strictEqual(Model.matchEnded("Match Finished"), true)
  assert.strictEqual(Model.matchStarted("NS"), false)
  assert.strictEqual(Model.matchEnded("NS"), false)
})

test("formatMatchTime renders elapsed minutes for in-play matches", () => {
  assert.strictEqual(Model.formatMatchTime("1H", 23), "23'")
  assert.strictEqual(Model.formatMatchTime("2H", 62), "62'")
})

test("formatMatchTime falls back to the raw status when nothing else fits", () => {
  assert.strictEqual(Model.formatMatchTime("Postponed", null), "Postponed")
  assert.strictEqual(Model.formatMatchTime(null, null), "")
})
test("matchEnded recognizes terminal non-live statuses case-insensitively", () => {
  assert.strictEqual(Model.matchEnded("postponed"), true)
  assert.strictEqual(Model.matchEnded("CANCELLED"), true)
  assert.strictEqual(Model.matchEnded("2H"), false)
})


// ------------------------------------------------------------------ favourites
test("isFavourite matches by team name case-insensitively", () => {
  assert.strictEqual(Model.isFavourite("Arsenal", ["arsenal", "Boston Celtics"]), true)
  assert.strictEqual(Model.isFavourite("Leicester Tigers", ["Leicester Tigers"]), true)
  assert.strictEqual(Model.isFavourite("Chelsea", []), false)
  assert.strictEqual(Model.isFavourite(null, ["Arsenal"]), false)
})

test("matchTouchesFavourite checks both sides", () => {
  const m = { homeTeam: "Arsenal", awayTeam: "Chelsea" }
  assert.strictEqual(Model.matchTouchesFavourite(m, ["Chelsea"]), true)
  assert.strictEqual(Model.matchTouchesFavourite(m, ["Liverpool"]), false)
})

// ------------------------------------------------------------- bar widget feed
test("barSummary prefers a favourite team's live match", () => {
  const state = {
    updatedAt: "2026-09-13T10:00:00Z",
    live: [
      { sport: "Soccer", homeTeam: "Someone", awayTeam: "Else", homeScore: null, awayScore: null, status: "NS" },
      { sport: "Soccer", homeTeam: "Arsenal", awayTeam: "Chelsea", homeScore: 1, awayScore: 0, status: "2H", elapsed: 63 }
    ],
    upcoming: [],
    results: []
  }
  const s = Model.barSummary(state, ["Chelsea"])
  assert.strictEqual(s.mode, "live")
  assert.strictEqual(s.match.homeTeam, "Arsenal")
  assert.strictEqual(s.text, "Arsenal 1 – 0 Chelsea")
  assert.strictEqual(s.liveCount, 2)
})

test("barSummary never promotes a terminal live-feed row", () => {
  const s = Model.barSummary({
    live: [{ homeTeam: "Finished", awayTeam: "Game", status: "FT", homeScore: 2, awayScore: 1 }],
    upcoming: [],
  }, [])
  assert.strictEqual(s.mode, "idle")
  assert.strictEqual(s.liveCount, 0)
})

test("barSummary falls back to the next upcoming favourite match", () => {
  const state = {
    updatedAt: "2026-09-13T10:00:00Z", live: [],
    upcoming: [
      { sport: "Rugby", homeTeam: "Harlequins", awayTeam: "Bath Rugby", dateEvent: "2026-09-25", strTimestamp: "2026-09-25T18:45:00" },
      { sport: "Soccer", homeTeam: "Arsenal", awayTeam: "Fulham", dateEvent: "2026-09-15", strTimestamp: "2026-09-15T19:00:00" }
    ], results: []
  }
  const s = Model.barSummary(state, ["Arsenal"])
  assert.strictEqual(s.mode, "next")
  assert.strictEqual(s.match.homeTeam, "Arsenal")
  assert.ok(s.text.indexOf("Arsenal") !== -1)
})

test("barSummary falls back to a plain count when nothing matches", () => {
  const s = Model.barSummary(Model.defaultState(), [])
  assert.strictEqual(s.mode, "idle")
  assert.strictEqual(s.liveCount, 0)
})

// ------------------------------------------------------------- sorting helpers
test("matchTime sorts by strTimestamp falling back to dateEvent", () => {
  assert.strictEqual(Model.matchTime({ strTimestamp: "2026-09-15T19:00:00", dateEvent: "2026-09-15" }), Date.parse("2026-09-15T19:00:00"))
  assert.strictEqual(Model.matchTime({ dateEvent: "2026-09-15" }), Date.parse("2026-09-15"))
  assert.strictEqual(Model.matchTime({}), Infinity)
})

test("sortUpcoming orders soonest first", () => {
  const a = { strTimestamp: "2026-09-16T12:00:00" }
  const b = { strTimestamp: "2026-09-15T12:00:00" }
  assert.deepStrictEqual(Model.sortUpcoming([a, b]), [b, a])
})

// ------------------------------------------------------------ prediction parse
test("parsePrediction extracts the display fields from the CLI's JSON", () => {
  const p = Model.parsePrediction(JSON.stringify({
    version: 1, sport: "Rugby",
    homeTeam: "Leicester Tigers", awayTeam: "Bath Rugby",
    predictedWinner: "Leicester Tigers", confidence: 0.62,
    breakdown: { form: 0.55, h2h: 0.4, home: 0.2, standing: 0.3 },
    error: null
  }))
  assert.strictEqual(p.predictedWinner, "Leicester Tigers")
  assert.strictEqual(p.confidence, 0.62)
  assert.strictEqual(p.sport, "Rugby")
})

test("parsePrediction returns null for empty or malformed output", () => {
  assert.strictEqual(Model.parsePrediction(""), null)
  assert.strictEqual(Model.parsePrediction("nope"), null)
  assert.strictEqual(Model.parsePrediction(null), null)
})

test("parsePrediction surfaces the error message when the CLI failed", () => {
  const p = Model.parsePrediction(JSON.stringify({ error: "no standings data for team" }))
  assert.strictEqual(p.error, "no standings data for team")
  assert.strictEqual(p.predictedWinner, null)
})

// ---------------------------------------------------------------- sportGlyph
test("sportGlyph maps known sports to nerd-font glyphs", () => {
  assert.strictEqual(Model.sportGlyph("Soccer"), "󰧑")
  assert.strictEqual(Model.sportGlyph("Rugby"), "󰣇")
  assert.strictEqual(Model.sportGlyph("Basketball"), "󰖄")
})

test("sportGlyph falls back to the trophy for unknown sports", () => {
  assert.strictEqual(Model.sportGlyph("Hurling"), "󰜺")
  assert.strictEqual(Model.sportGlyph(""), "󰜺")
})

test("sport metadata includes UFC and visual accent colors", () => {
  assert.strictEqual(Model.sportLabel("Fighting"), "UFC / MMA")
  assert.strictEqual(Model.sportGlyph("Fighting"), "󰒃")
  assert.strictEqual(Model.sportColor("Fighting"), "#FF0066")
  assert.notStrictEqual(Model.sportColor("Golf"), Model.sportColor("Soccer"))
})

test("match media helpers preserve provider links and generate legal searches", () => {
  const match = { sport: "Soccer", homeTeam: "Arsenal", awayTeam: "Chelsea" }
  assert.match(Model.matchHighlightsUrl(match), /^https:\/\/www\.youtube\.com\/results\?search_query=/)
  assert.match(Model.matchCoverageUrl(match), /^https:\/\/www\.youtube\.com\/results\?search_query=/)
  assert.strictEqual(
    Model.matchHighlightsUrl({ youtubeHighlightsUrl: "https://youtube.com/watch?v=1" }),
    "https://youtube.com/watch?v=1"
  )
})

test("predictionForMatch finds persisted predictions by normalized matchup", () => {
  const prediction = { predictedWinner: "Arsenal", confidence: 0.72, reason: "Recent form favors Arsenal." }
  const state = { predictions: { "soccer|arsenal|chelsea": prediction } }
  assert.strictEqual(
    Model.predictionForMatch(state, { sport: "Soccer", homeTeam: " Arsenal ", awayTeam: "Chelsea" }),
    prediction
  )
})


// --------------------------------------------------------------- match summary
test("formatMatchLabel composes the two team names", () => {
  assert.strictEqual(Model.formatMatchLabel({ homeTeam: "Arsenal", awayTeam: "Chelsea" }), "Arsenal vs Chelsea")
})

test("formatMatchLabel uses the UFC event name when teams are absent", () => {
  assert.strictEqual(
    Model.formatMatchLabel({ sport: "Fighting", eventName: "UFC Fight Night", homeTeam: null, awayTeam: null }),
    "UFC Fight Night vs Fight card"
  )
})

test("formatMatchDate renders a short friendly date", () => {
  assert.strictEqual(Model.formatMatchDate("2026-09-20"), "20 Sep")
})

test("formatMatchTimeOfDay renders a 24h time from the timestamp", () => {
  assert.strictEqual(Model.formatMatchTimeOfDay({ strTimestamp: "2026-09-25T18:45:00" }), "18:45")
})

console.log("")
console.log(process.exitCode ? "model.test.js FAILED" : "model.test.js passed")
