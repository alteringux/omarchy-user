import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// The intrusion surface. One window, two intensities, chosen by the daemon:
//   checkin   — a centred card over a light scrim, keyboard focus on demand.
//   takeover  — the whole screen, near-opaque, EXCLUSIVE keyboard focus, so it
//               can't be Alt-Tabbed past. Fired on a hard deadline, a badly
//               overdue task, or too many dismissed check-ins in a row.
//
// It renders straight from the host widget's watched stores and turns every
// button into an omarchy-grip verb via the host. It never writes state itself.
Item {
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
        color: Color.bar.background
        border.width: 1
        border.color: root.takeover
          ? Kit.Palette.negative
          : Qt.rgba(Color.bar.text.r, Color.bar.text.g, Color.bar.text.b, 0.25)

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
            color: Color.bar.text
            font.family: Style.font.family
            font.pixelSize: root.takeover ? Style.font.title : Style.font.heading
            font.bold: true
          }

          Text {
            width: parent.width
            text: Qt.formatDateTime(new Date(), "dddd HH:mm")
              + " · " + root.stateValue.dismissStreak + " dismissed in a row"
            visible: root.takeover
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            visible: root.rows.length === 0
            text: "Nothing open right now — dismiss this."
            color: Kit.Palette.faint
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
                color: Qt.rgba(Color.bar.text.r, Color.bar.text.g, Color.bar.text.b, hov.containsMouse ? 0.10 : 0.05)

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

                  Rectangle {
                    id: box
                    width: Style.space(18)
                    height: Style.space(18)
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Style.space(4)
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(Color.bar.text.r, Color.bar.text.g, Color.bar.text.b, 0.6)

                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(6)
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.tickTask(prow.task.id)
                    }
                  }

                  Text {
                    width: parent.width - box.width - rowDue.width - parent.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: (prow.task.hard ? "! " : "") + prow.task.text
                    elide: Text.ElideRight
                    color: Color.bar.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: prow.task.hard
                  }

                  Text {
                    id: rowDue
                    anchors.verticalCenter: parent.verticalCenter
                    visible: prow.task.due != null || prow.task.source !== "typed"
                    text: prow.task.due != null ? Model.formatDue(prow.dueDelta, root.nowMs) : prow.task.source
                    color: prow.overdue ? Kit.Palette.negative : Kit.Palette.faint
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

            Button {
              visible: root.takeover
              text: "I hear you — 10 min"
              foreground: Color.bar.text
              bordered: true
              onClicked: if (root.hostWidget) root.hostWidget.ackHear()
            }
            Button {
              visible: !root.takeover
              text: "Not now"
              foreground: Color.bar.text
              bordered: true
              onClicked: if (root.hostWidget) root.hostWidget.ackDismiss()
            }
            Button {
              visible: !root.takeover
              text: "15 min"
              foreground: Color.bar.text
              bordered: true
              onClicked: if (root.hostWidget) root.hostWidget.ackSnooze(15)
            }
            Button {
              text: root.takeover ? "Snooze 1h" : "1 hour"
              foreground: Color.bar.text
              bordered: true
              onClicked: if (root.hostWidget) root.hostWidget.ackSnooze(60)
            }
          }
        }
      }
    }
  }
}
