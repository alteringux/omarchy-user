import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit

// Compact RSS/Atom story row. The URL is opened only after validating it in
// Panel.qml, keeping this visual component free of process-launch logic.
Rectangle {
  id: root

  required property var article
  required property color barForeground
  signal openRequested(string url)

  implicitHeight: body.implicitHeight + Style.space(20)
  radius: Style.cornerRadius
  color: Util.alpha(root.barForeground, 0.06)
  border.width: 1
  border.color: Util.alpha(root.barForeground, 0.14)

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

      Text {
        Layout.fillWidth: true
        text: root.article.title || "Untitled article"
        color: root.barForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
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
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    Row {
      spacing: Style.space(8)

      Text {
        text: root.article.source || "Feed"
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        visible: !!root.article.published
        text: root.article.published || ""
        color: Kit.Palette.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Text {
      visible: !!root.article.summary
      width: parent.width
      text: root.article.summary || ""
      color: root.barForeground
      opacity: 0.72
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.openRequested(root.article.url || "")
  }
}
