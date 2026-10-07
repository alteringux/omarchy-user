// Pure logic for the stocks plugin: parsing Yahoo Finance's unofficial
// (undocumented, no API key) screener response shape into a common quote
// shape, formatting, 52-week-range filtering, and mover selection. Kept free
// of QML/Quickshell APIs so it can be reasoned about (and tested) in
// isolation — see ADR: the refresh script under bin/ only fetches and
// bundles raw Yahoo JSON; all the shape-specific parsing lives here so a
// future break in Yahoo's undocumented shape is a one-file fix.
//
// The plugin shows global top-10 gainers/losers (bin/omarchy-stocks-refresh
// merges per-region screener results), not a personal watchlist.

var NEAR_EDGE_FRACTION = 0.1 // "near 52w high/low" = top/bottom 10% of the range

var FILTER_ALL = "all"
var FILTER_NEAR_HIGH = "nearHigh"
var FILTER_NEAR_LOW = "nearLow"

function defaultState() {
  return { version: 1, updatedAt: null, gainers: [], losers: [], trending: [] }
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
    if (Array.isArray(parsed.gainers)) state.gainers = parsed.gainers
    if (Array.isArray(parsed.losers)) state.losers = parsed.losers
    if (parsed.trending !== undefined) state.trending = parsed.trending
    if (typeof parsed.stale === "boolean") state.stale = parsed.stale
    if (typeof parsed.providerStatus === "string") state.providerStatus = parsed.providerStatus
    if (parsed.providerError === null || typeof parsed.providerError === "string") state.providerError = parsed.providerError
    if (typeof parsed.checkedAt === "string") state.checkedAt = parsed.checkedAt
  } catch (e) {
    console.warn("stocks: state parse failed:", e)
  }
  return state
}

// ---------------------------------------------------------------- parsing
// Raw shape: one row of `finance.result[0].quotes[]` from Yahoo's screener
// endpoint (bin/omarchy-stocks-refresh queries it once per region — US, GB,
// DE, JP, AU, HK, CA — and merges/re-sorts the results into global top-10
// gainers/losers before writing state). `exchange` is threaded through so
// the panel can show which market a mover trades on.
function parseScreenerQuote(raw) {
  if (!raw || !raw.symbol) return { symbol: null, name: null, price: null, changePct: null, week52High: null, week52Low: null, currency: null, exchange: null }
  return {
    symbol: raw.symbol,
    name: raw.shortName || raw.longName || raw.symbol,
    price: raw.regularMarketPrice !== undefined ? raw.regularMarketPrice : null,
    changePct: raw.regularMarketChangePercent !== undefined ? raw.regularMarketChangePercent : null,
    week52High: raw.fiftyTwoWeekHigh !== undefined ? raw.fiftyTwoWeekHigh : null,
    week52Low: raw.fiftyTwoWeekLow !== undefined ? raw.fiftyTwoWeekLow : null,
    currency: raw.currency || null,
    exchange: raw.exchange || null
  }
}

// Raw shape: the trimmed JSON array bin/omarchy-stocks-search prints, itself
// derived from query1.finance.yahoo.com/v1/finance/trending/US. Bare symbols
// only — no price data, shown as click-to-open pills in the panel.
function parseTrendingSymbols(raw, limit) {
  var quotes = raw && raw.finance && raw.finance.result && raw.finance.result[0] && raw.finance.result[0].quotes
  if (!quotes) return []
  var symbols = quotes.map(function (q) { return q.symbol }).filter(function (s) { return !!s })
  return limit ? symbols.slice(0, limit) : symbols
}

// ------------------------------------------------------------- formatting
// Map a Yahoo currency code onto a short display prefix. Unknown codes fall
// back to "<CODE> " (e.g. "SEK 142.00") rather than a wrong symbol. Added so
// .AX (AUD) movers don't render a misleading "$".
var CURRENCY_PREFIX = {
  USD: "$", AUD: "A$", NZD: "NZ$", CAD: "C$", SGD: "S$", HKD: "HK$",
  GBP: "£", EUR: "€", JPY: "¥", CNY: "¥", INR: "₹", CHF: "CHF ", ZAR: "R "
}

function currencyPrefix(code) {
  if (!code) return "$"
  if (CURRENCY_PREFIX.hasOwnProperty(code)) return CURRENCY_PREFIX[code]
  return code + " "
}

// Price with a currency-aware prefix. "—" for a missing/NaN price so callers
// don't have to special-case it. GBp (pence) quotes pass through as-is —
// rare and not worth a /100 special case.
function formatPrice(price, currency) {
  if (price === null || price === undefined || isNaN(price)) return "—"
  return currencyPrefix(currency) + Number(price).toFixed(2)
}

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

// Exposed only for the Node test harness under test/; QML's JS import
// mechanism has no `module` global, so this is a no-op there.
if (typeof module !== "undefined") {
  module.exports = {
    FILTER_ALL: FILTER_ALL,
    FILTER_NEAR_HIGH: FILTER_NEAR_HIGH,
    FILTER_NEAR_LOW: FILTER_NEAR_LOW,
    defaultState: defaultState,
    parseState: parseState,
    parseScreenerQuote: parseScreenerQuote,
    parseTrendingSymbols: parseTrendingSymbols,
    currencyPrefix: currencyPrefix,
    formatPrice: formatPrice,
    formatChangePct: formatChangePct,
    changeDirection: changeDirection,
    week52Position: week52Position,
    passes52wFilter: passes52wFilter,
    topMover: topMover,
    worstMover: worstMover,
    biggestMoverAbs: biggestMoverAbs
  }
}
