import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

Rectangle {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  required property var match
  property var details: null
  property bool loading: false
  property color barForeground: _webPalette.foreground
  property color accentColor: _webPalette.accent
  readonly property color textForeground: _webPalette.contrastColorFor(barForeground, color, 4.5, Color.popups.background)
  readonly property color textAccent: _webPalette.contrastColorFor(accentColor, color, 4.5, Color.popups.background)
  signal openRequested(string url)
  signal closeRequested()

  function event() { return details && details.event ? details.event : (match || {}) }
  function label(value, fallback) { return value === null || value === undefined || value === "" ? fallback : String(value) }

  width: parent ? parent.width : 0
  implicitHeight: body.implicitHeight + Style.space(20)
  radius: Style.cornerRadius
  color: Util.alpha(root.barForeground, 0.06)
  border.width: 1
  border.color: Util.alpha(root.accentColor, 0.34)

  Column {
    id: body
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(8)

    Row {
      width: parent.width
      spacing: Style.space(8)

      MarqueeText {
        text: Model.sportGlyph(root.event().sport) + "  " + label(root.event().league, "Match details")
        width: parent.width - closeButton.width
        requestedElide: Text.ElideRight
        color: root.textAccent
        textFont.family: Style.font.family
        textFont.pixelSize: Style.font.bodySmall
        textFont.bold: true
      }
      Kit.ActionButton {
        id: closeButton
        text: "×"
        focusable: true
        Accessible.role: Accessible.Button
        Accessible.name: "Close match details"
        tooltipText: "Close match details"
        foreground: root.textForeground
        fontSize: Style.font.body
        horizontalPadding: Style.space(4)
        verticalPadding: 0
        onClicked: root.closeRequested()
      }
    }

    Text {
      text: label(root.event().eventName, Model.formatMatchLabel(root.event()))
      width: parent.width
      wrapMode: Text.WordWrap
      color: root.textForeground
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Row {
      spacing: Style.space(8)
      Text {
        text: root.event().homeTeam || "TBA"
        color: root.textForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        text: Model.formatScore(root.event().homeScore, root.event().awayScore)
        color: root.textAccent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        text: root.event().awayTeam || (root.event().eventName ? "Fight card" : "TBA")
        color: root.textForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    Text {
      visible: root.loading
      text: "Loading provider details…"
      color: root.textForeground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)
      visible: !root.loading

      Repeater {
        model: [
          ["Date", root.event().dateEvent],
          ["Time", Model.formatMatchTimeOfDay(root.event())],
          ["Venue", root.event().venue],
          ["Status", root.event().status],
          ["Round", root.event().round],
          ["Season", root.event().season],
          ["Official", root.event().official],
          ["Weather", root.event().weather],
          ["Attendance", root.event().attendance]
        ].filter(function (row) { return row[1] !== null && row[1] !== undefined && row[1] !== "" })
        delegate: Rectangle {
          required property var modelData
          width: detailText.implicitWidth + Style.space(14)
          height: detailText.implicitHeight + Style.space(8)
          radius: Style.cornerRadius
          color: Util.alpha(root.barForeground, 0.07)
          Text {
            id: detailText
            anchors.centerIn: parent
            text: modelData[0] + ": " + modelData[1]
            color: root.textForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(5)
      visible: !root.loading && root.details && root.details.stats && root.details.stats.length > 0

      Text {
        text: "Match statistics"
        color: root.textForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
      Repeater {
        model: root.details && root.details.stats ? root.details.stats : []
        delegate: Row {
          required property var modelData
          width: parent.width
          spacing: Style.space(8)
          MarqueeText {
            text: modelData.name || "Stat"
            width: parent.width - homeValue.width - awayValue.width - parent.spacing * 2
            requestedElide: Text.ElideRight
            color: root.textForeground
            textFont.family: Style.font.family
            textFont.pixelSize: Style.font.caption
          }
          Text {
            id: homeValue
            text: modelData.home || "—"
            width: Style.space(54)
            horizontalAlignment: Text.AlignRight
            color: root.textForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Text {
            id: awayValue
            text: modelData.away || "—"
            width: Style.space(54)
            horizontalAlignment: Text.AlignRight
            color: root.textForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Flow {
      width: parent.width
      spacing: Style.space(8)
      visible: !root.loading

      Kit.ActionButton {
        text: "▶ YouTube highlights"
        focusable: true
        Accessible.role: Accessible.Button
        Accessible.name: "Open YouTube highlights for " + label(root.event().eventName, Model.formatMatchLabel(root.event()))
        foreground: root.textAccent
        fontSize: Style.font.caption
        horizontalPadding: Style.space(3)
        verticalPadding: 0
        bordered: false
        onClicked: root.openRequested(Model.matchHighlightsUrl(root.event()))
      }
      Kit.ActionButton {
        visible: !!(root.event().videoUrl)
        text: "󰕧 Official video"
        focusable: true
        Accessible.role: Accessible.Button
        Accessible.name: "Open official video for " + label(root.event().eventName, Model.formatMatchLabel(root.event()))
        foreground: root.textAccent
        fontSize: Style.font.caption
        horizontalPadding: Style.space(3)
        verticalPadding: 0
        bordered: false
        onClicked: root.openRequested(root.event().videoUrl)
      }
      Kit.ActionButton {
        text: "󰍉 Official coverage"
        focusable: true
        Accessible.role: Accessible.Button
        Accessible.name: "Open official coverage for " + label(root.event().eventName, Model.formatMatchLabel(root.event()))
        foreground: root.textForeground
        fontSize: Style.font.caption
        horizontalPadding: Style.space(3)
        verticalPadding: 0
        bordered: false
        onClicked: root.openRequested(Model.matchCoverageUrl(root.event()))
      }
    }

    Kit.EmptyState {
      visible: !root.loading && (!root.details || !root.details.stats || root.details.stats.length === 0)
      text: "No provider statistics returned"
      hint: "The event details above are still available."
      foreground: root.textForeground
    }
  }
}
