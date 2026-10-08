import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit
import "Model.js" as Model

// Prediction result card: predicted winner, confidence bar, and the four
// factor rows from the predictor's breakdown.
Rectangle {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  required property var prediction   // Model.parsePrediction() output
  property color barForeground: _webPalette.foreground
  property color accentColor: _webPalette.accent
  readonly property color textForeground: _webPalette.contrastColorFor(
    root.barForeground, root.color, 4.5, Color.popups.background)
  readonly property color textAccent: _webPalette.contrastColorFor(
    root.accentColor, root.color, 4.5, Color.popups.background)

  Layout.preferredHeight: col.implicitHeight + Style.space(16)
  radius: Style.cornerRadius
  clip: true
  color: _webPalette.cardBackgroundFor(root.barForeground)
  border.width: 1
  border.color: _webPalette.cardBorderFor(root.barForeground)

  Column {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(8)
    spacing: Style.space(4)

    // error / empty state
    Text {
      visible: !!(root.prediction && root.prediction.error)
      text: (root.prediction && root.prediction.error) || ""
      width: parent.width
      wrapMode: Text.WordWrap
      color: _webPalette.contrastColorFor(_webPalette.warning, root.color, 4.5, Color.popups.background)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      visible: !!(root.prediction && root.prediction.predictedWinner)
      text: root.prediction && root.prediction.predictedWinner
        ? "Predicted winner: " + root.prediction.predictedWinner
        : ""
      color: root.textAccent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }

    // confidence bar
    Item {
      visible: !!(root.prediction && root.prediction.confidence !== null)
      width: parent.width
      height: Style.space(8)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: Util.alpha(root.barForeground, 0.18)
      }
      Rectangle {
        readonly property real frac: root.prediction ? Math.max(0, Math.min(1, root.prediction.confidence || 0)) : 0
        width: parent.width * frac
        height: 4
        radius: 2
        color: root.accentColor
      }
      Text {
        anchors.right: parent.right
        anchors.top: parent.bottom
        text: root.prediction && root.prediction.confidence !== null
          ? Math.round(root.prediction.confidence * 100) + "% confidence"
          : ""
        color: root.textForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Repeater {
      model: root.prediction && root.prediction.breakdown ? [
        { label: "Form (last 5)", value: root.prediction.breakdown.form },
        { label: "Head-to-head", value: root.prediction.breakdown.h2h },
        { label: "Home advantage", value: root.prediction.breakdown.home },
        { label: "Standing gap", value: root.prediction.breakdown.standing }
      ] : []

      delegate: Row {
        required property var modelData
        width: parent.width
        spacing: Style.space(6)
        Text {
          text: modelData.label
          width: parent.width - valText.width - parent.spacing
          color: root.textForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Text {
          id: valText
          text: modelData.value === null || modelData.value === undefined ? "n/a" : (modelData.value > 0 ? "+" : "") + modelData.value
          color: modelData.value > 0
            ? _webPalette.contrastColorFor(_webPalette.positive, root.color, 4.5, Color.popups.background)
            : (modelData.value < 0
              ? _webPalette.contrastColorFor(_webPalette.negative, root.color, 4.5, Color.popups.background)
              : root.textForeground)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }

    Text {
      visible: !!(root.prediction && root.prediction.predictedWinner)
      text: "Comparisons only — not betting advice."
      color: _webPalette.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
