import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// Pulse's feed popup: what the alteringux.* plugins have been doing, the ones
// waiting on you pulled to the top with their action, and a single "do this
// next" pick. Every control calls the same hostWidget function so there's one
// implementation shared with the IPC path.
Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.pulse"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var activityValue: hostWidget ? hostWidget.activityValue : Model.defaultActivity()
  readonly property var attentionValue: hostWidget ? hostWidget.attentionValue : Model.defaultAttention()
  readonly property var readValue: hostWidget ? hostWidget.readValue : Model.defaultState()
  readonly property var usageValue: hostWidget ? hostWidget.usageValue : Model.defaultUsage()

  property double nowMs: Date.now()
  Timer { interval: 20000; repeat: true; running: root.opened; onTriggered: root.nowMs = Date.now() }

  readonly property var summary: Model.summary(root.activityValue, root.attentionValue, root.readValue, root.usageValue)
  readonly property var attentionRows: Model.attentionList(root.attentionValue)
  readonly property var events: (root.activityValue.events || []).slice(0, 40)
  readonly property string activityDescription: Model.activityDescription(
    root.activityValue, root.readValue, root.attentionValue, root.events.length)
  readonly property string activityMessageSummary: Model.activityMessageSummary(root.activityValue)
  readonly property double lastReadTs: root.readValue.lastReadTs || 0
  readonly property string metaLine: {
    var bits = []
    if (root.summary.unread > 0) bits.push(root.summary.unread + " new")
    if (root.summary.needAction > 0) bits.push(root.summary.needAction + " need action")
    if (root.summary.usage.summary.stale > 0) bits.push(root.summary.usage.summary.stale + " plugins stale")
    return bits.length ? bits.join(" · ") : "all caught up"
  }

  function toneFor(level) {
    if (level === "critical") return _webPalette.negative
    if (level === "urgent") return _webPalette.urgent
    if (level === "warning" || level === "warn") return _webPalette.warning
    return _webPalette.info
  }

  // toneFor(level) at a given alpha, without every call site re-destructuring
  // .r/.g/.b out of the same color three times over (the "do this next"
  // border below used to call toneFor(...) three times for one color).
  function toneRgba(level, alpha) {
    var c = root.toneFor(level)
    return Qt.rgba(c.r, c.g, c.b, alpha)
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)
    focusTarget: pulseKeys

    Kit.PanelKeys {
      id: pulseKeys
      anchors.fill: parent
      recoveryPilot: true
      recoveryPilotVerified: true
      shortcutSource: root.moduleName
      onCloseRequested: root.close()

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: content.implicitHeight

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Kit.PanelHead {
          glyph: "󰂚"   // nf-md-bell
          title: "Pulse"
          meta: root.metaLine
          foreground: root.barForeground
        }

        Text {
          id: feedbackText
          width: parent.width
          visible: text.length > 0
          text: root.hostWidget && typeof root.hostWidget.actionStatus === "string"
            ? root.hostWidget.actionStatus : ""
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          Accessible.role: Accessible.StaticText
          Accessible.name: text
          Connections {
            target: root.hostWidget
            ignoreUnknownSignals: true
            function onActionFeedback(message) {
              if (root.opened && feedbackText.visible) feedbackText.Accessible.announce(message)
            }
          }
        }

        // ---- do this next -------------------------------------------
        Rectangle {
          width: parent.width
          visible: root.summary.nextAction !== null
          radius: Style.cornerRadius
          color: _webPalette.cardBackgroundFor(root.barForeground)
          border.width: 1
          border.color: root.summary.nextAction
            ? root.toneRgba(root.summary.nextAction.level, 0.5)
            : "transparent"
          implicitHeight: nextRow.implicitHeight + Style.space(16)

          Row {
            id: nextRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(10)

            Column {
              width: Math.max(0, parent.width - (nextBtn.visible ? nextBtn.width + parent.spacing : 0))
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Kit.MetaText {
                width: implicitWidth
                content: "DO THIS NEXT"
                foreground: root.summary.nextAction ? root.toneFor(root.summary.nextAction.level) : _webPalette.faint
              }
              MarqueeText {
                width: parent.width
                text: root.summary.nextAction
                  ? (root.summary.nextAction.plugin.replace(/^alteringux\./, "") + " — " + root.summary.nextAction.label)
                  : ""
                requestedElide: Text.ElideRight
                color: root.barForeground
                textFont.family: Style.font.family
                textFont.pixelSize: Style.font.body
              }
            }

            Kit.ActionButton {
              id: nextBtn
              anchors.verticalCenter: parent.verticalCenter
              visible: root.summary.nextAction && root.summary.nextAction.action.length > 0
              text: root.summary.nextAction ? root.summary.nextAction.actionLabel : ""
              focusable: true
              Accessible.name: text
              foreground: root.barForeground
              bordered: true
              onClicked: if (root.hostWidget) root.hostWidget.runNextAction()
            }
          }
        }

        // ---- needs action -----------------------------------------
        PanelSeparator { visible: root.attentionRows.length > 0 }
        PanelSectionHeader {
          visible: root.attentionRows.length > 0
          text: "NEEDS ACTION"
          foreground: root.barForeground
        }

        Column {
          width: parent.width
          visible: root.attentionRows.length > 0
          spacing: Style.space(6)

          Repeater {
            model: root.attentionRows

            Rectangle {
              id: attDel
              width: parent.width
              required property var modelData
              readonly property var item: modelData
              implicitHeight: attRow.implicitHeight + Style.space(14)
              radius: Style.cornerRadius
              color: _webPalette.cardBackgroundFor(root.barForeground)
              border.width: 1
              border.color: _webPalette.cardBorderFor(root.barForeground)

              Rectangle {
                width: Style.space(3)
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                radius: width / 2
                color: root.toneFor(attDel.item.level)
                opacity: 0.9
              }

              Row {
                id: attRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Column {
                  width: Math.max(0, parent.width - (attActBtn.visible ? attActBtn.width + parent.spacing : 0)
                    - attDismiss.width - parent.spacing)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    text: attDel.item.plugin.replace(/^alteringux\./, "").toUpperCase()
                    color: root.toneFor(attDel.item.level)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.0
                  }
                  Text {
                    width: parent.width
                    text: attDel.item.label
                    wrapMode: Text.WordWrap
                    color: root.barForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Kit.ActionButton {
                  id: attActBtn
                  anchors.verticalCenter: parent.verticalCenter
                  visible: attDel.item.action.length > 0
                  text: attDel.item.actionLabel.length ? attDel.item.actionLabel : "Do it"
                  focusable: true
                  Accessible.name: text + " for " + attDel.item.plugin.replace(/^alteringux\./, "")
                  foreground: root.barForeground
                  bordered: true
                  onClicked: if (root.hostWidget) root.hostWidget.actOn(attDel.item.plugin)
                }

                Kit.ActionButton {
                  id: attDismiss
                  anchors.verticalCenter: parent.verticalCenter
                  text: "✕"
                  focusable: true
                  Accessible.name: "Dismiss alert for " + attDel.item.plugin.replace(/^alteringux\./, "")
                  foreground: _webPalette.faint
                  bordered: false
                  onClicked: if (root.hostWidget) root.hostWidget.clearOne(attDel.item.plugin)
                }
              }
            }
          }
        }

        // ---- plugin usage -----------------------------------------
        PanelSeparator { visible: root.summary.usage.plugins.length > 0 }
        PanelSectionHeader {
          visible: root.summary.usage.plugins.length > 0
          text: "PLUGIN USAGE"
          foreground: root.barForeground
        }
        Text {
          width: parent.width
          visible: root.summary.usage.plugins.length > 0
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          text: {
            var most = root.summary.mostUsed.slice(0, 3).map(function (p) {
              return p.id.replace(/^alteringux\./, "") + " " + p.uses
            }).join(" · ")
            var least = root.summary.leastUsed.slice(0, 3).map(function (p) {
              return p.id.replace(/^alteringux\./, "") + " " + (p.neverUsed ? "never" : p.uses)
            }).join(" · ")
            var stale = root.summary.stalePlugins.map(function (p) {
              return p.id.replace(/^alteringux\./, "") + " (" +
                (p.neverUsed ? "never used" : Math.floor(p.daysIdle) + "d idle") + ")"
            }).join(" · ")
            var line = "Most: " + (most || "—") + "   Least: " + (least || "—")
            return stale ? line + "\nStale: " + stale : line
          }
        }

        // ---- activity feed ---------------------------------------
        PanelSeparator {}
        PanelSectionHeader { text: "ACTIVITY"; foreground: root.barForeground }

        Text {
          objectName: "pulse-activity-summary"
          width: parent.width
          visible: root.activityDescription.length > 0
          text: root.activityDescription
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          Accessible.role: Accessible.StaticText
          Accessible.name: text
        }

        MarqueeText {
          objectName: "pulse-activity-message-summary"
          visible: root.activityMessageSummary.length > 0
          width: parent.width
          text: "Highlights: " + root.activityMessageSummary
          requestedTextFormat: Text.PlainText
          textFont.family: Style.font.family
          textFont.pixelSize: Style.font.bodySmall
          color: _webPalette.faint
        }

        Kit.EmptyState {
          visible: root.events.length === 0
          width: parent.width
          foreground: root.barForeground
          text: "No activity yet."
          hint: "Plugins report here with:  omarchy-pulse log <plugin> \"…\""
        }

        Column {
          id: feedColumn
          width: parent.width
          visible: root.events.length > 0
          spacing: Style.space(6)

          Repeater {
            model: root.events

            ActivityRow {
              width: feedColumn.width
              nowMs: root.nowMs
              lastReadTs: root.lastReadTs
              barForeground: root.barForeground
              faintForeground: _webPalette.faint
              unreadColor: root.toneFor(modelData.level)
              onOpenRequested: action => {
                if (root.hostWidget) root.hostWidget.runAction(action)
              }
            }
          }
        }

        // ---- footer ---------------------------------------------
        PanelSeparator {}
        Flow {
          width: parent.width
          spacing: Style.space(8)

          Kit.ActionButton {
            text: "Mark all read"
            focusable: true
            Accessible.name: text
            foreground: root.barForeground
            bordered: true
            enabled: root.summary.unread > 0
            onClicked: if (root.hostWidget) root.hostWidget.markRead()
          }
          Kit.ActionButton {
            text: "Clear alerts"
            focusable: true
            Accessible.name: text
            foreground: root.barForeground
            bordered: true
            enabled: root.summary.needAction > 0
            onClicked: if (root.hostWidget) root.hostWidget.clearAll()
          }
        }
      }
      }
    }
  }
}
