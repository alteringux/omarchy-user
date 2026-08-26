// Pure logic for the stocks plugin: parsing Yahoo Finance's unofficial
// (undocumented, no API key) response shapes into one common quote shape,
// formatting, 52-week-range filtering, mover selection, sparkline geometry,
// and watchlist list management. Kept free of QML/Quickshell APIs so it can
// be reasoned about (and tested) in isolation — see ADR: the refresh script
// under bin/ only fetches and bundles raw Yahoo JSON; all the shape-specific
// parsing lives here so a future break in Yahoo's undocumented shape is a
// one-file fix.

var NEAR_EDGE_FRACTION = 0.1 // "near 52w high/low" = top/bottom 10% of the range

var FILTER_ALL = "all"
var FILTER_NEAR_HIGH = "nearHigh"
var FILTER_NEAR_LOW = "nearLow"

function defaultWatchlist() {
  return { version: 1, tickers: [] }
}

function defaultState() {
  return { version: 1, updatedAt: null, watchlist: {}, gainers: [], losers: [], trending: [] }
}

// Tolerant parse: missing/malformed sections fall back to empty defaults
// rather than throwing, so a half-written or stale state file never crashes
// the panel. Same convention as alteringux.dashboard's Model.parseState.
function parseState(raw) {
  var state = defaultState()
  if (!raw || raw.length === 0) return state
  try {
    var parsed = JSON.parse(raw)
    state.updatedAt = parsed.updatedAt || null
    if (parsed.watchlist && typeof parsed.watchlist === "object") state.watchlist = parsed.watchlist
    if (Array.isArray(parsed.gainers)) state.gainers = parsed.gainers
    if (Array.isArray(parsed.losers)) state.losers = parsed.losers
    if (parsed.trending !== undefined) state.trending = parsed.trending
  } catch (e) {
    console.warn("stocks: state parse failed:", e)
  }
  return state
}

// ---------------------------------------------------------------- parsing
// Raw shape: query1.finance.yahoo.com/v8/finance/chart/<TICKER>. `chart`
// bundles a live quote (via `meta`) and same-day intraday closes (via
// `indicators.quote[0].close`) in a single call, which is why this is the
// only endpoint the watchlist needs.
// `fallbackSymbol` covers a failed/malformed fetch, where Yahoo's response
// carries no `meta.symbol` to identify which watchlist ticker it was for —
// the caller (BarWidget.qml) knows that from the ticker it requested, so it
// passes it through here rather than patching the result after the fact.
function parseChartQuote(raw, fallbackSymbol) {
  var result = raw && raw.chart && raw.chart.result && raw.chart.result[0]
  if (!result || !result.meta) {
    return { symbol: fallbackSymbol || null, name: null, price: null, prevClose: null, changePct: null, week52High: null, week52Low: null, series: [], ok: false }
  }
  var meta = result.meta
  var closes = (result.indicators && result.indicators.quote && result.indicators.quote[0] && result.indicators.quote[0].close) || []
  var series = closes.filter(function (c) { return c !== null && c !== undefined })
  var price = meta.regularMarketPrice
  var prevClose = meta.previousClose !== undefined ? meta.previousClose : meta.chartPreviousClose
  var changePct = (price !== undefined && prevClose) ? ((price - prevClose) / prevClose) * 100 : null

  return {
    symbol: meta.symbol || fallbackSymbol || null,
    name: meta.shortName || meta.longName || meta.symbol || null,
    price: price !== undefined ? price : null,
    prevClose: prevClose !== undefined ? prevClose : null,
    changePct: changePct,
    week52High: meta.fiftyTwoWeekHigh !== undefined ? meta.fiftyTwoWeekHigh : null,
    week52Low: meta.fiftyTwoWeekLow !== undefined ? meta.fiftyTwoWeekLow : null,
    series: series,
    ok: true
  }
}

// Raw shape: one row of `finance.result[0].quotes[]` from the
// day_gainers/day_losers screener endpoint. Field names differ from the
// chart endpoint's `meta` (regularMarketChangePercent is precomputed here,
// vs. derived from price/prevClose above) but map onto the same common shape.
function parseScreenerQuote(raw) {
  if (!raw || !raw.symbol) return { symbol: null, name: null, price: null, changePct: null, week52High: null, week52Low: null }
  return {
    symbol: raw.symbol,
    name: raw.shortName || raw.longName || raw.symbol,
    price: raw.regularMarketPrice !== undefined ? raw.regularMarketPrice : null,
    changePct: raw.regularMarketChangePercent !== undefined ? raw.regularMarketChangePercent : null,
    week52High: raw.fiftyTwoWeekHigh !== undefined ? raw.fiftyTwoWeekHigh : null,
    week52Low: raw.fiftyTwoWeekLow !== undefined ? raw.fiftyTwoWeekLow : null
  }
}

// Raw shape: query1.finance.yahoo.com/v1/finance/trending/US. Bare symbols
// only — no price data, so these are shown as add-to-watchlist pills, not
// priced cards, to avoid a chart call per trending symbol on every refresh.
function parseTrendingSymbols(raw, limit) {
  var quotes = raw && raw.finance && raw.finance.result && raw.finance.result[0] && raw.finance.result[0].quotes
  if (!quotes) return []
  var symbols = quotes.map(function (q) { return q.symbol }).filter(function (s) { return !!s })
  return limit ? symbols.slice(0, limit) : symbols
}

