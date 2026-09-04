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

  // Panel-local, not persisted: resets to FILTER_ALL each time the panel opens.
  property string filterMode: Model.FILTER_ALL

  readonly property var filteredGainers: gainers.filter(function (q) { return Model.passes52wFilter(q, root.filterMode) })
  readonly property var filteredLosers: losers.filter(function (q) { return Model.passes52wFilter(q, root.filterMode) })

  readonly property var heroTop: gainers.length ? gainers[0] : null
  readonly property var heroWorst: losers.length ? losers[0] : null

  readonly property color upColor: "#3fb950"
  readonly property color downColor: Color.urgent
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(560)))

    PanelKeyCatcher {
      anchors.fill: parent

      onCloseRequested: root.close()
      onActivateRequested: if (hostWidget) hostWidget.runRefresh()

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
          meta: root.refreshing ? "refreshing…" : "global top movers"
          foreground: root.barForeground
          trailingControl: Component {
            Button {
              text: "Refresh"
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
            color: Util.alpha(root.barForeground, 0.05)
            border.width: 1
            border.color: Util.alpha(root.barForeground, 0.14)

            Column {
              anchors.centerIn: parent
              spacing: Style.space(2)
              Text { text: "Top gainer"; color: root.barForeground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
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
            color: Util.alpha(root.barForeground, 0.05)
            border.width: 1
            border.color: Util.alpha(root.barForeground, 0.14)

            Column {
              anchors.centerIn: parent
              spacing: Style.space(2)
              Text { text: "Top loser"; color: root.barForeground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
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
            delegate: Button {
              required property var modelData
              text: modelData.label
              bordered: true
              foreground: root.filterMode === modelData.key ? Color.accent : root.barForeground
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

        Text {
          visible: root.filteredGainers.length === 0
          text: root.gainers.length === 0 ? (root.refreshing ? "Loading…" : "No data yet — try Refresh.") : "None match this filter."
          color: root.barForeground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
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

        Text {
          visible: root.filteredLosers.length === 0
          text: root.losers.length === 0 ? (root.refreshing ? "Loading…" : "No data yet — try Refresh.") : "None match this filter."
          color: root.barForeground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator {}

        Text {
          text: "Trending searches — click to view"
          color: root.barForeground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.trendingSymbols
            delegate: Rectangle {
              required property string modelData
              radius: Style.cornerRadius
              color: Util.alpha(root.barForeground, 0.07)
              border.width: 1
              border.color: Util.alpha(root.barForeground, 0.16)
              width: pillText.implicitWidth + Style.space(16)
              height: pillText.implicitHeight + Style.space(8)

              Text {
                id: pillText
                anchors.centerIn: parent
                text: modelData
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openSymbol(modelData)
              }
            }
          }
        }

        PanelSeparator {}

        Text {
          text: "Enter: refresh now  ·  Esc: close"
          color: Qt.darker(root.barForeground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
    }
  }
}
