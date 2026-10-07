import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Stocks bar widget: a background refresh timer shells out to
// bin/omarchy-stocks-refresh (Yahoo Finance's free/keyless screener,
// queried per-region and merged) and writes global top-10 gainers/losers +
// trending symbols to a state file (same convention as
// alteringux.dashboard). The bar icon cycles through the current top
// movers; the popup panel shows the full gainers/losers card grid plus
// trending searches.
BarWidget {
  id: root
  moduleName: "alteringux.stocks"

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/alteringux.stocks"
  readonly property string refreshScript: pluginDir + "/bin/omarchy-stocks-refresh"

  // stocks.json lives under ~/.local/state/omarchy/ (outside the plugin's
  // own source tree — the shell's plugin-file watcher would reload the
  // widget on every write) and is rewritten by bin/omarchy-stocks-refresh.
  property alias state: stateStore.value
  property bool refreshing: false
  // The refresh script keeps the last valid quotes on provider failure. Do
  // not let that cache look like a current market snapshot.
  readonly property bool providerStale: state && state.stale === true
  readonly property string providerError: state && state.providerError ? String(state.providerError) : ""

  // ---- derived, read by Panel.qml -----------------------------------

  readonly property var gainers: (state.gainers || []).map(Model.parseScreenerQuote)
  readonly property var losers: (state.losers || []).map(Model.parseScreenerQuote)
  readonly property var trendingSymbols: Model.parseTrendingSymbols(state.trending, 12)

  readonly property var biggestMover: Model.biggestMoverAbs(gainers.concat(losers))

  // ---- bar-icon cycling ----------------------------------------------------
  // The bar icon rotates through the global top gainers/losers, one every
  // `cycleSeconds` (read from this widget's shell.json layout entry, default
  // 5), gainers first then losers. Put "cycle": false in the layout entry to
  // pin it to the single biggest mover instead. Scrolling the widget steps
  // the rotation by hand and nudges the timer.
  readonly property var cycleQuotes: gainers.concat(losers).filter(function (q) {
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

  readonly property string tickerTooltip: {
    var text = currentQuote && currentQuote.symbol
      ? (currentQuote.symbol
         + (currentQuote.price !== null && currentQuote.price !== undefined ? "  " + Model.formatPrice(currentQuote.price, currentQuote.currency) : "")
         + "  " + Model.formatChangePct(currentQuote.changePct)
         + (currentQuote.name ? "\n" + currentQuote.name : ""))
      : "Stocks — no mover data yet"
    if (root.providerStale)
      text += "\nProvider unavailable — showing stale data"
    else if (root.providerError)
      text += "\n" + root.providerError
    return text
  }

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

  // -------------------------------------------------------------- refresh
  // Set when runRefresh() is called while a refresh is already in flight —
  // without this, that request would just be dropped until the next timer
  // tick, silently delaying a manual refresh click by up to a full cycle.
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

  // Wall-clock of the last fetch this instance started. Instance-local, so it
  // breaks a single-widget refresh loop even when the shared file timestamp
  // is unreadable.
  property real lastRefreshAt: 0
  function runRefresh() {
    if (refreshProc.running) { root.refreshPending = true; return }
    // Circuit breakers for the multi-screen refresh storm (one bottom bar PER
    // screen) and for any caller that over-triggers this:
    //  1. this instance fetched very recently
    //  2. another instance already refreshed the shared stocks.json
    var since = Date.now() - root.lastRefreshAt
    if (root.lastRefreshAt > 0 && since >= 0 && since < root.refreshIntervalMs * 0.75) { root.refreshPending = false; return }
    var age = Date.now() - (Date.parse(String((root.state && root.state.updatedAt) || "")) || 0)
    if (age >= 0 && age < root.refreshIntervalMs * 0.75) { root.refreshPending = false; return }
    root.lastRefreshAt = Date.now()
    refreshProc.command = ["bash", root.refreshScript]
    refreshProc.running = true
  }

  Component.onCompleted: root.runRefresh()

  // Poll cadence. Yahoo's keyless endpoints have no push/stream, so this is
  // plain polling — default every 30s (the floor). Global movers change more
  // than a personal watchlist did, so this stays livelier than the old
  // 120s default; override per-widget with "refreshSeconds" in this widget's
  // shell.json layout entry (e.g. 60 for a lighter poll) if Yahoo's screener
  // starts rate-limiting at this cadence.
  readonly property int refreshIntervalMs: Math.max(120, setting("refreshSeconds", 300)) * 1000

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalMs
    repeat: true
    running: true
    onTriggered: root.runRefresh()
  }

  readonly property var guard: Kit.BugGuard.create("alteringux.stocks", function(argv) { Quickshell.execDetached(argv) })

  Kit.PulseTint {
    id: pulseTint
    pluginId: "alteringux.stocks"
  }

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
    function status(): string {
      return guard.call("ipc.status", function() {
        return JSON.stringify({
          updatedAt: root.state.updatedAt,
          refreshing: root.refreshing,
          stale: root.providerStale,
          providerError: root.providerError || null,
          gainers: root.gainers.length,
          losers: root.losers.length,
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
    dimmed: root.providerStale

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

    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 2
      active: pulseTint.active
      level: pulseTint.level
    }
  }
}
