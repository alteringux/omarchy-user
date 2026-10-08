import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// The intrusion surface. One window, two intensities, chosen by the daemon:
//   checkin   — a centred card over a light scrim, keyboard focus on demand.
//   takeover  — the whole screen, near-opaque, EXCLUSIVE keyboard focus, so it
//               can't be Alt-Tabbed past. Fired on a hard deadline, a badly
//               overdue task, or too many dismissed check-ins in a row.
//
// It renders straight from the host widget's watched stores and turns every
// button into an omarchy-grip verb via the host. It never writes state itself.
Item {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  property var hostWidget: null

  readonly property string mode: hostWidget ? hostWidget.promptKind : ""
  readonly property bool takeover: mode === "takeover"
  readonly property var tasksValue: hostWidget ? hostWidget.tasksValue : Model.defaultTasks()
  readonly property var stateValue: hostWidget ? hostWidget.stateValue : Model.defaultState()
  readonly property var configValue: hostWidget ? hostWidget.configValue : Model.defaultConfig()

  property double nowMs: Date.now()
  Timer { interval: 10000; repeat: true; running: root.mode !== ""; onTriggered: root.nowMs = Date.now() }

  readonly property var rows: Model.topTasks(root.tasksValue, root.nowMs, root.takeover ? 99 : 3)
  readonly property string reason: Model.escalationReason(root.configValue, root.stateValue, root.tasksValue, root.nowMs)

  readonly property string headline: {
    if (!root.takeover) return "Quick check-in"
    if (root.reason === "deadline") return "A hard deadline just hit."
    if (root.reason === "overdue") return "Something's badly overdue."
    if (root.reason === "dismissed") return "You've waved this away " + root.stateValue.dismissStreak + " times."
    return "Deal with this."
  }

  function tickTask(id) {
    if (!root.hostWidget) return
    if (root.takeover) root.hostWidget.completeTask(id)
    else root.hostWidget.ackDid(id)          // a check-in you actually acted on
  }

  PanelWindow {
    id: win
    visible: root.mode !== ""
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omarchy-grip-prompt"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.takeover ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, root.takeover ? 0.92 : 0.45)

      // Clicking the scrim dismisses a check-in (soft). A takeover ignores it —
      // use a button.
      MouseArea {
        anchors.fill: parent
        enabled: !root.takeover
        onClicked: if (root.hostWidget) root.hostWidget.ackDismiss()
      }

      Keys.onEscapePressed: {
        if (!root.hostWidget) return
        if (root.takeover) root.hostWidget.ackHear()   // "I hear you — 10 min"
        else root.hostWidget.ackDismiss()
      }
      focus: true

      Rectangle {
        id: card
        anchors.centerIn: parent
        width: root.takeover
          ? Math.min(parent.width - Style.space(120), Style.space(720))
          : Math.min(parent.width - Style.space(60), Style.space(440))
        height: Math.min(parent.height - Style.space(60), cardCol.implicitHeight + Style.space(48))
        radius: Style.cornerRadius
        color: _webPalette.barBackground
        border.width: 1
        border.color: root.takeover
          ? _webPalette.negative
          : Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, 0.25)

        MouseArea { anchors.fill: parent }   // swallow clicks so the scrim handler doesn't fire

        Column {
          id: cardCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(24)
          spacing: Style.space(14)

          Text {
            width: parent.width
            text: root.headline
            wrapMode: Text.WordWrap
            color: _webPalette.barForeground
            font.family: Style.font.family
            font.pixelSize: root.takeover ? Style.font.title : Style.font.heading
            font.bold: true
          }
          Text {
            id: actionFeedbackText
            width: parent.width
            visible: !!(root.hostWidget && root.hostWidget.actionStatus)
            text: root.hostWidget ? root.hostWidget.actionStatus : ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.hostWidget && root.hostWidget.actionFailed ? _webPalette.negative : _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            Accessible.role: Accessible.StaticText
            Accessible.name: text
            Connections {
              target: root.hostWidget
              ignoreUnknownSignals: true
              function onActionFeedback(message) {
                if (win.visible && actionFeedbackText.visible) actionFeedbackText.Accessible.announce(message)
              }
            }
          }

          Text {
            width: parent.width
            text: Qt.formatDateTime(new Date(), "dddd HH:mm")
              + " · " + root.stateValue.dismissStreak + " dismissed in a row"
            visible: root.takeover
            color: _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            visible: root.rows.length === 0
            text: "Nothing open right now — dismiss this."
            color: _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          // ---- task rows -------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.rows

              Rectangle {
                id: prow
                width: parent.width
                height: Style.space(38)
                radius: Style.cornerRadius
                color: Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, hov.containsMouse ? 0.10 : 0.05)

                required property var modelData
                readonly property var task: modelData
                readonly property real dueDelta: task.due != null ? task.due - root.nowMs : 0
                readonly property bool overdue: task.due != null && dueDelta <= 0

                MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  spacing: Style.space(10)

                  Kit.ActionButton {
                    id: box
                    width: Style.space(24)
                    height: Style.space(24)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✓"
                    focusable: true
                    Accessible.role: Accessible.Button
                    Accessible.name: (root.takeover ? "Complete task: " : "Confirm you handled: ") + prow.task.text
                    foreground: _webPalette.barForeground
                    bordered: false
                    onClicked: root.tickTask(prow.task.id)
                  }

                  MarqueeText {
                    width: parent.width - box.width - rowDue.width - parent.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: (prow.task.hard ? "! " : "") + prow.task.text
                    requestedElide: Text.ElideRight
                    color: _webPalette.barForeground
                    textFont.family: Style.font.family
                    textFont.pixelSize: Style.font.body
                    textFont.bold: prow.task.hard
                  }

                  Text {
                    id: rowDue
                    anchors.verticalCenter: parent.verticalCenter
                    visible: prow.task.due != null || prow.task.source !== "typed"
                    text: prow.task.due != null ? Model.formatDue(prow.dueDelta, root.nowMs) : prow.task.source
                    color: prow.overdue ? _webPalette.negative : _webPalette.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }
          }

          // ---- exits ---------------------------------------------------
          Flow {
            width: parent.width
            spacing: Style.space(8)

            Kit.ActionButton {
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: text
              visible: root.takeover
              text: "I hear you — 10 min"
              foreground: _webPalette.barForeground
              bordered: true
              onClicked: if (root.hostWidget) root.hostWidget.ackHear()
            }
            Kit.ActionButton {
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: text
              visible: !root.takeover
              text: "Not now"
              foreground: _webPalette.barForeground
              bordered: true
              onClicked: if (root.hostWidget) root.hostWidget.ackDismiss()
            }
            Kit.ActionButton {
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: text
              visible: !root.takeover
              text: "15 min"
              foreground: _webPalette.barForeground
              bordered: true
              onClicked: if (root.hostWidget) root.hostWidget.ackSnooze(15)
            }
            Kit.ActionButton {
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: text
              text: root.takeover ? "Snooze 1h" : "1 hour"
              foreground: _webPalette.barForeground
              bordered: true
              onClicked: if (root.hostWidget) root.hostWidget.ackSnooze(60)
            }
          }
        }
      }
    }
  }
}
