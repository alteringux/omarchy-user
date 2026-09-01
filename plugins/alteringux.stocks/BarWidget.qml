import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Stocks bar widget: owns the watchlist (which tickers to track — config,
// written directly by this widget, same convention as alteringux.pomodoro)
// and a background refresh timer that shells out to
// bin/omarchy-stocks-refresh (Yahoo Finance's free/keyless endpoints) and
// writes quotes + market-wide movers/trending to a state file (same
// convention as alteringux.dashboard). The bar icon shows whichever
// watchlist ticker moved most since previous close; the popup panel shows
// the full card grid plus trending/movers.
BarWidget {
  id: root
  moduleName: "alteringux.stocks"

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/alteringux.stocks"
  readonly property string refreshScript: pluginDir + "/bin/omarchy-stocks-refresh"
  readonly property string searchScript: pluginDir + "/bin/omarchy-stocks-search"
  readonly property string engageScript: pluginDir + "/bin/omarchy-stocks-engage"

  // Four JSON files under ~/.local/state/omarchy/ (outside the plugin's own
  // source tree — the shell's plugin-file watcher would reload the widget on
  // every write). stocks.json / -engagement / -commentary are rewritten by
  // bin/omarchy-stocks-{refresh,engage,commentary}, so their Stores watch for
  // outside changes; the watchlist is plugin-owned.
  property alias state: stateStore.value
  property alias watchlistConfig: watchlistStore.value
  readonly property bool watchlistLoaded: watchlistStore.loaded
  property bool refreshing: false
  property alias engagement: engagementStore.value
  property alias commentary: commentaryStore.value

  // ---- ticker autocomplete (read by Panel.qml's Add field) -------------
  // Debounced results from bin/omarchy-stocks-search; each row is
  // {symbol,name,exchange,type} (see Model.parseSearchResults). Non-US
  // listings keep their suffix, so picking "BHP.AX" adds the ASX line.
  property var searchResults: []
  property string searchQuery: ""

  // ---- derived, read by Panel.qml -----------------------------------
  // Most-clicked tickers surface first — the panel's one piece of learned
  // behavior; see Model.sortByEngagement.
  readonly property var watchlistQuotes: Model.sortByEngagement(
    watchlistConfig.tickers.map(function (t) {
      var raw = root.state.watchlist ? root.state.watchlist[t] : null
      return Model.parseChartQuote(raw, t)
    }),
    root.engagement
  )
  readonly property var gainers: (state.gainers || []).map(Model.parseScreenerQuote)
  readonly property var losers: (state.losers || []).map(Model.parseScreenerQuote)
  readonly property var trendingSymbols: Model.parseTrendingSymbols(state.trending, 12)

  readonly property var biggestMover: Model.biggestMoverAbs(watchlistQuotes)

  // ---- bar-icon cycling ----------------------------------------------------
  // The bar icon rotates through every watchlist quote that has a live
  // change%, one every `cycleSeconds` (read from this widget's shell.json
  // layout entry, default 5), newest-engagement-first (watchlistQuotes is
  // already engagement-sorted). Put "cycle": false in the layout entry to pin
  // it to the single biggest mover instead. Scrolling the widget steps the
  // rotation by hand and nudges the timer.
  readonly property var cycleQuotes: watchlistQuotes.filter(function (q) {
    return q && q.changePct !== null && q.changePct !== undefined && !isNaN(q.changePct)
  })
  readonly property bool cycleEnabled: setting("cycle", true) && cycleQuotes.length > 1
  readonly property int cycleMs: Math.max(1, setting("cycleSeconds", 5)) * 1000
  property int cycleIndex: 0
  readonly property var currentQuote: cycleQuotes.length
    ? cycleQuotes[((cycleIndex % cycleQuotes.length) + cycleQuotes.length) % cycleQuotes.length]
    : biggestMover

  onCycleQuotesChanged: {
    if (cycleQuotes.length && cycleIndex >= cycleQuotes.length)
      cycleIndex = cycleIndex % cycleQuotes.length
  }

  function stepCycle(delta) {
    var n = cycleQuotes.length
    if (n < 1)
      return
    cycleIndex = (((cycleIndex + delta) % n) + n) % n
  }

  readonly property color upColor: "#3fb950"
  readonly property color downColor: bar ? bar.urgent : Color.urgent
  readonly property color neutralColor: bar ? bar.barForeground : Color.foreground
  readonly property color tickerColor: {
    var p = currentQuote ? currentQuote.changePct : null
    if (p === null || p === undefined || isNaN(p))
      return neutralColor
    return p > 0 ? upColor : (p < 0 ? downColor : neutralColor)
  }

  readonly property string displayText: currentQuote && currentQuote.symbol
    ? ("  " + currentQuote.symbol + " " + Model.formatChangePct(currentQuote.changePct))
    : "  Stocks"

  readonly property string tickerTooltip: currentQuote && currentQuote.symbol
    ? (currentQuote.symbol
       + (currentQuote.price !== null && currentQuote.price !== undefined ? "  " + Model.formatPrice(currentQuote.price, currentQuote.currency) : "")
       + "  " + Model.formatChangePct(currentQuote.changePct)
       + (currentQuote.name ? "\n" + currentQuote.name : ""))
    : "Stocks — no watchlist quotes yet"

  Timer {
    id: cycleTimer
    interval: root.cycleMs
    repeat: true
    running: root.cycleEnabled
    onTriggered: root.stepCycle(1)
  }

  // quotes + market movers — written by bin/omarchy-stocks-refresh
  Kit.Store {
    id: stateStore
    fileName: "stocks.json"
    watch: true
    parse: function (raw) { return Model.parseState(raw) }
  }

  // self-improvement state — per-ticker click counts (bin/omarchy-stocks-engage)
  // and cached AI commentary (bin/omarchy-stocks-commentary)
  Kit.Store {
    id: engagementStore
    fileName: "stocks-engagement.json"
    watch: true
    parse: function (raw) { return Model.parseEngagement(raw) }
  }

  Kit.Store {
    id: commentaryStore
    fileName: "stocks-commentary.json"
    watch: true
    parse: function (raw) { return Model.parseCommentary(raw) }
  }

  // Fire-and-forget: records a card click for Model.sortByEngagement and
  // bin/omarchy-stocks-commentary to learn from. Not gated on `running`
  // like refreshProc — clicks are rare enough that overlap isn't a concern,
  // and each invocation is a fresh Process so consecutive clicks don't fight
  // for the same one.
  function engageTicker(symbol) {
    var proc = engageProcComponent.createObject(root, { command: ["bash", root.engageScript, symbol] })
    proc.running = true
  }

  Component {
    id: engageProcComponent
    Process {
      running: false
      onExited: destroy()
    }
  }

  // watchlist — plugin-owned config (which tickers to track)
  Kit.Store {
    id: watchlistStore
    fileName: "stocks-watchlist.json"
    parse: function (raw) { return Model.parseWatchlist(raw) }
    // Kick the first price fetch once the watchlist has loaded.
    onLoadedChanged: if (loaded) root.runRefresh()
  }

  function saveWatchlist() {
    watchlistStore.save()
  }

  function addTicker(symbol) {
    guard.run("addTicker", function() {
      root.watchlistConfig = Model.addTicker(root.watchlistConfig, symbol)
      root.saveWatchlist()
      root.runRefresh()
    })
  }

  function removeTicker(symbol) {
    guard.run("removeTicker", function() {
      root.watchlistConfig = Model.removeTicker(root.watchlistConfig, symbol)
      root.saveWatchlist()
    })
  }

  function clearWatchlist() {
    guard.run("clearWatchlist", function() {
      root.watchlistConfig = Model.defaultWatchlist()
      root.saveWatchlist()
    })
  }

  // -------------------------------------------------- ticker autocomplete
  // Panel.qml calls searchTickers() on every keystroke in the Add field;
  // this debounces (searchDebounce) and shells out to bin/omarchy-stocks-search,
  // whose trimmed JSON stdout is parsed straight into searchResults. Kept
  // separate from the price-refresh Process so an in-flight search never
  // blocks (or is blocked by) a refresh.
  function searchTickers(query) {
    guard.run("searchTickers", function() {
      var q = (query || "").trim()
      root.searchQuery = q
      if (q.length < 1) {
        root.searchResults = []
        searchDebounce.stop()
        return
      }
      searchDebounce.restart()
    })
  }

  function clearSearchResults() {
    root.searchQuery = ""
    root.searchResults = []
    searchDebounce.stop()
  }

  Timer {
    id: searchDebounce
    interval: 220
    repeat: false
    onTriggered: {
      if (!root.searchQuery) return
      searchProc.command = ["bash", root.searchScript, root.searchQuery]
      searchProc.running = true
    }
  }

  Process {
    id: searchProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        guard.run("searchProc.onStreamFinished", function() {
          try {
            root.searchResults = Model.parseSearchResults(JSON.parse(text || "[]"), 8)
          } catch (e) {
            root.searchResults = []
          }
        })
      }
    }
  }

  // -------------------------------------------------------------- refresh
  // Set when runRefresh() is called while a refresh is already in flight
  // (e.g. adding a second ticker moments after adding the first) — without
  // this, that request would just be dropped until the next timer tick,
  // silently leaving the newly-added ticker unfetched for up to 2 minutes.
  property bool refreshPending: false

  Process {
    id: refreshProc
    running: false
    onRunningChanged: root.refreshing = running
    onExited: {
      stateStore.reload()
      if (root.refreshPending) {
        root.refreshPending = false
        root.runRefresh()
      }
    }
  }

  function runRefresh() {
    if (!watchlistLoaded) return
    if (refreshProc.running) {
      root.refreshPending = true
      return
    }
    refreshProc.command = ["bash", root.refreshScript].concat(root.watchlistConfig.tickers)
    refreshProc.running = true
  }

  // Poll cadence. Yahoo's keyless endpoints have no push/stream, so this is
  // plain polling — default every 120s, floored at 30s. Override per-widget
  // with "refreshSeconds" in this widget's shell.json layout entry (e.g. 300
  // for a lighter 5-minute poll).
  readonly property int refreshIntervalMs: Math.max(30, setting("refreshSeconds", 120)) * 1000

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalMs
    repeat: true
    running: true
    onTriggered: root.runRefresh()
  }

  readonly property var guard: Kit.BugGuard.create("alteringux.stocks", function(argv) { Quickshell.execDetached(argv) })

  // ---- Popup panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property real cyclePadding: Style.spaceReal(8.75)

  // Width follows the animated ticker label (not the raw text metrics) so the
  // bar slot eases open/closed as symbols swap rather than snapping.
  implicitWidth: Math.round(ticker.implicitWidth + cyclePadding * 2)
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "alteringux.stocks"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.runRefresh() }
    function addTicker(symbol: string): void { root.addTicker(symbol) }
    function removeTicker(symbol: string): void { root.removeTicker(symbol) }
    function status(): string {
      return guard.call("ipc.status", function() {
        return JSON.stringify({
          tickers: root.watchlistConfig.tickers,
          updatedAt: root.state.updatedAt,
          refreshing: root.refreshing,
          showing: root.currentQuote && root.currentQuote.symbol ? root.currentQuote.symbol : null
        })
      }, "{}")
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Fed to the button only to keep it "visually present" (sizing/opacity);
    // its own label is hidden and the animated TickerTape draws instead.
    text: root.displayText
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tickerTooltip

    onPressed: function(b) {
      root.togglePanel()
    }

    onWheelMoved: function(delta) {
      root.stepCycle(delta < 0 ? 1 : -1)
      if (root.cycleEnabled)
        cycleTimer.restart()
    }

    TickerTape {
      id: ticker
      anchors.centerIn: parent
      text: root.displayText
      color: root.tickerColor
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      fontSize: Style.font.body
    }
  }
}