// ------------------------------------------------------------- formatting
function formatChangePct(pct) {
  if (pct === null || pct === undefined || isNaN(pct)) return "—"
  var sign = pct >= 0 ? "+" : ""
  return sign + pct.toFixed(2) + "%"
}

function changeDirection(pct) {
  if (!pct) return "flat"
  if (pct > 0) return "up"
  if (pct < 0) return "down"
  return "flat"
}

// ------------------------------------------------------------------- 52w
// Fraction (0..1) of where `price` sits between `low` and `high`, clamped.
// null when the range is missing or degenerate (low === high).
function week52Position(price, low, high) {
  if (low === null || low === undefined || high === null || high === undefined) return null
  if (high === low) return null
  var frac = (price - low) / (high - low)
  return Math.max(0, Math.min(1, frac))
}

// filterMode: FILTER_ALL | FILTER_NEAR_HIGH | FILTER_NEAR_LOW
function passes52wFilter(quote, filterMode) {
  if (!filterMode || filterMode === FILTER_ALL) return true
  var pos = week52Position(quote.price, quote.week52Low, quote.week52High)
  if (pos === null) return false
  if (filterMode === FILTER_NEAR_HIGH) return pos >= 1 - NEAR_EDGE_FRACTION
  if (filterMode === FILTER_NEAR_LOW) return pos <= NEAR_EDGE_FRACTION
  return true
}

// ----------------------------------------------------------------- movers
function validQuotes(quotes) {
  return (quotes || []).filter(function (q) { return q && q.changePct !== null && q.changePct !== undefined && !isNaN(q.changePct) })
}

function topMover(quotes) {
  var valid = validQuotes(quotes)
  if (valid.length === 0) return null
  return valid.reduce(function (a, b) { return b.changePct > a.changePct ? b : a })
}

function worstMover(quotes) {
  var valid = validQuotes(quotes)
  if (valid.length === 0) return null
  return valid.reduce(function (a, b) { return b.changePct < a.changePct ? b : a })
}

function biggestMoverAbs(quotes) {
  var valid = validQuotes(quotes)
  if (valid.length === 0) return null
  return valid.reduce(function (a, b) { return Math.abs(b.changePct) > Math.abs(a.changePct) ? b : a })
}

// -------------------------------------------------------------- sparkline
// SVG path geometry for a card's mini price chart. Purely decorative data
// in -> path string out; no DOM/QML dependency so it's testable here.
function sparklinePath(series, width, height) {
  if (!series || series.length < 2) return ""
  var min = Math.min.apply(null, series)
  var max = Math.max.apply(null, series)
  var span = max - min

  var points = series.map(function (v, i) {
    var x = (i / (series.length - 1)) * width
    var y = span === 0 ? height / 2 : height - ((v - min) / span) * height
    return { x: x, y: y }
  })

  return points.map(function (p, i) {
    return (i === 0 ? "M" : "L") + round2(p.x) + "," + round2(p.y)
  }).join(" ")
}

function round2(n) {
  return Math.round(n * 100) / 100
}

// -------------------------------------------------------------- watchlist
function normalizeTicker(input) {
  var t = (input || "").trim().toUpperCase()
  return t.length > 0 ? t : null
}

function addTicker(watchlist, symbol) {
  var normalized = normalizeTicker(symbol)
  var tickers = (watchlist && watchlist.tickers) ? watchlist.tickers.slice() : []
  if (!normalized) return { version: 1, tickers: tickers }
  var exists = tickers.some(function (t) { return t.toUpperCase() === normalized })
  if (!exists) tickers.push(normalized)
  return { version: 1, tickers: tickers }
}

function removeTicker(watchlist, symbol) {
  var normalized = normalizeTicker(symbol)
  var tickers = (watchlist && watchlist.tickers) ? watchlist.tickers.slice() : []
  return { version: 1, tickers: tickers.filter(function (t) { return t.toUpperCase() !== normalized }) }
}

// Exposed only for the Node test harness under test/; QML's JS import
// mechanism has no `module` global, so this is a no-op there.
if (typeof module !== "undefined") {
  module.exports = {
    FILTER_ALL: FILTER_ALL,
    FILTER_NEAR_HIGH: FILTER_NEAR_HIGH,
    FILTER_NEAR_LOW: FILTER_NEAR_LOW,
    defaultWatchlist: defaultWatchlist,
    defaultState: defaultState,
    parseState: parseState,
    parseChartQuote: parseChartQuote,
    parseScreenerQuote: parseScreenerQuote,
    parseTrendingSymbols: parseTrendingSymbols,
    formatChangePct: formatChangePct,
    changeDirection: changeDirection,
    week52Position: week52Position,
    passes52wFilter: passes52wFilter,
    topMover: topMover,
    worstMover: worstMover,
    biggestMoverAbs: biggestMoverAbs,
    sparklinePath: sparklinePath,
    normalizeTicker: normalizeTicker,
    addTicker: addTicker,
    removeTicker: removeTicker
  }
}
