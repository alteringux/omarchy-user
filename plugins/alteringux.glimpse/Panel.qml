import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// Pool browser + stats for the Glimpse widget: start a drill round, see which
// scheduled scenes are due, and drive the daemon (on/off, pause, check-in,
// fetch). Every control calls the same hostWidget function the IPC path calls.
Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.glimpse"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var cardsValue: hostWidget ? hostWidget.cardsValue : Model.defaultCards()
  readonly property var stateValue: hostWidget ? hostWidget.stateValue : Model.defaultState()
  readonly property var configValue: hostWidget ? hostWidget.configValue : Model.defaultConfig()
  readonly property string promptKind: hostWidget ? hostWidget.promptKind : ""
  readonly property bool roundActive: hostWidget ? hostWidget.roundActive : false

  property double nowMs: Date.now()
  Timer { interval: 15000; repeat: true; running: root.opened; onTriggered: root.nowMs = Date.now() }

  readonly property var dueList: Model.dueCards(root.cardsValue.cards, root.nowMs)
  readonly property var poolStats: Model.stats(root.cardsValue.cards, root.stateValue, root.nowMs)

  readonly property string metaLine: {
    if (!root.configValue.enabled) return "off"
    if (root.nowMs < root.stateValue.pauseUntilMs)
      return "paused " + Model.formatDue(root.stateValue.pauseUntilMs - root.nowMs).replace("in ", "") + " left"
    var bits = root.dueList.length + " due · drill L" + root.poolStats.drillLevel
    if (root.stateValue.streakDays > 0) bits += " · " + root.stateValue.streakDays + "d streak"
    return bits
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    Kit.PanelKeys {
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Kit.PanelHead {
          glyph: "󰈈"
          title: "Glimpse"
          meta: root.metaLine
          foreground: root.barForeground
        }

        // ---- practice ------------------------------------------------------
        PanelSectionHeader { text: "PRACTICE"; foreground: root.barForeground }

        Text {
          width: parent.width
          text: "Study a scene, then click what changed in the altered copy. Drill picks fresh scenes and ramps the difficulty; scheduled scenes resurface on a spacing interval."
          wrapMode: Text.WordWrap
          color: _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Flow {
          width: parent.width
          spacing: Style.space(8)

          Kit.ActionButton {
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            text: "Drill now"
            foreground: root.barForeground
            bordered: true
            enabled: !root.roundActive && root.promptKind === ""
            onClicked: { if (root.hostWidget) root.hostWidget.startDrill(); root.close() }
          }
          Kit.ActionButton {
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            text: "Review a due scene"
            foreground: root.barForeground
            bordered: true
            enabled: !root.roundActive && root.promptKind === "" && root.dueList.length > 0
            onClicked: { if (root.hostWidget) root.hostWidget.startScheduled(""); root.close() }
          }
        }

        PanelSeparator {}

        // ---- due pool ----------------------------------------------------
        PanelSectionHeader { text: "SCHEDULED SCENES"; foreground: root.barForeground }

        Kit.EmptyState {
          visible: root.dueList.length === 0
          width: parent.width
          foreground: root.barForeground
          text: root.cardsValue.cards.length === 0 ? "No scenes in the pool yet." : "Nothing due."
          hint: root.configValue.enabled
            ? "The daemon tops the pool up from Wallhaven while you're caught up."
            : "Glimpse is off — turn it on below to start building the pool."
        }

        Kit.PanelScroll {
          width: parent.width
          visible: root.dueList.length > 0
          height: Math.min(Style.space(200), dueColumn.implicitHeight)
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
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Review scene " + drow.card.sceneId + ", level " + drow.card.level
                Accessible.description: drow.card.changeCount + " changes, "
                  + (drow.card.reps > 0 ? Model.formatPct(drow.card.bestAccuracy) + " best accuracy" : "not reviewed yet")
                Accessible.focusable: true
                Accessible.onPressAction: {
                  if (root.hostWidget && !root.roundActive && root.promptKind === "") {
                    root.hostWidget.startScheduled(drow.card.id)
                    root.close()
                  }
                }
                border.width: activeFocus ? 1 : 0
                border.color: _webPalette.accent
                color: rowHover.containsMouse
                  ? Util.alpha(root.barForeground, 0.06)
                  : "transparent"

                required property var modelData
                readonly property var card: modelData

                MouseArea {
                  id: rowHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    drow.forceActiveFocus()
                    if (root.hostWidget && !root.roundActive && root.promptKind === "") {
                      root.hostWidget.startScheduled(drow.card.id)
                      root.close()
                    }
                  }
                }

                Row {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(8)

                  MarqueeText {
                    width: drow.width - dropBtn.width - metaCol.width - parent.spacing * 3
                    anchors.verticalCenter: parent.verticalCenter
                    text: "scene " + drow.card.sceneId
                    focusableOnOverflow: false
                    requestedElide: Text.ElideRight
                    color: root.barForeground
                    textFont.family: Style.font.family
                    textFont.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    id: metaCol
                    anchors.verticalCenter: parent.verticalCenter
                    text: "L" + drow.card.level + " · " + drow.card.changeCount + "△"
                      + (drow.card.reps > 0 ? " · " + Model.formatPct(drow.card.bestAccuracy) : " · new")
                    color: _webPalette.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  Kit.ActionButton {
                    id: dropBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(24)
                    height: Style.space(24)
                    text: "✕"
                    focusable: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Remove scheduled scene " + drow.card.sceneId
                    foreground: _webPalette.faint
                    bordered: false
                    onClicked: if (root.hostWidget) root.hostWidget.dropCard(drow.card.id)
                  }
                }
              }
            }
          }
        }

        PanelSeparator {}

        // ---- stats -----------------------------------------------------
        PanelSectionHeader { text: "STATS"; foreground: root.barForeground }

        Text {
          width: parent.width
          text: root.poolStats.poolSize + " scenes · " + root.poolStats.reviewedCount + " reviewed · "
            + root.poolStats.lifetimeRounds + " rounds"
            + (root.poolStats.lifetimeAccuracy != null ? " · " + Model.formatPct(root.poolStats.lifetimeAccuracy) + " avg" : "")
            + " · " + root.poolStats.roundsToday + " today"
          wrapMode: Text.WordWrap
          color: _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator {}

        // ---- controls ------------------------------------------------------
        PanelSectionHeader { text: "CONTROLS"; foreground: root.barForeground }

        Flow {
          width: parent.width
          spacing: Style.space(8)

          Kit.ActionButton {
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            text: root.configValue.enabled ? "Turn off" : "Turn on"
            foreground: root.barForeground
            bordered: true
            onClicked: if (root.hostWidget) root.hostWidget.setEnabled(!root.configValue.enabled)
          }
          Kit.ActionButton {
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            text: "Check in now"
            foreground: root.barForeground
            bordered: true
            enabled: root.configValue.enabled && root.promptKind === "" && !root.roundActive
            onClicked: if (root.hostWidget) root.hostWidget.forceCheckin()
          }
          Kit.ActionButton {
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            text: "Fetch scenes"
            foreground: root.barForeground
            bordered: true
            onClicked: if (root.hostWidget) root.hostWidget.fetchScenes(4)
          }
          Kit.ActionButton {
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            text: "Pause 2h"
            foreground: root.barForeground
            bordered: true
            enabled: root.configValue.enabled
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
