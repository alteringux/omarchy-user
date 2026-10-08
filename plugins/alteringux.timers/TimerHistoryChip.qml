import QtQuick
import "../shared" as Shared
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit

Rectangle {
  id: root
  property string label: ""
  property color foreground: "white"
  property color accent: foreground
  property real maxWidth: Style.space(320)
  property real maxTextWidth: Style.space(180)
  signal startRequested()
  signal forgetRequested()

  function start() {
    if (!root.visible || !root.enabled) return
    root.forceActiveFocus()
    root.startRequested()
  }

  width: Math.min(root.maxWidth, chipRow.implicitWidth + Style.space(16))
  height: chipRow.implicitHeight + Style.space(8)
  radius: Style.cornerRadius
  color: startArea.containsMouse
    ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10) : "transparent"
  border.width: startArea.activeFocus ? 2 : 1
  border.color: startArea.activeFocus ? root.accent
    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

  MouseArea {
    id: startArea
    objectName: "timer-history-start"
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: "Start timer from history label " + root.label
    Accessible.description: "Starts a timer with this saved label."
    Accessible.onPressAction: root.start()
    Keys.onReturnPressed: root.start()
    Keys.onEnterPressed: root.start()
    Keys.onSpacePressed: root.start()
    onClicked: root.start()
  }

  Row {
    id: chipRow
    anchors.centerIn: parent
    spacing: Style.space(6)

    Shared.MarqueeText {
      id: labelText
      objectName: "timer-history-label"
      text: root.label
      width: Math.max(Style.space(40), Math.min(implicitWidth, root.maxTextWidth,
        root.maxWidth - Style.space(48)))
      color: root.foreground
      textFont.family: Style.font.family
      textFont.pixelSize: Style.font.body
      active: startArea.containsMouse || startArea.activeFocus
      anchors.verticalCenter: parent.verticalCenter
    }

    Kit.ActionButton {
      objectName: "timer-history-forget"
      text: "×"
      focusable: true
      Accessible.role: Accessible.Button
      Accessible.name: "Forget timer label " + root.label
      tooltipText: "Forget " + root.label
      foreground: root.foreground
      fontSize: Style.font.body
      horizontalPadding: Style.space(4)
      verticalPadding: 0
      onClicked: root.forgetRequested()
    }
  }
}
