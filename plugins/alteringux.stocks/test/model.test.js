// Plain-node tests for the pure logic in Model.js. Run with:
//   node test/model.test.js
// Model.js has no module system of its own (it's loaded as a QML JS
// import), so it exposes a guarded `module.exports` at the bottom purely
// for this test harness; that export is a no-op inside QML.
const assert = require("assert")
const Model = require("../Model.js")

function test(name, fn) {
  try {
    fn()
    console.log("ok - " + name)
  } catch (e) {
    console.error("FAIL - " + name)
    console.error(e)
    process.exitCode = 1
  }
}

// ---------------------------------------------------------- parseChartQuote
// Shape confirmed live against query1.finance.yahoo.com/v8/finance/chart/<T>.
const RAW_CHART_AAPL = {
  chart: {
    result: [{
      meta: {
        symbol: "AAPL",
        shortName: "Apple Inc.",
        regularMarketPrice: 231.42,
        previousClose: 227.30,
        fiftyTwoWeekHigh: 260.10,
        fiftyTwoWeekLow: 164.08
      },
      timestamp: [1, 2, 3, 4, 5],
      indicators: { quote: [{ close: [225.0, null, 228.5, 230.1, 231.42] }] }
    }]
  }
}

test("parseChartQuote extracts price/prevClose/52w range and drops null closes from the series", () => {
  const q = Model.parseChartQuote(RAW_CHART_AAPL)
  assert.strictEqual(q.symbol, "AAPL")
  assert.strictEqual(q.price, 231.42)
  assert.strictEqual(q.prevClose, 227.30)
  assert.strictEqual(q.week52High, 260.10)
  assert.strictEqual(q.week52Low, 164.08)
  assert.deepStrictEqual(q.series, [225.0, 228.5, 230.1, 231.42])
  assert.strictEqual(q.ok, true)
  assert.ok(Math.abs(q.changePct - ((231.42 - 227.30) / 227.30) * 100) < 1e-9)
})

test("parseChartQuote marks a malformed/error response as not ok instead of throwing", () => {
  const q = Model.parseChartQuote({ chart: { result: null, error: { description: "No data found" } } })
  assert.strictEqual(q.ok, false)
  assert.strictEqual(q.price, null)
  assert.deepStrictEqual(q.series, [])
})

test("parseChartQuote falls back to the requested ticker's symbol when the fetch failed", () => {
  const q = Model.parseChartQuote(null, "AAPL")
  assert.strictEqual(q.symbol, "AAPL")
  assert.strictEqual(q.ok, false)
})

test("parseChartQuote prefers Yahoo's own symbol over the fallback when the fetch succeeded", () => {
  const q = Model.parseChartQuote(RAW_CHART_AAPL, "aapl-typed-differently")
  assert.strictEqual(q.symbol, "AAPL")
})

// ------------------------------------------------------------- parseScreenerQuote
// Shape confirmed live against the day_gainers/day_losers screener endpoint.
const RAW_SCREENER_ROW = {
  symbol: "ABCL",
  shortName: "AbCellera Biologics Inc.",
  regularMarketPrice: 12.5,
  regularMarketChangePercent: 17.8134,
  fiftyTwoWeekHigh: 12.5,
  fiftyTwoWeekLow: 2.745
}

test("parseScreenerQuote maps the screener's field names onto the common quote shape", () => {
  const q = Model.parseScreenerQuote(RAW_SCREENER_ROW)
  assert.strictEqual(q.symbol, "ABCL")
  assert.strictEqual(q.name, "AbCellera Biologics Inc.")
  assert.strictEqual(q.price, 12.5)
  assert.strictEqual(q.changePct, 17.8134)
  assert.strictEqual(q.week52High, 12.5)
  assert.strictEqual(q.week52Low, 2.745)
})

// ------------------------------------------------------ parseTrendingSymbols
// Shape confirmed live against query1.finance.yahoo.com/v1/finance/trending/US.
const RAW_TRENDING = {
  finance: { result: [{ quotes: [{ symbol: "DKS" }, { symbol: "INTU" }, { symbol: "ZM" }, { symbol: "OKLO" }] }] }
}

