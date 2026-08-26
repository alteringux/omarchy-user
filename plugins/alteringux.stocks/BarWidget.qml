import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

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
  // Deliberately NOT inside the plugin's own source directory — that tree is
  // watched by the shell's plugin-file watcher, and this state file is
  // rewritten every refresh. Writing it there would trigger a "local plugin
  // changed" reload every refresh, tearing down an open panel. Same
  // convention as alteringux.dashboard / alteringux.pomodoro.
  readonly property string stateDir: home + "/.local/state/omarchy/"
  readonly property string statePath: stateDir + "stocks.json"
  readonly property string watchlistPath: stateDir + "stocks-watchlist.json"

  property var state: Model.defaultState()
  property var watchlistConfig: Model.defaultWatchlist()
  property bool watchlistLoaded: false
  property bool refreshing: false

  // ---- derived, read by Panel.qml -----------------------------------
  readonly property var watchlistQuotes: watchlistConfig.tickers.map(function (t) {
    var raw = root.state.watchlist ? root.state.watchlist[t] : null
    var q = Model.parseChartQuote(raw)
    q.symbol = q.symbol || t // fall back to the configured ticker if the fetch failed
    return q
  })
  readonly property var gainers: (state.gainers || []).map(Model.parseScreenerQuote)
  readonly property var losers: (state.losers || []).map(Model.parseScreenerQuote)
  readonly property var trendingSymbols: Model.parseTrendingSymbols(state.trending, 12)

  readonly property var biggestMover: Model.biggestMoverAbs(watchlistQuotes)
  readonly property string displayText: biggestMover
    ? ("📈 " + biggestMover.symbol + " " + Model.formatChangePct(biggestMover.changePct))
    : "📈 Stocks"

  // ------------------------------------------------------ state file (quotes)
  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.state = JSON.parse(text() || "{}")
    onLoadFailed: root.state = Model.defaultState()
    onFileChanged: reload()
  }

  // ------------------------------------------------------ watchlist config
  FileView {
    id: watchlistFile
    path: root.watchlistPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadWatchlist(text())
    onLoadFailed: root.loadWatchlist("")
  }

  function loadWatchlist(raw) {
    var parsed = Model.defaultWatchlist()
    try {
      if (raw && raw.length > 0) {
        var stored = JSON.parse(raw)
        if (Array.isArray(stored.tickers)) parsed.tickers = stored.tickers
      }
    } catch (e) {
      console.warn("stocks: watchlist parse failed:", e)
    }
    root.watchlistConfig = parsed
    root.watchlistLoaded = true
    root.runRefresh()
  }

  function saveWatchlist() {
    if (!watchlistLoaded) return
    watchlistFile.setText(JSON.stringify(root.watchlistConfig, null, 2) + "\n")
  }

  function addTicker(symbol) {
    root.watchlistConfig = Model.addTicker(root.watchlistConfig, symbol)
    root.saveWatchlist()
    root.runRefresh()
  }

  function removeTicker(symbol) {
    root.watchlistConfig = Model.removeTicker(root.watchlistConfig, symbol)
    root.saveWatchlist()
  }

  function clearWatchlist() {
    root.watchlistConfig = Model.defaultWatchlist()
    root.saveWatchlist()
  }

  // -------------------------------------------------------------- refresh
  Process {
    id: ensureDirsProc
    command: ["mkdir", "-p", root.stateDir]
    running: false
  }

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
      stateFile.reload()
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

  Timer {
    id: refreshTimer
    interval: 2 * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.runRefresh()
  }

  Component.onCompleted: {
    ensureDirsProc.running = true
    Qt.callLater(function() {
      stateFile.reload()
      watchlistFile.reload()
    })
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

  implicitWidth: button.implicitWidth
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
      return JSON.stringify({ tickers: root.watchlistConfig.tickers, updatedAt: root.state.updatedAt, refreshing: root.refreshing })
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      root.togglePanel()
    }
  }
}
