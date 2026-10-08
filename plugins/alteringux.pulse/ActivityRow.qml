import QtQuick
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit
import "Model.js" as Model
import "../shared"

Rectangle {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  objectName: "pulse-activity-row"

  required property var modelData
  required property double nowMs
  required property double lastReadTs
  required property color barForeground
  required property color faintForeground
  required property color unreadColor

  readonly property var eventData: modelData
  readonly property bool unread: eventData.ts > lastReadTs
  readonly property bool hasAction: eventData.action.length > 0
  readonly property bool hasSeverity: ["critical", "urgent", "warning", "warn"].indexOf(eventData.level) >= 0
  readonly property bool hovered: rowHover.hovered
  readonly property bool actionVisible: root.hasAction && openButton.opacity > 0

  signal openRequested(string action)

  // Reserve the action button's height before hover shows it so the feed row
  // and its popup keep stable bounds under a stationary pointer.
  implicitHeight: eventContent.implicitHeight + Style.space(4)
  radius: Style.cornerRadius
  color: hovered ? Qt.rgba(unreadColor.r, unreadColor.g, unreadColor.b, 0.10)
    : root.unread ? Qt.rgba(unreadColor.r, unreadColor.g, unreadColor.b, 0.07)
    : "transparent"
  border.width: root.hasSeverity ? 1 : 0
  border.color: root.unread || root.hasSeverity
    ? Qt.rgba(unreadColor.r, unreadColor.g, unreadColor.b, 0.3)
    : "transparent"

  HoverHandler { id: rowHover }

  Rectangle {
    width: Style.space(3)
    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
    radius: width / 2
    visible: root.unread || root.hasSeverity
    color: root.unreadColor
    opacity: root.unread ? 1 : 0.8
  }

  Flow {
    id: eventContent
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(14)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(6)

    MarqueeText {
      id: sourceLabel
      width: Math.min(Style.space(64), eventContent.width)
      text: root.eventData.plugin.replace(/^alteringux\./, "")
      requestedElide: Text.ElideRight
      color: root.unread ? root.unreadColor : root.faintForeground
      textFont.family: Style.font.family
      textFont.pixelSize: Style.font.caption
      textFont.bold: true
    }

    Rectangle {
      id: levelBadge
      visible: root.hasSeverity
      width: visible ? levelText.implicitWidth + Style.space(10) : 0
      height: levelText.implicitHeight + Style.space(4)
      radius: Style.cornerRadius
      color: Qt.rgba(root.unreadColor.r, root.unreadColor.g, root.unreadColor.b, 0.12)
      Text {
        id: levelText
        anchors.centerIn: parent
        text: root.eventData.level === "warn" ? "WARNING" : root.eventData.level.toUpperCase()
        textFormat: Text.PlainText
        color: root.unreadColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    MarqueeText {
      id: messageText
      readonly property real remainingWidth: eventContent.width - sourceLabel.width
        - levelBadge.width - timeLabel.implicitWidth - actionSlot.width
        - eventContent.spacing * (2 + (root.hasSeverity ? 1 : 0) + (root.hasAction ? 1 : 0))
      // Keep the feed to one line when the message still has room to read;
      // Flow wraps the remaining fields when the fixed metadata crowds it.
      width: Math.min(eventContent.width, Math.max(Style.space(80), remainingWidth))
      text: root.eventData.message
      requestedElide: Text.ElideRight
      requestedWrapMode: Text.NoWrap
      requestedMaximumLineCount: 1
      color: root.barForeground
      textFont.family: Style.font.family
      textFont.pixelSize: Style.font.bodySmall
      textFont.bold: root.unread
    }

    Text {
      id: timeLabel
      text: Model.relTime(root.nowMs - root.eventData.ts)
      color: root.faintForeground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Item {
      id: actionSlot
      width: root.hasAction ? Math.min(openButton.implicitWidth, eventContent.width, Style.space(112)) : 0
      height: root.hasAction ? openButton.implicitHeight : 0
      visible: root.hasAction

      Kit.ActionButton {
        id: openButton
        objectName: "pulse-activity-action"
        anchors.fill: parent
        opacity: rowHover.hovered || activeFocus ? 1 : 0
        focusable: true
        text: ""
        implicitWidth: actionText.implicitWidth + horizontalPadding * 2
          + _reservedBorderLeft + _reservedBorderRight > Style.space(112)
            ? Style.space(112)
            : actionText.implicitWidth + horizontalPadding * 2
              + _reservedBorderLeft + _reservedBorderRight
        implicitHeight: actionText.implicitHeight + verticalPadding * 2
          + _reservedBorderTop + _reservedBorderBottom
        Accessible.name: actionText.text + " for " + root.eventData.plugin.replace(/^alteringux\./, "")
        Accessible.role: Accessible.Button
        foreground: root.barForeground
        bordered: true
        onClicked: root.openRequested(root.eventData.action)

        MarqueeText {
          id: actionText
          focusableOnOverflow: false
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: parent.horizontalPadding + parent._reservedBorderLeft
          anchors.rightMargin: parent.horizontalPadding + parent._reservedBorderRight
          anchors.verticalCenter: parent.verticalCenter
          text: root.eventData.actionLabel.length ? root.eventData.actionLabel : "Open"
          active: openButton.activeFocus
          requestedWrapMode: Text.NoWrap
          requestedMaximumLineCount: 1
          requestedElide: Text.ElideRight
          color: openButton.foreground
          textFont.family: openButton.fontFamily
          textFont.pixelSize: openButton.fontSize
          horizontalAlignment: Text.AlignHCenter
          Accessible.ignored: true
        }
      }
    }
  }
}
