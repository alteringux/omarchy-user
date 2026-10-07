import QtQuick
import QtQuick.Layouts
import Quickshell
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Sports dashboard popup: sport picker pills, then one of six bodies —
// Live, Upcoming, Results, Players, Standings, Predict — plus an Ask AI row
// and the local-shortcuts hint row (ADR 0001). Data comes from the watched
// state file; predictions and AI answers shell out through bin/.
Panel {
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

  property var selectedMatch: null
  property var matchDetails: null
  property bool loadingDetails: false
  property string detailsError: ""
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

  // ---- AI row -----------------------------------------------------------
  property string aiAnswer: ""
  property bool aiBusy: false

  Process {
    id: predictProc
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.predicting = false
        root.prediction = Model.parsePrediction(this.text)
      }
    }
    stderr: StdioCollector { }
  }

  function runPrediction(homeTeam, awayTeam) {
    if (!homeTeam || !awayTeam || !hostWidget) return
    root.predictHome = homeTeam
    root.predictAway = awayTeam
    root.predicting = true
    root.prediction = null
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
    stdout: StdioCollector {
      onStreamFinished: {
        root.loadingDetails = false
        try {
          var payload = JSON.parse(this.text)
          root.matchDetails = payload
          root.detailsError = payload.error || ""
        } catch (e) {
          root.matchDetails = null
          root.detailsError = "Could not read match details"
        }
      }
    }
    stderr: StdioCollector { }
  }

  function openMatchDetails(match) {
    if (!match || !match.id || !hostWidget) return
    root.selectedMatch = match
    root.matchDetails = null
    root.detailsError = ""
    root.loadingDetails = true
    root.activeTab = "Details"
    detailsProc.command = ["bash", hostWidget.pluginDir + "/bin/omarchy-sports-event",
                           "--id", String(match.id)]
    detailsProc.running = true
  }

  function closeMatchDetails() {
    root.selectedMatch = null
    root.matchDetails = null
    root.detailsError = ""
    if (root.activeTab === "Details") root.activeTab = "Results"
  }

  Process {
    id: aiProc
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.aiBusy = false
        root.aiAnswer = this.text.trim()
      }
    }
    stderr: StdioCollector { }
  }

  function askAi(question) {
    if (!question || !hostWidget) return
    root.aiBusy = true
    root.aiAnswer = ""
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
  readonly property color fg: root.bar ? root.bar.barForeground : Color.foreground

  function openRosterTeam(teamName) {
    root.playerFilter = teamName || ""
    root.activeTab = "Players"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(680))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(620)))

    PanelKeyCatcher {
      anchors.fill: parent

      onCloseRequested: root.close()
      onActivateRequested: if (hostWidget) hostWidget.runRefresh()


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
          meta: root.refreshing ? "refreshing…" : (root.liveMatches.length ? root.liveMatches.length + " LIVE NOW" : "no live matches")
          foreground: root.fg
          trailingControl: Component {
            Button {
              text: "Refresh"
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
            delegate: Button {
              required property string modelData
              text: modelData === "All" ? "🏆 All" : (Model.sportEmoji(modelData) + " " + Model.sportLabel(modelData))
              bordered: true
              foreground: root.selectedSport === modelData ? Model.sportColor(modelData) : root.fg
              onClicked: root.selectedSport = modelData
            }
          }
        }

        // ---- tab strip -----------------------------------------------------
        Row {
          spacing: Style.space(6)

          Repeater {
            model: root.tabs
            delegate: Button {
              required property string modelData
              text: modelData
              bordered: false
              foreground: root.activeTab === modelData ? Color.accent : root.fg
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
                accentColor: Model.sportColor(modelData.sport)
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
                accentColor: Model.sportColor(modelData.sport)
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
                accentColor: Model.sportColor(modelData.sport)
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
            accentColor: Model.sportColor((root.selectedMatch || {}).sport)
            onOpenRequested: root.openArticle(url)
            onCloseRequested: root.closeMatchDetails()
          }

          Text {
            visible: !!root.detailsError
            text: root.detailsError
            color: Kit.Palette.negative
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // ================= ARTICLES =================
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.activeTab === "Articles"

          Text {
            text: "📰  Latest stories from your configured sport feeds"
            color: root.fg
            opacity: 0.7
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
                text: "🔍"
                color: root.fg
                opacity: 0.6
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
                  color: root.fg
                  opacity: 0.4
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              Text {
                id: hintText
                text: root.filteredPlayerRows.length + " players"
                color: root.fg
                opacity: 0.4
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: searchClear
                visible: root.playerFilter !== ""
                text: "✕"
                color: root.fg
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.playerFilter = ""; searchInput.text = "" }
                }
              }
            }
          }

          Text {
            visible: Object.keys(root.playerMap).length === 0
            text: "No rosters yet. Add favourite teams (with idTeam) to sports-config.json, then Refresh — their squads load into this tab."
            width: parent.width
            wrapMode: Text.WordWrap
            color: Kit.Palette.faint
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
              accentColor: root.selectedSport === "All" ? Color.accent : Model.sportColor(root.selectedSport)
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
            color: Kit.Palette.faint
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
                opacity: 0.5
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                text: modelData.team || ""
                width: parent.width - parent.spacing * 5 - Style.space(18) - ptsText.width - formText.width - playedText.width
                elide: Text.ElideRight
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: parseInt(modelData.rank, 10) <= 4
              }
              Text {
                id: playedText
                text: (modelData.played || "") + "P"
                color: root.fg
                opacity: 0.45
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                id: formText
                text: modelData.form || ""
                color: root.fg
                opacity: 0.6
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
            color: Kit.Palette.faint
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

          Button {
            text: root.predicting ? "Predicting…" : "Run prediction"
            enabled: !root.predicting && root.predictHome !== "" && root.predictAway !== ""
            foreground: root.fg
            bordered: true
            onClicked: root.runPrediction(root.predictHome, root.predictAway)
          }

          PredictionCard {
            visible: root.prediction !== null
            width: parent.width
            prediction: root.prediction
            barForeground: root.fg
            accentColor: root.selectedSport === "All" ? Color.accent : Model.sportColor(root.selectedSport)
          }
        }

        PanelSeparator {}

        // ================= ASK AI =================
        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "ASK THE ANALYST"
            color: Qt.darker(root.fg, 1.4)
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
                  opacity: 0.4
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            Button {
              id: aiButton
              text: root.aiBusy ? "…" : "Ask"
              enabled: !root.aiBusy
              foreground: root.fg
              bordered: true
              onClicked: root.askAi(aiInput.text)
            }
          }

          Text {
            visible: root.aiAnswer !== ""
            text: root.aiAnswer
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator {}

        Text {
          text: "Enter: refresh now  ·  Esc: close"
          color: Qt.darker(root.fg, 1.4)
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