test("parseTrendingSymbols returns bare symbols capped at the given limit", () => {
  assert.deepStrictEqual(Model.parseTrendingSymbols(RAW_TRENDING, 2), ["DKS", "INTU"])
})

test("parseTrendingSymbols returns an empty list for a malformed response", () => {
  assert.deepStrictEqual(Model.parseTrendingSymbols({}, 5), [])
})

// ------------------------------------------------------------- parseState
// Same tolerant-parse convention as alteringux.dashboard's Model.parseState:
// a malformed/half-written state file falls back to defaults per-field
// instead of throwing and blanking the whole panel.
test("parseState returns defaults for empty input", () => {
  assert.deepStrictEqual(Model.parseState(""), Model.defaultState())
})

test("parseState returns defaults for unparseable JSON instead of throwing", () => {
  assert.deepStrictEqual(Model.parseState("{not json"), Model.defaultState())
})

test("parseState reads a well-formed state file", () => {
  const raw = JSON.stringify({
    updatedAt: "2026-01-01T00:00:00Z",
    watchlist: { AAPL: RAW_CHART_AAPL },
    gainers: [RAW_SCREENER_ROW],
    losers: [],
    trending: RAW_TRENDING
  })
  const s = Model.parseState(raw)
  assert.strictEqual(s.updatedAt, "2026-01-01T00:00:00Z")
  assert.deepStrictEqual(s.watchlist, { AAPL: RAW_CHART_AAPL })
  assert.deepStrictEqual(s.gainers, [RAW_SCREENER_ROW])
})

test("parseState falls back to an empty gainers list when that field is malformed", () => {
  const s = Model.parseState(JSON.stringify({ gainers: "not an array" }))
  assert.deepStrictEqual(s.gainers, [])
})

// ------------------------------------------------------------- formatting
test("formatChangePct signs positive values and keeps two decimals", () => {
  assert.strictEqual(Model.formatChangePct(1.8), "+1.80%")
})

test("formatChangePct signs negative values", () => {
  assert.strictEqual(Model.formatChangePct(-3.4), "-3.40%")
})

test("formatChangePct renders an em dash for a missing value", () => {
  assert.strictEqual(Model.formatChangePct(null), "—")
})

test("changeDirection classifies up/down/flat", () => {
  assert.strictEqual(Model.changeDirection(0.01), "up")
  assert.strictEqual(Model.changeDirection(-0.01), "down")
  assert.strictEqual(Model.changeDirection(0), "flat")
  assert.strictEqual(Model.changeDirection(null), "flat")
})

// ------------------------------------------------------------------- 52w
test("week52Position places the price fractionally between low and high", () => {
  assert.strictEqual(Model.week52Position(150, 100, 200), 0.5)
  assert.strictEqual(Model.week52Position(100, 100, 200), 0)
  assert.strictEqual(Model.week52Position(200, 100, 200), 1)
})

test("week52Position clamps a price outside the recorded range instead of exceeding 0..1", () => {
  assert.strictEqual(Model.week52Position(250, 100, 200), 1)
  assert.strictEqual(Model.week52Position(50, 100, 200), 0)
})

test("week52Position returns null when low/high are missing or degenerate", () => {
  assert.strictEqual(Model.week52Position(150, null, 200), null)
  assert.strictEqual(Model.week52Position(150, 200, 200), null)
})

test("passes52wFilter FILTER_ALL accepts everything", () => {
  assert.strictEqual(Model.passes52wFilter({ price: 150, week52Low: 100, week52High: 200 }, Model.FILTER_ALL), true)
})

test("passes52wFilter FILTER_NEAR_HIGH accepts only quotes in the top 10% of their range", () => {
  assert.strictEqual(Model.passes52wFilter({ price: 195, week52Low: 100, week52High: 200 }, Model.FILTER_NEAR_HIGH), true)
  assert.strictEqual(Model.passes52wFilter({ price: 150, week52Low: 100, week52High: 200 }, Model.FILTER_NEAR_HIGH), false)
})

