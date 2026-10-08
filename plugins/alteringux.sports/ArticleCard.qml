import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit
import "../shared"

// Compact RSS/Atom story row. The URL is opened only after validating it in
// Panel.qml, keeping this visual component free of process-launch logic.
Rectangle {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  required property var article
  required property color barForeground
  signal openRequested(string url)
  activeFocusOnTab: true
  Accessible.role: Accessible.Link
  Accessible.name: "Open article: " + (root.article.title || "Untitled article")
  Accessible.onPressAction: root.openRequested(root.article.url || "")

  implicitHeight: body.implicitHeight + Style.space(20)
  radius: Style.cornerRadius
  color: Util.alpha(root.barForeground, 0.06)
  border.width: 1
  border.color: activeFocus ? _webPalette.accent : _webPalette.cardBorderFor(root.barForeground)

  Keys.onReturnPressed: root.openRequested(root.article.url || "")
  Keys.onSpacePressed: root.openRequested(root.article.url || "")

  Column {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(10)
    spacing: Style.space(4)

    RowLayout {
      width: parent.width
      spacing: Style.space(8)

      MarqueeText {
        Layout.fillWidth: true
        text: root.article.title || "Untitled article"
        color: root.barForeground
        textFont.family: Style.font.family
        textFont.pixelSize: Style.font.bodySmall
        textFont.bold: true
        requestedWrapMode: Text.WordWrap
        requestedMaximumLineCount: 2
        requestedElide: Text.ElideRight
      }
      Image {
        Layout.preferredWidth: Style.space(72)
        Layout.preferredHeight: Style.space(44)
        visible: source !== ""
        source: root.article.image || ""
        asynchronous: true
        sourceSize.width: Style.space(144)
        sourceSize.height: Style.space(88)
        fillMode: Image.PreserveAspectCrop
      }

      Text {
        text: "↗"
        color: _webPalette.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    Row {
      spacing: Style.space(8)

      Text {
        text: root.article.source || "Feed"
        color: _webPalette.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      MarqueeText {
        visible: !!root.article.published
        text: root.article.published || ""
        color: _webPalette.faint
        textFont.family: Style.font.family
        textFont.pixelSize: Style.font.caption
        requestedElide: Text.ElideRight
      }
    }

    MarqueeText {
      visible: !!root.article.summary
      width: parent.width
      text: root.article.summary || ""
      color: root.barForeground
      textFont.family: Style.font.family
      textFont.pixelSize: Style.font.caption
      requestedWrapMode: Text.WordWrap
      requestedMaximumLineCount: 2
      requestedElide: Text.ElideRight
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: { root.forceActiveFocus(); root.openRequested(root.article.url || "") }
  }
}
