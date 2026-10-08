import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Global movers popup: hero top-gainer/worst-loser, a 52-week-range filter,
// two card grids (top-10 gainers, top-10 losers, from bin/omarchy-stocks-
// refresh's merged per-region screener query), and a Trending searches strip.
// See ADR 0001 (local shortcuts + hint row) and ADR 0002 (this is its own
// plugin, not a Dashboard card).
Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.stocks"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var guard: Kit.BugGuard.create("alteringux.stocks", function(argv) { Quickshell.execDetached(argv) })

  readonly property var gainers: hostWidget ? hostWidget.gainers : []
  readonly property var losers: hostWidget ? hostWidget.losers : []
  readonly property var trendingSymbols: hostWidget ? hostWidget.trendingSymbols : []
  readonly property bool refreshing: hostWidget ? hostWidget.refreshing : false
  readonly property bool providerStale: hostWidget ? hostWidget.providerStale : false
  readonly property string providerError: hostWidget && hostWidget.providerError ? hostWidget.providerError : ""

  function quoteFreshness() {
    var updatedAt = hostWidget && hostWidget.state ? Date.parse(hostWidget.state.updatedAt || "") : NaN
    return isFinite(updatedAt)
      ? "Yahoo Finance · fetched " + Qt.formatDateTime(new Date(updatedAt), "hh:mm")
      : "Yahoo Finance · no successful fetch yet"
  }

  // Panel-local, not persisted: resets to FILTER_ALL each time the panel opens.
  property string filterMode: Model.FILTER_ALL

  readonly property var filteredGainers: gainers.filter(function (q) { return Model.passes52wFilter(q, root.filterMode) })
  readonly property var filteredLosers: losers.filter(function (q) { return Model.passes52wFilter(q, root.filterMode) })

  readonly property var heroTop: gainers.length ? gainers[0] : null
  readonly property var heroWorst: losers.length ? losers[0] : null

  readonly property color upColor: _webPalette.statusColorFor("positive", _webPalette.cardBackgroundFor(root.barForeground))
  readonly property color downColor: _webPalette.statusColorFor("negative", _webPalette.cardBackgroundFor(root.barForeground))
  function moveColor(pct) {
    var dir = Model.changeDirection(pct)
    if (dir === "up") return root.upColor
    if (dir === "down") return root.downColor
    return root.barForeground
  }

  // Opens a symbol's Yahoo Finance quote page — used by the trending pills,
  // which are bare search-trend symbols with no price data of their own.
  function openSymbol(symbol) {
    guard.run("openSymbol", function() {
      Quickshell.execDetached(["xdg-open", "https://finance.yahoo.com/quote/" + symbol])
    })
  }

  readonly property var filterOptions: [
    { key: Model.FILTER_ALL, label: "All" },
    { key: Model.FILTER_NEAR_HIGH, label: "Near 52w High" },
    { key: Model.FILTER_NEAR_LOW, label: "Near 52w Low" }
  ]

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(560)))

    Kit.PanelKeys {
      anchors.fill: parent

      onCloseRequested: root.close()
      onActivateRequested: if (hostWidget) hostWidget.runRefresh()
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Refresh stock data", context: "Stocks · shortcut focus" }
      ]

    Kit.PanelScroll {
      anchors.fill: parent
      contentHeight: content.implicitHeight

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.panelGap

        Kit.PanelHead {
          glyph: ""   // nf-fa-line_chart, matches the bar widget
          title: "Stocks"
          meta: root.refreshing
            ? "refreshing" + (root.providerStale ? " · stale" : "") + " · " + root.quoteFreshness()
            : (root.providerStale
              ? "provider unavailable · stale · " + root.quoteFreshness()
              : (root.providerError
                ? root.providerError + " · " + root.quoteFreshness()
                : root.quoteFreshness() + " · global top movers"))
          foreground: root.barForeground
          trailingControl: Component {
            Kit.ActionButton {
              text: "Refresh"
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: "Refresh stock movers"
              foreground: root.barForeground
              bordered: true
              onClicked: if (hostWidget) hostWidget.runRefresh()
            }
          }
        }

        // ---- Hero: biggest global gainer/loser
        RowLayout {
          width: parent.width
          spacing: Style.spacing.panelGap
          visible: root.heroTop !== null || root.heroWorst !== null

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            height: Style.space(52)
            radius: Style.cornerRadius
            color: _webPalette.cardBackgroundFor(root.barForeground)
            border.width: 1
            border.color: _webPalette.cardBorderFor(root.barForeground)

            Column {
              anchors.centerIn: parent
              spacing: Style.space(2)
              Text { text: "Top gainer"; color: _webPalette.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
              Text {
                text: root.heroTop ? (root.heroTop.symbol + "  " + Model.formatChangePct(root.heroTop.changePct)) : "—"
                color: root.heroTop ? root.moveColor(root.heroTop.changePct) : root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            height: Style.space(52)
            radius: Style.cornerRadius
            color: _webPalette.cardBackgroundFor(root.barForeground)
            border.width: 1
            border.color: _webPalette.cardBorderFor(root.barForeground)

            Column {
              anchors.centerIn: parent
              spacing: Style.space(2)
              Text { text: "Top loser"; color: _webPalette.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
              Text {
                text: root.heroWorst ? (root.heroWorst.symbol + "  " + Model.formatChangePct(root.heroWorst.changePct)) : "—"
                color: root.heroWorst ? root.moveColor(root.heroWorst.changePct) : root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
              }
            }
          }
        }

        // ---- 52-week range filter
        Row {
          spacing: Style.space(6)

          Repeater {
            model: root.filterOptions
            delegate: Kit.ActionButton {
              required property var modelData
              text: modelData.label
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: "Filter stock movers: " + modelData.label
              bordered: true
              foreground: root.filterMode === modelData.key ? _webPalette.accent : root.barForeground
              onClicked: root.filterMode = modelData.key
            }
          }
        }

        PanelSectionHeader {
          text: "TOP GAINERS — WORLDWIDE"
          foreground: root.barForeground
        }

        GridLayout {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(10)
          rowSpacing: Style.space(10)

          Repeater {
            model: root.filteredGainers
            delegate: MoverCard {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              quote: modelData
              barForeground: root.barForeground
              accentColor: root.moveColor(modelData.changePct)
            }
          }
        }

        Kit.EmptyState {
          visible: root.filteredGainers.length === 0
          text: root.gainers.length === 0
            ? (root.refreshing ? "Loading…" : (root.providerError ? "Provider unavailable" : "No data yet"))
            : "None match this filter."
          hint: root.gainers.length === 0 && !root.refreshing ? "Try Refresh." : ""
          foreground: root.barForeground
        }

        PanelSectionHeader {
          text: "TOP LOSERS — WORLDWIDE"
          foreground: root.barForeground
        }

        GridLayout {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(10)
          rowSpacing: Style.space(10)

          Repeater {
            model: root.filteredLosers
            delegate: MoverCard {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              quote: modelData
              barForeground: root.barForeground
              accentColor: root.moveColor(modelData.changePct)
            }
          }
        }

        Kit.EmptyState {
          visible: root.filteredLosers.length === 0
          text: root.losers.length === 0
            ? (root.refreshing ? "Loading…" : (root.providerError ? "Provider unavailable" : "No data yet"))
            : "None match this filter."
          hint: root.losers.length === 0 && !root.refreshing ? "Try Refresh." : ""
          foreground: root.barForeground
        }

        PanelSeparator {}

        Text {
          text: "Trending searches — click to view"
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.trendingSymbols
            delegate: Kit.ActionButton {
              required property string modelData
              text: modelData
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: "View stock quote for " + modelData
              foreground: root.barForeground
              fontSize: Style.font.caption
              bordered: true
              onClicked: root.openSymbol(modelData)
            }
          }
        }

        PanelSeparator {}

        Text {
          text: "Enter: refresh now  ·  Esc: close"
          color: _webPalette.contrastColorFor(Qt.darker(root.barForeground, 1.4), _webPalette.barBackground)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
    }
  }
}