test("passes52wFilter FILTER_NEAR_LOW accepts only quotes in the bottom 10% of their range", () => {
  assert.strictEqual(Model.passes52wFilter({ price: 105, week52Low: 100, week52High: 200 }, Model.FILTER_NEAR_LOW), true)
  assert.strictEqual(Model.passes52wFilter({ price: 150, week52Low: 100, week52High: 200 }, Model.FILTER_NEAR_LOW), false)
})

test("passes52wFilter excludes quotes with no 52w range from nearHigh/nearLow", () => {
  assert.strictEqual(Model.passes52wFilter({ price: 150, week52Low: null, week52High: null }, Model.FILTER_NEAR_HIGH), false)
})

// ----------------------------------------------------------------- movers
const QUOTES = [
  { symbol: "A", changePct: 1.5 },
  { symbol: "B", changePct: -4.2 },
  { symbol: "C", changePct: 0.3 },
  { symbol: "D", changePct: null } // failed fetch, must be ignored
]

test("topMover picks the largest positive change, ignoring quotes with no data", () => {
  assert.strictEqual(Model.topMover(QUOTES).symbol, "A")
})

test("worstMover picks the most negative change", () => {
  assert.strictEqual(Model.worstMover(QUOTES).symbol, "B")
})

test("biggestMoverAbs picks the largest move in either direction", () => {
  assert.strictEqual(Model.biggestMoverAbs(QUOTES).symbol, "B")
})

test("topMover/worstMover/biggestMoverAbs return null for an empty or all-null list", () => {
  assert.strictEqual(Model.topMover([]), null)
  assert.strictEqual(Model.worstMover([{ symbol: "X", changePct: null }]), null)
  assert.strictEqual(Model.biggestMoverAbs([]), null)
})

// -------------------------------------------------------------- sparkline
test("sparklinePath draws one segment per point, spanning the full width", () => {
  const path = Model.sparklinePath([1, 2, 3, 2], 100, 20)
  assert.ok(path.startsWith("M0,"))
  assert.strictEqual((path.match(/L/g) || []).length, 3)
  assert.ok(path.includes("L100,"))
})

test("sparklinePath maps the lowest value to the bottom and highest to the top", () => {
  const path = Model.sparklinePath([0, 10], 100, 20)
  assert.strictEqual(path, "M0,20 L100,0")
})

test("sparklinePath returns an empty string for fewer than two points", () => {
  assert.strictEqual(Model.sparklinePath([], 100, 20), "")
  assert.strictEqual(Model.sparklinePath([5], 100, 20), "")
})

test("sparklinePath draws a flat centered line when every value is identical", () => {
  const path = Model.sparklinePath([5, 5, 5], 100, 20)
  assert.strictEqual(path, "M0,10 L50,10 L100,10")
})

// -------------------------------------------------------------- watchlist
test("normalizeTicker upper-cases and trims, rejecting blank input", () => {
  assert.strictEqual(Model.normalizeTicker("  aapl "), "AAPL")
  assert.strictEqual(Model.normalizeTicker(""), null)
  assert.strictEqual(Model.normalizeTicker("   "), null)
})

test("addTicker appends a normalized symbol and de-duplicates case-insensitively", () => {
  const wl = Model.defaultWatchlist()
  const wl2 = Model.addTicker(wl, "aapl")
  const wl3 = Model.addTicker(wl2, "AAPL")
  assert.deepStrictEqual(wl3.tickers, ["AAPL"])
})

test("addTicker ignores blank input", () => {
  const wl = Model.addTicker(Model.defaultWatchlist(), "   ")
  assert.deepStrictEqual(wl.tickers, [])
})

test("removeTicker drops a symbol case-insensitively", () => {
  const wl = Model.addTicker(Model.defaultWatchlist(), "TSLA")
  const wl2 = Model.removeTicker(wl, "tsla")
  assert.deepStrictEqual(wl2.tickers, [])
})

test("addTicker does not mutate the watchlist passed in", () => {
  const wl = Model.defaultWatchlist()
  Model.addTicker(wl, "NVDA")
  assert.deepStrictEqual(wl.tickers, [])
})
