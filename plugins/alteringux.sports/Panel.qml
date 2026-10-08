import QtQuick
import QtQuick.Layouts
import Quickshell
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// Sports dashboard popup: sport picker pills, then one of six bodies —
// Live, Upcoming, Results, Players, Standings, Predict — plus an Ask AI row
// and the local-shortcuts hint row (ADR 0001). Data comes from the watched
// state file; predictions and AI answers shell out through bin/.
Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.sports"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var guard: Kit.BugGuard.create("alteringux.sports", function(argv) { Quickshell.execDetached(argv) })

  // ---- data from the host widget ------------------------------------
  readonly property var state: hostWidget ? hostWidget.state : Model.defaultState()
  readonly property var favouriteNames: hostWidget ? hostWidget.favouriteNames : []
  readonly property bool refreshing: hostWidget ? hostWidget.refreshing : false

  readonly property var liveMatches: Model.sortUpcoming(state.live || [])
  readonly property var upcomingMatches: Model.sortUpcoming(state.upcoming || [])
  readonly property var resultMatches: (state.results || []).slice(0, 30)
  readonly property var articles: state.articles || []
  readonly property var playerMap: state.players || {}
  readonly property var teamMap: state.teams || {}
  readonly property var standingsMap: state.standings || {}

  function displayDataTime(value) {
    var timestamp = Date.parse(value || "")
    return isFinite(timestamp) ? Qt.formatDateTime(new Date(timestamp), "hh:mm") : "time unavailable"
  }

  property var selectedMatch: null
  property var matchDetails: null
  property bool loadingDetails: false
  property string detailsError: ""
  property string detailsStatus: ""
  property string detailsOutput: ""
  property string detailsStderr: ""
  readonly property var configuredSports: hostWidget ? ((hostWidget.config && hostWidget.config.activeSports) || []) : []

  // ---- sport filter ---------------------------------------------------
  // Pill row filters every tab by sport; "All" shows everything. The last
  // selection persists in the widget's config store.
  readonly property var sportOptions: {
    var opts = ["All"]
    var seen = {}
    for (var c = 0; c < configuredSports.length; c++) {
      var configured = configuredSports[c]
      if (configured && !seen[configured]) { seen[configured] = true; opts.push(configured) }
    }
    var pools = [liveMatches, upcomingMatches, resultMatches, articles]
    for (var p = 0; p < pools.length; p++) {
      for (var i = 0; i < pools[p].length; i++) {
        var s = pools[p][i].sport
        if (s && !seen[s]) { seen[s] = true; opts.push(s) }
      }
    }
    for (var k in standingsMap) if (!seen[k]) { seen[k] = true; opts.push(k) }
    return opts
  }

  property string selectedSport: "All"

  function matchesSport(m) {
    return selectedSport === "All" || !m.sport || m.sport === selectedSport
  }

  readonly property var filteredLive: liveMatches.filter(matchesSport)
  readonly property var filteredUpcoming: upcomingMatches.filter(matchesSport)
  readonly property var filteredResults: resultMatches.filter(matchesSport)
  readonly property var filteredArticles: articles.filter(matchesSport)
  readonly property var filteredStandings: selectedSport !== "All" ? (standingsMap[selectedSport] || []) : []

  // ---- tab strip --------------------------------------------------------
  readonly property var tabs: ["Live", "Upcoming", "Results", "Players", "Table", "Articles", "Predict"].concat(root.selectedMatch ? ["Details"] : [])
  property string activeTab: "Live"

  // ---- prediction -------------------------------------------------------
  property var prediction: null
  property bool predicting: false
  property string predictHome: ""
  property string predictAway: ""
  property string predictionError: ""
  property string predictionStatus: ""
  property string predictionOutput: ""
  property string predictionStderr: ""

  // ---- AI row -----------------------------------------------------------
  property string aiAnswer: ""
  property string aiError: ""
  property string aiStatus: ""
  property string aiOutput: ""
  property string aiStderr: ""
  property bool aiBusy: false

  function processError(label, code, stderr) {
    var detail = String(stderr || "").trim().split(/\r?\n/)[0].slice(0, 180)
    return label + " failed: " + (detail || ("process exited with code " + code))
  }

  function announceAsyncStatus(target, message) {
    if (!root.opened || !message) return
    Qt.callLater(function() {
      if (root.opened && target && target.visible) target.Accessible.announce(message)
    })
  }

  Process {
    id: predictProc
    running: false
    stdout: StdioCollector { onStreamFinished: root.predictionOutput = this.text }
    stderr: StdioCollector { onStreamFinished: root.predictionStderr = this.text }
    onExited: function (code) {
      root.predicting = false
      if (code !== 0) {
        root.prediction = null
        root.predictionError = root.processError("Prediction", code, root.predictionStderr)
      } else {
        root.prediction = Model.parsePrediction(root.predictionOutput)
        root.predictionError = root.prediction
          ? ""
          : (root.predictionOutput.trim() ? "Could not read prediction output." : "No prediction was returned.")
      }
      root.predictionStatus = root.predictionError || (root.prediction ? "Prediction ready." : "No prediction was returned.")
      root.announceAsyncStatus(predictionFeedbackText, root.predictionStatus)
    }
  }

  function runPrediction(homeTeam, awayTeam) {
    if (!homeTeam || !awayTeam || !hostWidget) return
    root.predictHome = homeTeam
    root.predictAway = awayTeam
    root.predicting = true
    root.prediction = null
    root.predictionError = ""
    root.predictionStatus = "Generating prediction…"
    root.predictionOutput = ""
    root.predictionStderr = ""
    root.announceAsyncStatus(predictionFeedbackText, root.predictionStatus)
    predictProc.command = ["bash", hostWidget.pluginDir + "/bin/omarchy-sports-predict",
                           "--sport", root.selectedSport === "All" ? (firstAvailableSport() || "") : root.selectedSport,
                           "--home", homeTeam, "--away", awayTeam,
                           "--state", Quickshell.env("HOME") + "/.local/state/omarchy/sports.json",
                           "--persist"]
    predictProc.running = true
  }

  function firstAvailableSport() {
    if (upcomingMatches.length) return upcomingMatches[0].sport || ""
    if (resultMatches.length) return resultMatches[0].sport || ""
    return ""
  }

  Process {
    id: detailsProc
    running: false
    stdout: StdioCollector { onStreamFinished: root.detailsOutput = this.text }
    stderr: StdioCollector { onStreamFinished: root.detailsStderr = this.text }
    onExited: function (code) {
      root.loadingDetails = false
      if (code !== 0) {
        root.matchDetails = null
        root.detailsError = root.processError("Match details", code, root.detailsStderr)
        root.detailsStatus = root.detailsError
        root.announceAsyncStatus(detailsFeedbackText, root.detailsStatus)
        return
      }
      try {
        var payload = JSON.parse(root.detailsOutput)
        root.matchDetails = payload
        root.detailsError = payload.error || (Object.keys(payload).length ? "" : "No match details were returned.")
      } catch (e) {
        root.matchDetails = null
        root.detailsError = root.detailsOutput.trim()
          ? "Could not read match details"
          : "No match details were returned."
      }
      root.detailsStatus = root.detailsError || "Match details loaded."
      root.announceAsyncStatus(detailsFeedbackText, root.detailsStatus)
    }
  }

  function openMatchDetails(match) {
    if (!match || !match.id || !hostWidget) return
    root.selectedMatch = match
    root.matchDetails = null
    root.detailsError = ""
    root.detailsStatus = "Loading match details…"
    root.detailsOutput = ""
    root.detailsStderr = ""
    root.loadingDetails = true
    root.activeTab = "Details"
    root.announceAsyncStatus(detailsFeedbackText, root.detailsStatus)
    detailsProc.command = ["bash", hostWidget.pluginDir + "/bin/omarchy-sports-event",
                           "--id", String(match.id)]
    detailsProc.running = true
  }

  function closeMatchDetails() {
    root.selectedMatch = null
    root.matchDetails = null
    root.detailsError = ""
    root.detailsStatus = ""
    if (root.activeTab === "Details") root.activeTab = "Results"
  }

  Process {
    id: aiProc
    running: false
    stdout: StdioCollector { onStreamFinished: root.aiOutput = this.text }
    stderr: StdioCollector { onStreamFinished: root.aiStderr = this.text }
    onExited: function (code) {
      root.aiBusy = false
      if (code !== 0) {
        root.aiAnswer = ""
        root.aiError = root.processError("Analyst request", code, root.aiStderr)
      } else {
        root.aiError = ""
        root.aiAnswer = root.aiOutput.trim() || "No answer was returned."
      }
      root.aiStatus = root.aiError || (root.aiAnswer === "No answer was returned."
        ? root.aiAnswer : "Analyst response received.")
      root.announceAsyncStatus(aiFeedbackText, root.aiStatus)
    }
  }

  function askAi(question) {
    if (!question || !hostWidget) return
    root.aiBusy = true
    root.aiAnswer = ""
    root.aiError = ""
    root.aiStatus = "Asking the analyst…"
    root.aiOutput = ""
    root.aiStderr = ""
    root.announceAsyncStatus(aiFeedbackText, root.aiStatus)
    var argv = ["bash", hostWidget.pluginDir + "/bin/omarchy-sports-ai",
                "--state", Quickshell.env("HOME") + "/.local/state/omarchy/sports.json"]
    if (root.selectedSport !== "All") argv.push("--sport", root.selectedSport)
    argv.push(question)
    aiProc.command = argv
    aiProc.running = true
  }

  function openArticle(url) {
    var clean = String(url || "").trim()
    if (/^https?:\/\//i.test(clean))
      Quickshell.execDetached(["xdg-open", clean])
  }

  function clearPlayerSearch() {
    root.playerFilter = ""
    searchInput.text = ""
  }

  // ---- searchable player list ------------------------------------------
  property string playerFilter: ""

  readonly property var filteredPlayerRows: {
    var rows = []
    for (var teamName in playerMap) {
      var roster = playerMap[teamName] || []
      for (var i = 0; i < roster.length; i++) {
        var p = roster[i]
        if (selectedSport !== "All" && teamMap[teamName] && teamMap[teamName].sport
            && teamMap[teamName].sport !== selectedSport)
          continue
        rows.push(p)
      }
    }
    var f = root.playerFilter.toLowerCase()
    if (f)
      rows = rows.filter(function (p) {
        return (p.name || "").toLowerCase().indexOf(f) !== -1
              || (p.position || "").toLowerCase().indexOf(f) !== -1
              || (p.team || "").toLowerCase().indexOf(f) !== -1
      })
    rows.sort(function (a, b) { return (a.name || "").localeCompare(b.name || "") })
    return rows
  }

  function badgeFor(teamName) {
    var team = teamMap[String(teamName || "")]
    return team && /^https?:\/\//i.test(String(team.badge || "")) ? team.badge : ""
  }
  // ---- panel chrome ------------------------------------------------------
  readonly property color fg: root.bar ? _webPalette.barTextColorFor(root.bar.barForeground) : _webPalette.foreground

  function openRosterTeam(teamName) {
    root.playerFilter = teamName || ""
    root.activeTab = "Players"
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(680))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(620)))

    Kit.PanelKeys {
      anchors.fill: parent

      onCloseRequested: root.close()
      onActivateRequested: if (hostWidget) hostWidget.runRefresh()
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Refresh sports results", context: "Sports · shortcut focus" }
      ]


      }

    Kit.PanelScroll {
      anchors.fill: parent
      contentHeight: content.implicitHeight

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.panelGap

        Kit.PanelHead {
          glyph: "󰜺"
          title: "Sports"
          meta: {
            var health = root.state.refreshHealth || {}
            if (health.usedCachedMatches || health.usedCachedArticles) {
              var cached = []
              if (health.usedCachedMatches)
                cached.push("matches " + root.displayDataTime(root.state.matchDataUpdatedAt || root.state.updatedAt))
              if (health.usedCachedArticles)
                cached.push("articles " + root.displayDataTime(root.state.articleDataUpdatedAt || root.state.updatedAt))
              return "showing cached " + cached.join(" · ")
            }
            if (root.refreshing) return "refreshing…"
            return (root.liveMatches.length ? root.liveMatches.length + " LIVE NOW" : "no live matches")
              + (root.state.updatedAt ? " · updated " + root.displayDataTime(root.state.updatedAt) : "")
          }
          foreground: root.fg
          trailingControl: Component {
            Kit.ActionButton {
              text: "Refresh"
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: "Refresh sports data"
              foreground: root.fg
              bordered: true
              onClicked: if (hostWidget) hostWidget.runRefresh()
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.sportOptions
            delegate: Kit.ActionButton {
              required property string modelData
              text: Model.sportGlyph(modelData) + " " + (modelData === "All" ? "All" : Model.sportLabel(modelData))
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: modelData === "All" ? "All sports" : Model.sportLabel(modelData)
              bordered: true
              foreground: root.selectedSport === modelData
                ? _webPalette.contrastColorFor(Model.sportColor(modelData), _webPalette.barBackground)
                : root.fg
              onClicked: root.selectedSport = modelData
            }
          }
        }

        // ---- tab strip -----------------------------------------------------
        Row {
          spacing: Style.space(6)

          Repeater {
            model: root.tabs
            delegate: Kit.ActionButton {
              required property string modelData
              text: modelData
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: modelData + " tab"
              bordered: false
              foreground: root.activeTab === modelData ? _webPalette.accent : root.fg
              onClicked: root.activeTab = modelData
            }
          }
        }

        PanelSectionHeader { text: root.activeTab.toUpperCase() + (root.selectedSport !== "All" ? " — " + Model.sportLabel(root.selectedSport).toUpperCase() : ""); foreground: root.fg }

        // ================= LIVE =================
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.activeTab === "Live"

          GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(10)
            rowSpacing: Style.space(10)

            Repeater {
              model: root.filteredLive
              delegate: MatchCard {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                match: modelData
                prediction: Model.predictionForMatch(root.state, modelData)
                homeBadge: root.badgeFor(modelData.homeTeam)
                awayBadge: root.badgeFor(modelData.awayTeam)
                isLive: true
                favouriteNames: root.favouriteNames
                barForeground: root.fg
                accentColor: _webPalette.contrastColorFor(Model.sportColor(modelData.sport), Color.popups.background)
                onOpenRequested: root.openArticle(url)
                onDetailsRequested: root.openMatchDetails(match)
              }
            }
          }

          Kit.EmptyState {
            visible: root.filteredLive.length === 0
            text: root.refreshing ? "Loading…" : "No live matches"
            hint: root.refreshing ? "" : "Matches appear here once play starts."
            foreground: root.fg
          }
        }

        // ================= UPCOMING =================
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.activeTab === "Upcoming"

          GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(10)
            rowSpacing: Style.space(10)

            Repeater {
              model: root.filteredUpcoming.slice(0, 20)
              delegate: MatchCard {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                match: modelData
                prediction: Model.predictionForMatch(root.state, modelData)
                homeBadge: root.badgeFor(modelData.homeTeam)
                awayBadge: root.badgeFor(modelData.awayTeam)
                favouriteNames: root.favouriteNames
                onOpenRequested: root.openArticle(url)
                onDetailsRequested: root.openMatchDetails(match)
                barForeground: root.fg
                accentColor: _webPalette.contrastColorFor(Model.sportColor(modelData.sport), Color.popups.background)
              }
            }
          }

          Kit.EmptyState {
            visible: root.filteredUpcoming.length === 0
            text: root.refreshing ? "Loading…" : "No upcoming fixtures"
            hint: root.refreshing ? "" : "Try Refresh, or add leagues in sports-config.json."
            foreground: root.fg
          }
        }

        // ================= RESULTS =================
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.activeTab === "Results"

          GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(10)
            rowSpacing: Style.space(10)

            Repeater {
              model: root.filteredResults.slice(0, 20)
              delegate: MatchCard {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                match: modelData
                prediction: Model.predictionForMatch(root.state, modelData)
                homeBadge: root.badgeFor(modelData.homeTeam)
                awayBadge: root.badgeFor(modelData.awayTeam)
                isResult: true
                favouriteNames: root.favouriteNames
                barForeground: root.fg
                accentColor: _webPalette.contrastColorFor(Model.sportColor(modelData.sport), Color.popups.background)
                onOpenRequested: root.openArticle(url)
                onDetailsRequested: root.openMatchDetails(match)
              }
            }
          }

          Kit.EmptyState {
            visible: root.filteredResults.length === 0
            text: root.refreshing ? "Loading…" : "No recent results"
            hint: root.refreshing ? "" : "Final scores land here after matches finish."
            foreground: root.fg
          }
        }

        // ================= DETAILS =================
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.activeTab === "Details"

          MatchDetailCard {
            width: parent.width
            match: root.selectedMatch || {}
            details: root.matchDetails
            loading: root.loadingDetails
            barForeground: root.fg
            accentColor: _webPalette.contrastColorFor(Model.sportColor((root.selectedMatch || {}).sport), Color.popups.background)
            onOpenRequested: root.openArticle(url)
            onCloseRequested: root.closeMatchDetails()
          }

          Text {
            id: detailsFeedbackText
            visible: !!root.detailsStatus
            text: root.detailsStatus
            Accessible.role: Accessible.StaticText
            width: parent.width
            color: root.detailsError ? _webPalette.negative : _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ================= ARTICLES =================
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.activeTab === "Articles"

          Text {
            text: "󰎕  Latest stories from your configured sport feeds"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.filteredArticles.slice(0, 20)
            delegate: ArticleCard {
              required property var modelData
              width: parent.width
              article: modelData
              barForeground: root.fg
              onOpenRequested: root.openArticle(url)
            }
          }

          Kit.EmptyState {
            visible: root.filteredArticles.length === 0
            text: root.refreshing ? "Loading…" : "No articles cached"
            hint: root.refreshing ? "" : "Add RSS or Atom URLs under articlesFeeds in sports-config.json, then Refresh."
            foreground: root.fg
          }
        }

        // ================= PLAYERS =================
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.activeTab === "Players"

          Rectangle {
            width: parent.width
            height: searchRow.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: Util.alpha(root.fg, 0.06)
            border.width: 1
            border.color: Util.alpha(root.fg, 0.18)

            Row {
              id: searchRow
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.margins: Style.space(6)
              spacing: Style.space(6)

              Text {
                text: "󰍉"
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }
              TextInput {
                id: searchInput
                width: parent.width - searchClear.width - hintText.width - parent.spacing * 3
                anchors.verticalCenter: parent.verticalCenter
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                clip: true
                text: root.playerFilter
                onTextEdited: root.playerFilter = text
                Text {
                  visible: searchInput.text === ""
                  text: "search players, positions, teams…"
                  color: _webPalette.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              Text {
                id: hintText
                text: root.filteredPlayerRows.length + " players"
                color: _webPalette.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: searchClear
                visible: root.playerFilter !== ""
                text: "✕"
                Accessible.role: Accessible.Button
                Accessible.name: "Clear player search"
                Accessible.onPressAction: root.clearPlayerSearch()
                color: activeFocus ? _webPalette.accent : root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.underline: activeFocus
                activeFocusOnTab: true
                anchors.verticalCenter: parent.verticalCenter

                Keys.onReturnPressed: root.clearPlayerSearch()
                Keys.onSpacePressed: root.clearPlayerSearch()

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    parent.forceActiveFocus()
                    root.clearPlayerSearch()
                  }
                }
              }
            }
          }

          Text {
            visible: Object.keys(root.playerMap).length === 0
            text: "No rosters yet. Add favourite teams (with idTeam) to sports-config.json, then Refresh — their squads load into this tab."
            width: parent.width
            wrapMode: Text.WordWrap
            color: _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.filteredPlayerRows.slice(0, 60)
            delegate: PlayerCard {
              required property var modelData
              width: parent.width
              player: modelData
              barForeground: root.fg
              accentColor: root.selectedSport === "All" ? _webPalette.accent
                : _webPalette.contrastColorFor(Model.sportColor(root.selectedSport), Color.popups.background)
            }
          }
        }

        // ================= TABLE =================
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.activeTab === "Table"

          Text {
            visible: root.filteredStandings.length === 0
            text: root.selectedSport === "All"
              ? "Pick a sport above to see its standings (tables load for sports listed in tableSports)."
              : "No standings cached for " + root.selectedSport + " yet — tableSports in sports-config.json controls which sports fetch tables."
            width: parent.width
            wrapMode: Text.WordWrap
            color: _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.filteredStandings
            delegate: Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: modelData.rank || ""
                width: Style.space(18)
                horizontalAlignment: Text.AlignRight
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              MarqueeText {
                text: modelData.team || ""
                width: parent.width - parent.spacing * 5 - Style.space(18) - ptsText.width - formText.width - playedText.width
                requestedElide: Text.ElideRight
                color: root.fg
                textFont.family: Style.font.family
                textFont.pixelSize: Style.font.bodySmall
                textFont.bold: parseInt(modelData.rank, 10) <= 4
              }
              Text {
                id: playedText
                text: (modelData.played || "") + "P"
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                id: formText
                text: modelData.form || ""
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                id: ptsText
                text: (modelData.points || "") + " pts"
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
          }
        }

        // ================= PREDICT =================
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.activeTab === "Predict"

          Text {
            text: "Compare two sides' form, head-to-head record, home advantage and league position. The predictor reads the matches already cached on this machine."
            width: parent.width
            wrapMode: Text.WordWrap
            color: _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            ComboBox {
              id: homeBox
              width: (parent.width - parent.spacing) / 2
              model: root.teamChoices()
              displayText: root.predictHome || "home team…"
              onActivated: root.predictHome = currentText
            }
            ComboBox {
              id: awayBox
              width: (parent.width - parent.spacing) / 2
              model: root.teamChoices()
              displayText: root.predictAway || "away team…"
              onActivated: root.predictAway = currentText
            }
          }

          Kit.ActionButton {
            text: root.predicting ? "Predicting…" : "Run prediction"
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: root.predicting ? "Prediction in progress" : "Run match prediction"
            enabled: !root.predicting && root.predictHome !== "" && root.predictAway !== ""
            foreground: root.fg
            bordered: true
            onClicked: root.runPrediction(root.predictHome, root.predictAway)
          }

          Text {
            id: predictionFeedbackText
            visible: !!root.predictionStatus
            text: root.predictionStatus
            Accessible.role: Accessible.StaticText
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.predictionError ? _webPalette.negative : _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          PredictionCard {
            visible: root.prediction !== null
            width: parent.width
            prediction: root.prediction
            barForeground: root.fg
            accentColor: root.selectedSport === "All" ? _webPalette.accent
              : _webPalette.contrastColorFor(Model.sportColor(root.selectedSport), Color.popups.background)
          }
        }

        PanelSeparator {}

        // ================= ASK AI =================
        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "ASK THE ANALYST"
            color: _webPalette.contrastColorFor(Qt.darker(root.fg, 1.4), _webPalette.barBackground)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Rectangle {
              width: parent.width - aiButton.width - parent.spacing
              height: aiInput.implicitHeight + Style.space(12)
              radius: Style.cornerRadius
              color: Util.alpha(root.fg, 0.06)
              border.width: 1
              border.color: Util.alpha(root.fg, 0.18)

              TextInput {
                id: aiInput
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Style.space(6)
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                clip: true
                Keys.onReturnPressed: root.askAi(text)
                Text {
                  visible: aiInput.text === ""
                  text: "e.g. how did the favourites do today?"
                  color: root.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            Kit.ActionButton {
              id: aiButton
              text: root.aiBusy ? "…" : "Ask"
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: root.aiBusy ? "Analyst response in progress" : "Ask the sports analyst"
              enabled: !root.aiBusy
              foreground: root.fg
              bordered: true
              onClicked: root.askAi(aiInput.text)
            }
          }

          Text {
            id: aiFeedbackText
            visible: root.aiStatus !== "" || root.aiAnswer !== "" || root.aiError !== ""
            text: root.aiError || root.aiAnswer || root.aiStatus
            Accessible.role: Accessible.StaticText
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.aiError ? _webPalette.negative : root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator {}

        Text {
          text: "Enter: refresh now  ·  Esc: close"
          color: _webPalette.contrastColorFor(Qt.darker(root.fg, 1.4), _webPalette.barBackground)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  function teamChoices() {
    var names = []
    for (var name in teamMap) names.push(name)
    if (names.length === 0) {
      // fall back to team names seen in cached matches
      var seen = {}
      var pools = [upcomingMatches, resultMatches]
      for (var p = 0; p < pools.length; p++)
        for (var i = 0; i < pools[p].length; i++) {
          var m = pools[p][i]
          if (m.homeTeam && !seen[m.homeTeam]) { seen[m.homeTeam] = true; names.push(m.homeTeam) }
          if (m.awayTeam && !seen[m.awayTeam]) { seen[m.awayTeam] = true; names.push(m.awayTeam) }
        }
    }
    return names.sort()
  }
}
