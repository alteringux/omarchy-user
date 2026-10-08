import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Sports bar widget: a background refresh timer shells out to
// bin/omarchy-sports-refresh (TheSportsDB free API — upcoming fixtures,
// recent results, standings, day-sweep live matches) and writes a state file
// under ~/.local/state/omarchy/ (same convention as alteringux.stocks). The
// bar icon shows the most interesting match (a favourite team's live match,
// else the next fixture); the popup panel holds the full dashboard.
BarWidget {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.sports"

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/alteringux.sports"
  readonly property string refreshScript: pluginDir + "/bin/omarchy-sports-refresh"

  // sports.json lives under ~/.local/state/omarchy/ (outside the plugin's
  // own source tree — the shell's plugin-file watcher would reload the
  // widget on every write) and is rewritten by bin/omarchy-sports-refresh.
  property alias state: stateStore.value
  property bool refreshing: false

  // ---- config (hand-edited; the CLI reads the same file) ----------------
  Kit.Store {
    id: configStore
    dir: home + "/.config/omarchy/"
    fileName: "sports-config.json"
    watch: true
    pollMs: 60000
    seedOnCreate: true
    parse: function (raw) {
      try {
        var doc = (raw && raw.length) ? JSON.parse(raw) : {}
        return root.normalizeConfig(doc)
      } catch (e) { return root.defaultConfig() }
    }
    serialize: function (value) { return JSON.stringify(value, null, 2) + "\n" }
  }

  function defaultConfig() {
    return {
      version: 1,
      activeSports: ["Soccer", "Rugby", "Basketball"],
      favouriteTeams: [],
      refreshSeconds: 300,
      liveRefreshSeconds: 60
    }
  }


  function normalizeConfig(doc) {
    var base = defaultConfig()
    if (!doc || typeof doc !== "object" || Array.isArray(doc)) return base
    for (var key in doc) if (Object.prototype.hasOwnProperty.call(doc, key)) base[key] = doc[key]

    if (!Array.isArray(base.activeSports))
      base.activeSports = defaultConfig().activeSports
    else
      base.activeSports = base.activeSports.filter(function (s) { return typeof s === "string" && s.trim() !== "" })
    if (!Array.isArray(base.favouriteTeams))
      base.favouriteTeams = []
    else
      base.favouriteTeams = base.favouriteTeams.filter(function (f) { return f && typeof f === "object" && !Array.isArray(f) })
    if (typeof base.refreshSeconds !== "number" || !isFinite(base.refreshSeconds) || base.refreshSeconds <= 0)
      base.refreshSeconds = 300
    if (typeof base.liveRefreshSeconds !== "number" || !isFinite(base.liveRefreshSeconds) || base.liveRefreshSeconds <= 0)
      base.liveRefreshSeconds = 60
    if (!base.leagues || typeof base.leagues !== "object" || Array.isArray(base.leagues))
      base.leagues = {}
    if (!Array.isArray(base.tableSports)) base.tableSports = []
    if (!base.articlesFeeds || typeof base.articlesFeeds !== "object" || Array.isArray(base.articlesFeeds))
      base.articlesFeeds = {}
    if (typeof base.players !== "boolean") base.players = true
    return base
  }
  property var config: configStore.value || defaultConfig()
  readonly property var favouriteNames: (config.favouriteTeams || []).map(function (f) { return f.name })

  // ---- derived, read by Panel.qml -----------------------------------
  readonly property var liveMatches: state.live || []
  readonly property var upcomingMatches: state.upcoming || []
  readonly property var resultMatches: state.results || []
  readonly property var playerMap: state.players || {}
  readonly property var standingsMap: state.standings || {}
  readonly property var teamMap: state.teams || {}
  readonly property int liveCount: liveMatches.length

  // Bar icon summary: favourite live match > any live match > next fixture.
  readonly property var summary: Model.barSummary(state, favouriteNames)
  readonly property bool liveNow: summary.mode === "live"

  function sportGlyph(sport) { return Model.sportGlyph(sport) }

  readonly property string barGlyph: summary.match
    ? Model.sportGlyph(summary.match.sport)
    : "󰧑"

  readonly property string displayText: root.barGlyph + " " + (
    liveNow ? summary.text
      : (summary.mode === "next" ? summary.text : "Sports"))

  readonly property string tickerTooltip: {
    var lines = []
    if (summary.match) {
      lines.push(Model.formatMatchLabel(summary.match))
      if (summary.mode === "live")
        lines.push(Model.formatMatchTime(summary.match.status, summary.match.elapsed) || "in play")
      else if (summary.match.dateEvent)
        lines.push(Model.formatMatchDate(summary.match.dateEvent) + " " + Model.formatMatchTimeOfDay(summary.match))
    }
    if (liveCount > 1)
      lines.push(liveCount + " matches live")
    return lines.length ? lines.join("\n") : "Sports — waiting for data"
  }

  // ---------------------------------------------------------------- state
  Kit.Store {
    id: stateStore
    fileName: "sports.json"
    watch: true
    parse: function (raw) { return Model.parseState(raw) }
    onLoadedChanged: {
      if (loaded && root.refreshPending) {
        root.refreshPending = false
        root.runRefresh()
      }
    }
  }

  // -------------------------------------------------------------- refresh
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

  property real lastRefreshAt: 0
  function runRefresh() {
    if (!stateStore.loaded) { root.refreshPending = true; return }
    if (refreshProc.running) { root.refreshPending = true; return }
    // Circuit breakers for the multi-screen refresh storm (one bar PER screen):
    //  1. this instance fetched very recently
    //  2. another instance already refreshed the shared sports.json
    var since = Date.now() - root.lastRefreshAt
    if (root.lastRefreshAt > 0 && since >= 0 && since < root.refreshIntervalMs * 0.75) { root.refreshPending = false; return }
    var age = Date.now() - (Date.parse(String((root.state && root.state.updatedAt) || "")) || 0)
    if (age >= 0 && age < root.refreshIntervalMs * 0.75) { root.refreshPending = false; return }
    root.lastRefreshAt = Date.now()
    refreshProc.command = ["bash", root.refreshScript]
    refreshProc.running = true
  }

  Component.onCompleted: root.runRefresh()

  // Poll cadence: slow while idle (default 5 min), fast when something is
  // live or a favourite match is coming up within the hour. Both overridable
  // in sports-config.json (refreshSeconds / liveRefreshSeconds).
  readonly property int refreshIntervalMs: Math.max(120, (config.refreshSeconds || 300)) * 1000
  readonly property int liveIntervalMs: Math.max(30, (config.liveRefreshSeconds || 60)) * 1000
  readonly property bool fastPoll: liveNow || (summary.match && summary.match.strTimestamp
    && (Date.parse(summary.match.strTimestamp) - Date.now()) < 3600000
    && (Date.parse(summary.match.strTimestamp) - Date.now()) > -7200000)

  Timer {
    id: refreshTimer
    interval: root.fastPoll ? root.liveIntervalMs : root.refreshIntervalMs
    repeat: true
    running: true
    onTriggered: root.runRefresh()
    // Re-evaluate the cadence binding when the poll mode flips.
    onIntervalChanged: restart()
  }

  readonly property var guard: Kit.BugGuard.create("alteringux.sports", function(argv) { Quickshell.execDetached(argv) })

  Kit.PulseTint {
    id: pulseTint
    pluginId: "alteringux.sports"
  }

  // ---- Popup panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    root.injectPanel()
    if (panelLoader.item) panelLoader.item.open()
    else Qt.callLater(function() {
      root.injectPanel()
      if (panelLoader.item) panelLoader.item.open()
    })
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    root.injectPanel()
    if (panelLoader.item) panelLoader.item.toggle()
    else Qt.callLater(function() {
      root.injectPanel()
      if (panelLoader.item) panelLoader.item.toggle()
    })
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property real cyclePadding: Style.spaceReal(8.75)

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
    target: "alteringux.sports"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.runRefresh() }
    function status(): string {
      return guard.call("ipc.status", function() {
        return JSON.stringify({
          updatedAt: root.state.updatedAt,
          refreshing: root.refreshing,
          live: root.liveCount,
          upcoming: root.upcomingMatches.length,
          results: root.resultMatches.length,
          showing: root.summary.mode
        })
      }, "{}")
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tickerTooltip

    onPressed: function(b) {
      root.togglePanel()
    }

    TickerTape {
      id: ticker
      anchors.centerIn: parent
      text: root.displayText
      color: root.liveNow ? _webPalette.barPositive : (root.bar ? _webPalette.barTextColorFor(root.bar.barForeground) : _webPalette.foreground)
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
