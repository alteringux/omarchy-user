import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One gainer/loser card in the panel's grid: symbol, exchange, price,
// %change, and a 52-week-range dot. No sparkline — the screener endpoint
// (unlike the old per-ticker chart endpoint) carries no intraday series.
Rectangle {
  id: root

  required property var quote
  property color barForeground: Color.foreground
  property color accentColor: barForeground

  Layout.preferredHeight: cardColumn.implicitHeight + Style.space(20)
  radius: Style.cornerRadius
  clip: true
  color: Util.alpha(root.barForeground, 0.05)
  border.width: 1
  border.color: Util.alpha(root.barForeground, 0.14)

  Column {
    id: cardColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(10)
    spacing: Style.space(4)

    Row {
      spacing: Style.space(6)
      Text {
        text: root.quote.symbol || "—"
        color: root.barForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        visible: !!root.quote.exchange
        text: root.quote.exchange || ""
        color: root.barForeground
        opacity: 0.5
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
    Text {
      visible: !!root.quote.name
      text: root.quote.name || ""
      width: parent.width
      elide: Text.ElideRight
      color: root.barForeground
      opacity: 0.6
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Text {
      text: Model.formatPrice(root.quote.price, root.quote.currency)
      color: root.barForeground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      text: Model.formatChangePct(root.quote.changePct)
      color: root.accentColor
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    // 52-week position: a dot along the low→high range.
    Item {
      width: parent.width
      height: Style.space(6)
      visible: Model.week52Position(root.quote.price, root.quote.week52Low, root.quote.week52High) !== null

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 2
        radius: 1
        color: Util.alpha(root.barForeground, 0.25)
      }
      Rectangle {
        readonly property real pos: Model.week52Position(root.quote.price, root.quote.week52Low, root.quote.week52High) || 0
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
