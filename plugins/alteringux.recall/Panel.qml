import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// Deck browser + stats for the Recall widget: quick-add a custom card, see
// what's due, and drive the daemon (on/off, pause, check-in now). Every
// control calls the same hostWidget function the IPC path calls.
Panel {
  property QtObject _webPalette: Kit.Palette {}
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
  property bool categoryChipFocused: false
  property bool deleteButtonFocused: false

  function submitQuickAdd() {
    var front = quickFrontInput.text
    var back = quickBackInput.text
    if (!front || !front.trim().length || !back || !back.trim().length) return
    if (hostWidget) hostWidget.addQuiz(front, back, root.quickCategory)
    quickFrontInput.text = ""
    quickBackInput.text = ""
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)
    focusTarget: keyCatcher

    Kit.PanelKeys {
      id: keyCatcher
      sectionNavigation: true
      tabShortcutDescription: "Move to the first or last control; move between controls in control focus"
      anchors.fill: parent
      // PanelKeys leaves native controls' keys to the focused descendant.
      // Only actual editors block the panel/control mode switch.
      blocked: quickFrontInput.activeFocus || quickBackInput.activeFocus
      onCloseRequested: root.close()
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Choose the focused review category", context: "Recall · control focus" }
      ]
      onTabRequested: function(direction) {
        if (direction > 0) quickFrontInput.forceActiveFocus()
        else turnOffButton.forceActiveFocus()
      }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Kit.PanelHead {
          glyph: "󰧑"
          title: "Recall"
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

        // ---- quick add: a custom quiz card ------------------------------
        Rectangle {
          width: parent.width
          height: Style.space(34)
          radius: Style.cornerRadius
          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
          border.width: 1
          border.color: quickFrontInput.activeFocus
            ? _webPalette.barActive
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
            Keys.onEscapePressed: root.close()

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: quickFrontInput.text.length === 0
              text: "Question / front"
              color: _webPalette.barTextColorFor(root.barForeground)
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
            ? _webPalette.barActive
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
            Keys.onEscapePressed: root.close()

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: quickBackInput.text.length === 0
              text: "Answer / back — Enter to save"
              color: _webPalette.barTextColorFor(root.barForeground)
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
              id: categoryChip
              required property string modelData
              width: catLabel.implicitWidth + Style.space(16)
              height: Style.space(30)
              radius: Style.cornerRadius
              focus: false
              activeFocusOnTab: true
              onActiveFocusChanged: root.categoryChipFocused = activeFocus
              Accessible.role: Accessible.Button
              Accessible.name: modelData + (root.quickCategory === modelData ? ", selected" : "")
              Accessible.onPressAction: root.quickCategory = modelData
              color: root.quickCategory === modelData
                ? Qt.rgba(_webPalette.barActive.r, _webPalette.barActive.g, _webPalette.barActive.b, categoryMouse.containsMouse ? 0.34 : 0.25)
                : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, categoryMouse.containsMouse ? 0.14 : 0.06)
              border.width: activeFocus ? 2 : (root.quickCategory === modelData ? 1 : 0)
              border.color: activeFocus || root.quickCategory === modelData ? _webPalette.barActive : "transparent"

              Text {
                id: catLabel
                anchors.centerIn: parent
                text: parent.modelData
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea {
                id: categoryMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.quickCategory = categoryChip.modelData
                  categoryChip.forceActiveFocus()
                }
              }
              Keys.onReturnPressed: root.quickCategory = modelData
              Keys.onSpacePressed: root.quickCategory = modelData
              Keys.onEscapePressed: root.close()
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
                height: Math.max(Style.space(30), Style.spacing.controlHeight)
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

                  MarqueeText {
                    width: Math.max(0, parent.width - dropBtn.width - catLabel2.width - dueBadge.width - parent.spacing * 3)
                    anchors.verticalCenter: parent.verticalCenter
                    text: drow.card.front
                    requestedElide: Text.ElideRight
                    color: root.barForeground
                    textFont.family: Style.font.family
                    textFont.pixelSize: Style.font.bodySmall
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
                    color: _webPalette.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  Kit.ActionButton {
                    id: dropBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.spacing.controlHeight
                    height: Style.spacing.controlHeight
                    text: "×"
                    fontSize: Style.font.bodySmall
                    horizontalPadding: 0
                    verticalPadding: 0
                    foreground: _webPalette.faint
                    focusable: true
                    tooltipText: "Delete card"
                    Accessible.role: Accessible.Button
                    Accessible.name: "Delete due card: " + drow.card.front
                    onActiveFocusChanged: root.deleteButtonFocused = activeFocus
                    Keys.onEscapePressed: root.close()
                    onClicked: if (root.hostWidget) root.hostWidget.dropCard(drow.card.id)
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
          color: _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator {}

        PanelSectionHeader { text: "CONTROLS"; foreground: root.barForeground }

        Flow {
          width: parent.width
          spacing: Style.space(8)

          Kit.ActionButton {
            id: turnOffButton
            text: root.configValue.enabled ? "Turn off" : "Turn on"
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            foreground: root.barForeground
            bordered: true
            onClicked: if (root.hostWidget) root.hostWidget.setEnabled(!root.configValue.enabled)
            Keys.onEscapePressed: root.close()
          }
          Kit.ActionButton {
            id: checkInButton
            text: "Check in now"
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            foreground: root.barForeground
            bordered: true
            enabled: root.configValue.enabled && root.promptKind === ""
            onClicked: if (root.hostWidget) root.hostWidget.forceCheckin()
            Keys.onEscapePressed: root.close()
          }
          Kit.ActionButton {
            id: pauseButton
            text: "Pause 2h"
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            foreground: root.barForeground
            bordered: true
            enabled: root.configValue.enabled
            onClicked: if (root.hostWidget) root.hostWidget.pauseFor(120)
            Keys.onEscapePressed: root.close()
          }
          Kit.ActionButton {
            id: resumeButton
            text: "Resume"
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            foreground: root.barForeground
            bordered: true
            visible: root.nowMs < root.stateValue.pauseUntilMs
            onClicked: if (root.hostWidget) root.hostWidget.resume()
            Keys.onEscapePressed: root.close()
          }
        }
      }
    }
  }
}
