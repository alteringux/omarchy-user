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

// ------------------------------------------------------------- parseScreenerQuote
// Shape confirmed live against the region-scoped day_gainers/day_losers-style
// screener query in bin/omarchy-stocks-refresh.
const RAW_SCREENER_ROW = {
  symbol: "ABCL",
  shortName: "AbCellera Biologics Inc.",
  regularMarketPrice: 12.5,
  regularMarketChangePercent: 17.8134,
  fiftyTwoWeekHigh: 12.5,
  fiftyTwoWeekLow: 2.745,
  exchange: "NCM"
}

test("parseScreenerQuote maps the screener's field names onto the common quote shape", () => {
  const q = Model.parseScreenerQuote(RAW_SCREENER_ROW)
  assert.strictEqual(q.symbol, "ABCL")
  assert.strictEqual(q.name, "AbCellera Biologics Inc.")
  assert.strictEqual(q.price, 12.5)
  assert.strictEqual(q.changePct, 17.8134)
  assert.strictEqual(q.week52High, 12.5)
  assert.strictEqual(q.week52Low, 2.745)
  assert.strictEqual(q.exchange, "NCM")
})

test("parseScreenerQuote returns nulls for a malformed row instead of throwing", () => {
  const q = Model.parseScreenerQuote({})
  assert.strictEqual(q.symbol, null)
  assert.strictEqual(q.price, null)
})

test("parseScreenerQuote threads the listing currency through (AUD for .AX)", () => {
  const q = Model.parseScreenerQuote({ symbol: "BAP.AX", currency: "AUD", regularMarketPrice: 8.02, regularMarketChangePercent: 8.02, exchange: "ASX" })
  assert.strictEqual(q.currency, "AUD")
})

// ------------------------------------------------------------ parseTrendingSymbols
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

// --------------------------------------------------------------- formatPrice
test("formatPrice prefixes AUD with A$ and USD (or missing) with $", () => {
  assert.strictEqual(Model.formatPrice(159.9, "AUD"), "A$159.90")
  assert.strictEqual(Model.formatPrice(231.4, "USD"), "$231.40")
  assert.strictEqual(Model.formatPrice(231.4, null), "$231.40")
})

test("formatPrice falls back to '<CODE> ' for a currency it has no symbol for", () => {
  assert.strictEqual(Model.formatPrice(142, "SEK"), "SEK 142.00")
})

test("formatPrice renders an em dash for a missing/NaN price", () => {
  assert.strictEqual(Model.formatPrice(null, "AUD"), "—")
  assert.strictEqual(Model.formatPrice(undefined, "USD"), "—")
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
    gainers: [RAW_SCREENER_ROW],
    losers: [],
    trending: RAW_TRENDING
  })
  const s = Model.parseState(raw)
  assert.strictEqual(s.updatedAt, "2026-01-01T00:00:00Z")
  assert.deepStrictEqual(s.gainers, [RAW_SCREENER_ROW])
})

test("parseState falls back to an empty gainers list when that field is malformed", () => {
  const s = Model.parseState(JSON.stringify({ gainers: "not an array" }))
  assert.deepStrictEqual(s.gainers, [])
})

test("parseState preserves cached quotes while exposing provider failure metadata", () => {
  const s = Model.parseState(JSON.stringify({
    updatedAt: "2026-01-01T00:00:00Z",
    gainers: [RAW_SCREENER_ROW],
    losers: [],
    stale: true,
    providerStatus: "error",
    providerError: "Yahoo Finance movers unavailable",
    checkedAt: "2026-01-01T00:05:00Z"
  }))
  assert.deepStrictEqual(s.gainers, [RAW_SCREENER_ROW])
  assert.strictEqual(s.updatedAt, "2026-01-01T00:00:00Z")
  assert.strictEqual(s.stale, true)
  assert.strictEqual(s.providerStatus, "error")
  assert.strictEqual(s.providerError, "Yahoo Finance movers unavailable")
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
