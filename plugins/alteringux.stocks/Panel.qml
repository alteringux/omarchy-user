import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Watchlist overview popup: hero top/worst mover, a 52-week-range filter,
// a card grid per tracked ticker (price, change, sparkline, 52w position),
// and a market-wide Trending section (day gainers/losers + trending
// symbols). See ADR 0001 (local shortcuts + hint row) and ADR 0002 (this
// is its own plugin, not a Dashboard card).
Panel {
  id: root
  moduleName: "alteringux.stocks"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var watchlistQuotes: hostWidget ? hostWidget.watchlistQuotes : []
  readonly property var gainers: hostWidget ? hostWidget.gainers : []
  readonly property var losers: hostWidget ? hostWidget.losers : []
  readonly property var trendingSymbols: hostWidget ? hostWidget.trendingSymbols : []
  readonly property bool refreshing: hostWidget ? hostWidget.refreshing : false

  // Panel-local, not persisted: resets to FILTER_ALL each time the panel opens.
  property string filterMode: Model.FILTER_ALL

  readonly property var filteredWatchlist: watchlistQuotes.filter(function (q) { return Model.passes52wFilter(q, root.filterMode) })
  readonly property var filteredGainers: gainers.slice(0, 5).filter(function (q) { return Model.passes52wFilter(q, root.filterMode) })
  readonly property var filteredLosers: losers.slice(0, 5).filter(function (q) { return Model.passes52wFilter(q, root.filterMode) })

  readonly property var heroTop: Model.topMover(watchlistQuotes)
  readonly property var heroWorst: Model.worstMover(watchlistQuotes)

  readonly property color upColor: "#3fb950"
  readonly property color downColor: Color.urgent
  function moveColor(pct) {
    var dir = Model.changeDirection(pct)
    if (dir === "up") return root.upColor
    if (dir === "down") return root.downColor
    return root.barForeground
  }

  function anyFieldFocused() {
    return addField.activeFocus
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
      blocked: root.anyFieldFocused()

      onCloseRequested: root.close()
      onActivateRequested: if (hostWidget) hostWidget.runRefresh()
      onDeleteRequested: if (hostWidget) hostWidget.clearWatchlist()

    Flickable {
      anchors.fill: parent
      clip: true
      contentHeight: content.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.panelGap

        RowLayout {
          width: parent.width
          spacing: Style.spacing.md

          PanelSectionHeader {
            text: "STOCKS"
            foreground: root.barForeground
            Layout.fillWidth: true
          }

          Text {
            visible: root.refreshing
            text: "refreshing…"
            color: root.barForeground
            opacity: 0.55
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Button {
            text: "Refresh"
            foreground: root.barForeground
            bordered: true
            onClicked: if (hostWidget) hostWidget.runRefresh()
          }
        }

        // ---- Hero: top/worst mover in your own watchlist
        RowLayout {
          width: parent.width
          spacing: Style.spacing.panelGap
          visible: root.heroTop !== null

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
              Text { text: "Top mover"; color: root.barForeground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
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
              Text { text: "Worst mover"; color: root.barForeground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
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

        // ---- Watchlist card grid
        GridLayout {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(10)
          rowSpacing: Style.space(10)

          Repeater {
            model: root.filteredWatchlist
            delegate: Rectangle {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              // Sized to the column's actual content (symbol + price + change
              // + sparkline + 52w bar) rather than a guessed fixed height —
              // a hardcoded height here previously ran a few px short of real
              // font metrics, and with no clip, the sparkline/52w bar bled
              // out the bottom of the card into the row below it.
              Layout.preferredHeight: cardColumn.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              clip: true
              color: Util.alpha(root.barForeground, 0.05)
              border.width: 1
              border.color: Util.alpha(root.barForeground, 0.14)

              Text {
                text: "×"
                color: root.barForeground
                opacity: 0.5
                font.pixelSize: Style.font.body
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.space(6)

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -6
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (hostWidget) hostWidget.removeTicker(modelData.symbol)
                }
              }

              Column {
                id: cardColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(10)
                spacing: Style.space(4)

                Text {
                  text: modelData.symbol
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  text: modelData.ok ? ("$" + modelData.price.toFixed(2)) : "no data"
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  visible: modelData.ok
                  text: Model.formatChangePct(modelData.changePct)
                  color: root.moveColor(modelData.changePct)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Shape {
                  width: parent.width
                  height: Style.space(22)
                  visible: modelData.series && modelData.series.length > 1
                  preferredRendererType: Shape.CurveRenderer

                  ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.moveColor(modelData.changePct)
                    strokeWidth: 1.5
                    PathSvg { path: Model.sparklinePath(modelData.series, parent.width, Style.space(22)) }
                  }
                }

                // 52-week position: a dot along the low→high range.
                Item {
                  width: parent.width
                  height: Style.space(6)
                  visible: modelData.ok && Model.week52Position(modelData.price, modelData.week52Low, modelData.week52High) !== null

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 2
                    radius: 1
                    color: Util.alpha(root.barForeground, 0.25)
                  }
                  Rectangle {
                    readonly property real pos: Model.week52Position(modelData.price, modelData.week52Low, modelData.week52High) || 0
                    x: pos * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(6)
                    height: Style.space(6)
                    radius: width / 2
                    color: Color.accent
                  }
                }
              }
            }
          }
        }

        Text {
          visible: root.filteredWatchlist.length === 0
          text: root.watchlistQuotes.length === 0 ? "Empty. Add a ticker below." : "No tickers match this filter."
          color: root.barForeground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          width: content.width
          spacing: Style.space(8)

          TextField {
            id: addField
            width: parent.width - addButton.implicitWidth - parent.spacing
            placeholderText: "Add ticker (e.g. MSFT)"
            foreground: root.barForeground
            onAccepted: {
              if (hostWidget) hostWidget.addTicker(text)
              text = ""
            }
          }
          Button {
            id: addButton
            text: "Add"
            foreground: root.barForeground
            bordered: true
            onClicked: {
              if (hostWidget) hostWidget.addTicker(addField.text)
              addField.text = ""
            }
          }
        }

        PanelSeparator {}

        PanelSectionHeader {
          text: "TRENDING"
          foreground: root.barForeground
        }

        RowLayout {
          width: parent.width
          spacing: Style.spacing.panelGap

          Column {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: Style.space(4)

            Text { text: "Gainers"; color: root.barForeground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Repeater {
              model: root.filteredGainers
              delegate: RowLayout {
                required property var modelData
                width: parent.width
                Text { text: modelData.symbol; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
                Text { text: Model.formatChangePct(modelData.changePct); color: root.moveColor(modelData.changePct); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
              }
            }
            Text {
              visible: root.filteredGainers.length === 0
              text: "None match this filter."
              color: root.barForeground
              opacity: 0.5
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: Style.space(4)

            Text { text: "Losers"; color: root.barForeground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Repeater {
              model: root.filteredLosers
              delegate: RowLayout {
                required property var modelData
                width: parent.width
                Text { text: modelData.symbol; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
                Text { text: Model.formatChangePct(modelData.changePct); color: root.moveColor(modelData.changePct); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
              }
            }
            Text {
              visible: root.filteredLosers.length === 0
              text: "None match this filter."
              color: root.barForeground
              opacity: 0.5
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Text {
          text: "Trending searches — click to add"
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
                onClicked: if (hostWidget) hostWidget.addTicker(modelData)
              }
            }
          }
        }

        PanelSeparator {}

        Text {
          text: "Enter: refresh now  ·  X: clear watchlist  ·  Esc: close"
          color: Qt.darker(root.barForeground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
    }
  }
}
