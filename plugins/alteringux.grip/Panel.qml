import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// Quick-triage popup for the Grip widget: add a task, tick one off, and drive
// the daemon (on/off, pause, check-in now). Every control calls the same
// hostWidget function the IPC path calls, so there's one implementation each.
Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.grip"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var tasksValue: hostWidget ? hostWidget.tasksValue : Model.defaultTasks()
  readonly property var stateValue: hostWidget ? hostWidget.stateValue : Model.defaultState()
  readonly property var configValue: hostWidget ? hostWidget.configValue : Model.defaultConfig()
  readonly property string promptKind: hostWidget ? hostWidget.promptKind : ""

  property double nowMs: Date.now()
  Timer { interval: 15000; repeat: true; running: root.opened; onTriggered: root.nowMs = Date.now() }

  readonly property var openList: Model.topTasks(root.tasksValue, root.nowMs, 99)
  readonly property var summary: Model.summary(root.tasksValue, root.stateValue, root.nowMs)

  readonly property string metaLine: {
    if (!root.stateValue.enabled) return "off"
    if (root.nowMs < root.stateValue.pauseUntilMs)
      return "paused " + Model.formatDue(root.stateValue.pauseUntilMs - root.nowMs, root.nowMs).replace("in ", "") + " left"
    var bits = root.summary.open + " open"
    if (root.summary.overdue > 0) bits += " · " + root.summary.overdue + " overdue"
    if (root.stateValue.dismissStreak > 0) bits += " · " + root.stateValue.dismissStreak + " dismissed"
    return bits
  }

  function submitQuickAdd() {
    var text = quickAddInput.text
    if (!text || !text.trim().length) return
    if (hostWidget) hostWidget.addTask(text)
    quickAddInput.text = ""
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    Kit.PanelKeys {
      anchors.fill: parent
      blocked: quickAddInput.activeFocus
      onCloseRequested: root.close()

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Kit.PanelHead {
          glyph: "󰄒"   // nf-md-clipboard_text
          title: "Grip"
          meta: root.metaLine
          foreground: root.barForeground
        }
        Text {
          id: actionFeedbackText
          width: content.width
          visible: !!(root.hostWidget && root.hostWidget.actionStatus)
          text: root.hostWidget ? root.hostWidget.actionStatus : ""
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.hostWidget && root.hostWidget.actionFailed ? _webPalette.negative : _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          Accessible.role: Accessible.StaticText
          Accessible.name: text
          Connections {
            target: root.hostWidget
            ignoreUnknownSignals: true
            function onActionFeedback(message) {
              if (root.opened && actionFeedbackText.visible) actionFeedbackText.Accessible.announce(message)
            }
          }
        }

        // ---- quick add ------------------------------------------------
        Rectangle {
          width: parent.width
          height: Style.space(34)
          radius: Style.cornerRadius
          color: Util.alpha(root.barForeground, 0.08)
          border.width: 1
          border.color: quickAddInput.activeFocus
            ? _webPalette.barActive
            : Util.alpha(root.barForeground, 0.2)

          TextInput {
            id: quickAddInput
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            selectByMouse: true
            Accessible.name: "Add a task"
            Accessible.description: "Enter saves the task."
            onAccepted: root.submitQuickAdd()

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: quickAddInput.text.length === 0
              text: "Add a task — Enter to save"
              color: _webPalette.barTextColorFor(root.barForeground)
              font: quickAddInput.font
            }
          }
        }

        Text {
          width: parent.width
          visible: quickAddInput.text.length > 0
          text: "Tip: put a time in the text and add a due later with:  omarchy-grip add \"…\" --due 17:00 --hard"
          wrapMode: Text.WordWrap
          color: _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator {}

        PanelSectionHeader { text: "OPEN"; foreground: root.barForeground }

        Kit.EmptyState {
          visible: root.openList.length === 0
          width: parent.width
          foreground: root.barForeground
          text: "Nothing open."
          hint: root.stateValue.enabled ? "Grip will stretch its check-ins while it's quiet." : "Grip is off — turn it on below."
        }

        Kit.PanelScroll {
          width: parent.width
          visible: root.openList.length > 0
          height: Math.min(Style.space(240), taskColumn.implicitHeight)
          contentHeight: taskColumn.implicitHeight

          Column {
            id: taskColumn
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.openList

              Rectangle {
                id: del
                width: taskColumn.width
                height: Style.space(30)
                radius: Style.cornerRadius
                color: rowHover.containsMouse
                  ? Util.alpha(root.barForeground, 0.06)
                  : "transparent"

                required property var modelData
                readonly property var task: modelData
                readonly property real dueDelta: task.due != null ? task.due - root.nowMs : 0
                readonly property bool overdue: task.due != null && dueDelta <= 0

                MouseArea { id: rowHover; anchors.fill: parent; hoverEnabled: true }

                Row {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(4)
                  anchors.rightMargin: Style.space(4)
                  spacing: Style.space(8)

                  Kit.ActionButton {
                    id: tick
                    width: Style.space(24)
                    height: Style.space(24)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "○"
                    focusable: true
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: "Complete task: " + del.task.text
                    Accessible.description: del.task.due != null ? Model.formatDue(del.dueDelta, root.nowMs) : del.task.source
                    Accessible.checked: false
                    foreground: root.barForeground
                    bordered: false
                    onClicked: if (root.hostWidget) root.hostWidget.completeTask(del.task.id)
                  }

                  MarqueeText {
                    width: del.width - tick.width - dueLabel.width - dropBtn.width - parent.spacing * 3
                    anchors.verticalCenter: parent.verticalCenter
                    text: (del.task.hard ? "! " : "") + del.task.text
                    requestedElide: Text.ElideRight
                    color: root.barForeground
                    textFont.family: Style.font.family
                    textFont.pixelSize: Style.font.bodySmall
                    textFont.bold: del.task.hard
                  }

                  Text {
                    id: dueLabel
                    anchors.verticalCenter: parent.verticalCenter
                    visible: del.task.due != null || del.task.source !== "typed"
                    text: del.task.due != null ? Model.formatDue(del.dueDelta, root.nowMs) : del.task.source
                    color: del.overdue ? _webPalette.negative : _webPalette.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  // Keep removal reachable without depending on hover.
                  Kit.ActionButton {
                    id: dropBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(24)
                    height: Style.space(24)
                    text: "✕"
                    focusable: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Remove task: " + del.task.text
                    foreground: _webPalette.faint
                    bordered: false
                    onClicked: if (root.hostWidget) root.hostWidget.dropTask(del.task.id)
                  }
                }
              }
            }
          }
        }

        PanelSeparator {}

        PanelSectionHeader { text: "NUDGES"; foreground: root.barForeground }

        Flow {
          width: parent.width
          spacing: Style.space(8)

          Kit.ActionButton {
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            text: root.stateValue.enabled ? "Turn off" : "Turn on"
            foreground: root.barForeground
            bordered: true
            onClicked: if (root.hostWidget) root.hostWidget.setEnabled(!root.stateValue.enabled)
          }
          Kit.ActionButton {
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            text: "Check in now"
            foreground: root.barForeground
            bordered: true
            enabled: root.stateValue.enabled && root.promptKind === ""
            onClicked: if (root.hostWidget) root.hostWidget.forceCheckin()
          }
          Kit.ActionButton {
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            text: "Pause 2h"
            foreground: root.barForeground
            bordered: true
            enabled: root.stateValue.enabled
            onClicked: if (root.hostWidget) root.hostWidget.pauseFor(120)
          }
          Kit.ActionButton {
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            text: "Resume"
            foreground: root.barForeground
            bordered: true
            visible: root.nowMs < root.stateValue.pauseUntilMs
            onClicked: if (root.hostWidget) root.hostWidget.resume()
          }
        }
      }
    }
  }
}
