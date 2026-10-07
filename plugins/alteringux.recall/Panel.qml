import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Deck browser + stats for the Recall widget: quick-add a custom card, see
// what's due, and drive the daemon (on/off, pause, check-in now). Every
// control calls the same hostWidget function the IPC path calls.
Panel {
  id: root
  moduleName: "alteringux.recall"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var cardsValue: hostWidget ? hostWidget.cardsValue : Model.defaultCards()
  readonly property var stateValue: hostWidget ? hostWidget.stateValue : Model.defaultState()
  readonly property var configValue: hostWidget ? hostWidget.configValue : Model.defaultConfig()
  readonly property string promptKind: hostWidget ? hostWidget.promptKind : ""

  property double nowMs: Date.now()
  Timer { interval: 15000; repeat: true; running: root.opened; onTriggered: root.nowMs = Date.now() }

  readonly property var dueList: Model.topDue(root.cardsValue.cards, root.nowMs, 99)
  readonly property var lessonsQueued: Model.unseenLessons(root.cardsValue.cards)
  readonly property var deckStats: Model.stats(root.cardsValue.cards, root.stateValue)

  readonly property string metaLine: {
    if (!root.configValue.enabled) return "off"
    if (root.nowMs < root.stateValue.pauseUntilMs)
      return "paused " + Model.formatDue(root.stateValue.pauseUntilMs - root.nowMs, root.nowMs).replace("in ", "") + " left"
    var bits = root.dueList.length + " due"
    if (root.lessonsQueued.length > 0) bits += " · " + root.lessonsQueued.length + " lesson" + (root.lessonsQueued.length > 1 ? "s" : "") + " queued"
    if (root.stateValue.streakDays > 0) bits += " · " + root.stateValue.streakDays + "d streak"
    return bits
  }

  property string quickCategory: "custom"

  function submitQuickAdd() {
    var front = quickFrontInput.text
    var back = quickBackInput.text
    if (!front || !front.trim().length || !back || !back.trim().length) return
    if (hostWidget) hostWidget.addQuiz(front, back, root.quickCategory)
    quickFrontInput.text = ""
    quickBackInput.text = ""
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent
      blocked: quickFrontInput.activeFocus || quickBackInput.activeFocus
      onCloseRequested: root.close()

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Kit.PanelHead {
          glyph: "🧠"
          title: "Recall"
          meta: root.metaLine
          foreground: root.barForeground
        }

        // ---- quick add: a custom quiz card ------------------------------
        Rectangle {
          width: parent.width
          height: Style.space(34)
          radius: Style.cornerRadius
          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
          border.width: 1
          border.color: quickFrontInput.activeFocus
            ? Color.bar.active
            : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.2)

          TextInput {
            id: quickFrontInput
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            selectByMouse: true
            onAccepted: quickBackInput.forceActiveFocus()

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: quickFrontInput.text.length === 0
              text: "Question / front"
              color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.4)
              font: quickFrontInput.font
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(34)
          radius: Style.cornerRadius
          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
          border.width: 1
          border.color: quickBackInput.activeFocus
            ? Color.bar.active
            : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.2)

          TextInput {
            id: quickBackInput
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            selectByMouse: true
            onAccepted: root.submitQuickAdd()

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: quickBackInput.text.length === 0
              text: "Answer / back — Enter to save"
              color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.4)
              font: quickBackInput.font
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: ["custom", "trivia", "technique"]

            Rectangle {
              required property string modelData
              width: catLabel.implicitWidth + Style.space(16)
              height: Style.space(22)
              radius: Style.cornerRadius
              color: root.quickCategory === modelData
                ? Qt.rgba(Color.bar.active.r, Color.bar.active.g, Color.bar.active.b, 0.25)
                : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)

              Text {
                id: catLabel
                anchors.centerIn: parent
                text: parent.modelData
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.quickCategory = parent.modelData }
            }
          }
        }

        PanelSeparator {}

        PanelSectionHeader { text: "DUE"; foreground: root.barForeground }

        Kit.EmptyState {
          visible: root.dueList.length === 0
          width: parent.width
          foreground: root.barForeground
          text: "Nothing due."
          hint: root.configValue.enabled ? "Recall will stretch its check-ins while you're caught up." : "Recall is off — turn it on below."
        }

        Kit.PanelScroll {
          width: parent.width
          visible: root.dueList.length > 0
          height: Math.min(Style.space(220), dueColumn.implicitHeight)
          contentHeight: dueColumn.implicitHeight

          Column {
            id: dueColumn
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.dueList

              Rectangle {
                id: drow
                width: dueColumn.width
                height: Style.space(30)
                radius: Style.cornerRadius
                color: rowHover.containsMouse
                  ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
                  : "transparent"

                required property var modelData
                readonly property var card: modelData

                MouseArea { id: rowHover; anchors.fill: parent; hoverEnabled: true }

                Row {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(8)

                  Text {
                    width: drow.width - dropBtn.width - catLabel2.width - dueBadge.width - parent.spacing * 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: drow.card.front
                    elide: Text.ElideRight
                    color: root.barForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  // Feature: each due row now shows how overdue/soon it is,
                  // not just its front text + category — using the fixed
                  // formatDue() (see Model.js) so a card sitting right at an
                  // hour/day boundary reads "1h overdue" rather than "60m
                  // overdue". Kit.MetaText is the kit's dim tracked-caption
                  // "status tag" treatment, so this reads as a tag rather
                  // than a hand-rolled dim Text.
                  Kit.MetaText {
                    id: dueBadge
                    anchors.verticalCenter: parent.verticalCenter
                    width: implicitWidth
                    content: Model.formatDue(drow.card.dueAt - root.nowMs, root.nowMs)
                    foreground: root.barForeground
                  }

                  Text {
                    id: catLabel2
                    anchors.verticalCenter: parent.verticalCenter
                    text: drow.card.category
                    color: Kit.Palette.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    id: dropBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"
                    color: Kit.Palette.faint
                    font.pixelSize: Style.font.bodySmall
                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(6)
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.hostWidget) root.hostWidget.dropCard(drow.card.id)
                    }
                  }
                }
              }
            }
          }
        }

        PanelSeparator {}

        PanelSectionHeader { text: "STATS"; foreground: root.barForeground }

        Text {
          width: parent.width
          text: root.deckStats.lessonsLearned + "/" + root.deckStats.lessonsTotal + " lessons learned · "
            + root.deckStats.reviewedCount + " cards reviewed"
            + (root.deckStats.retentionRate != null ? " · " + Math.round(root.deckStats.retentionRate * 100) + "% retention" : "")
          wrapMode: Text.WordWrap
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator {}

        PanelSectionHeader { text: "CONTROLS"; foreground: root.barForeground }

        Flow {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: root.configValue.enabled ? "Turn off" : "Turn on"
            foreground: root.barForeground
            bordered: true
            onClicked: if (root.hostWidget) root.hostWidget.setEnabled(!root.configValue.enabled)
          }
          Button {
            text: "Check in now"
            foreground: root.barForeground
            bordered: true
            enabled: root.configValue.enabled && root.promptKind === ""
            onClicked: if (root.hostWidget) root.hostWidget.forceCheckin()
          }
          Button {
            text: "Pause 2h"
            foreground: root.barForeground
            bordered: true
            enabled: root.configValue.enabled
            onClicked: if (root.hostWidget) root.hostWidget.pauseFor(120)
          }
          Button {
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
