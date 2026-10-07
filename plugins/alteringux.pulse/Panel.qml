import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Pulse's feed popup: what the alteringux.* plugins have been doing, the ones
// waiting on you pulled to the top with their action, and a single "do this
// next" pick. Every control calls the same hostWidget function so there's one
// implementation shared with the IPC path.
Panel {
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
  readonly property double lastReadTs: root.readValue.lastReadTs || 0
  readonly property string metaLine: {
    var bits = []
    if (root.summary.unread > 0) bits.push(root.summary.unread + " new")
    if (root.summary.needAction > 0) bits.push(root.summary.needAction + " need action")
    if (root.summary.usage.summary.stale > 0) bits.push(root.summary.usage.summary.stale + " plugins stale")
    return bits.length ? bits.join(" · ") : "all caught up"
  }

  function toneFor(level) {
    if (level === "critical") return Kit.Palette.negative
    if (level === "urgent") return Kit.Palette.urgent
    if (level === "warning") return Kit.Palette.warning
    return Kit.Palette.info
  }

  // toneFor(level) at a given alpha, without every call site re-destructuring
  // .r/.g/.b out of the same color three times over (the "do this next"
  // border below used to call toneFor(...) three times for one color).
  function toneRgba(level, alpha) {
    var c = root.toneFor(level)
    return Qt.rgba(c.r, c.g, c.b, alpha)
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
      onCloseRequested: root.close()

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

        // ---- do this next -------------------------------------------
        Rectangle {
          width: parent.width
          visible: root.summary.nextAction !== null
          radius: Style.cornerRadius
          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
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
              width: parent.width - nextBtn.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Kit.MetaText {
                width: implicitWidth
                content: "DO THIS NEXT"
                foreground: root.summary.nextAction ? root.toneFor(root.summary.nextAction.level) : Kit.Palette.faint
              }
              Text {
                width: parent.width
                text: root.summary.nextAction
                  ? (root.summary.nextAction.plugin.replace(/^alteringux\./, "") + " — " + root.summary.nextAction.label)
                  : ""
                elide: Text.ElideRight
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            Button {
              id: nextBtn
              anchors.verticalCenter: parent.verticalCenter
              visible: root.summary.nextAction && root.summary.nextAction.action.length > 0
              text: root.summary.nextAction ? root.summary.nextAction.actionLabel : ""
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
              color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.05)

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
                  width: parent.width - attActBtn.width - attDismiss.width - parent.spacing * 2
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

                Button {
                  id: attActBtn
                  anchors.verticalCenter: parent.verticalCenter
                  visible: attDel.item.action.length > 0
                  text: attDel.item.actionLabel.length ? attDel.item.actionLabel : "Do it"
                  foreground: root.barForeground
                  bordered: true
                  onClicked: if (root.hostWidget) root.hostWidget.actOn(attDel.item.plugin)
                }

                Button {
                  id: attDismiss
                  anchors.verticalCenter: parent.verticalCenter
                  text: "✕"
                  foreground: Kit.Palette.faint
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

        Kit.EmptyState {
          visible: root.events.length === 0
          width: parent.width
          foreground: root.barForeground
          text: "No activity yet."
          hint: "Plugins report here with:  omarchy-pulse log <plugin> \"…\""
        }

        Kit.PanelScroll {
          width: parent.width
          visible: root.events.length > 0
          height: Math.min(Style.space(260), feedColumn.implicitHeight)
          contentHeight: feedColumn.implicitHeight

          Column {
            id: feedColumn
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.events

              Rectangle {
                id: evDel
                width: feedColumn.width
                required property var modelData
                readonly property var ev: modelData
                readonly property bool unread: ev.ts > root.lastReadTs
                implicitHeight: evRow.implicitHeight + Style.space(10)
                radius: Style.cornerRadius
                color: evHover.containsMouse
                  ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
                  : "transparent"

                MouseArea { id: evHover; anchors.fill: parent; hoverEnabled: true }

                Rectangle {
                  width: Style.space(5); height: width; radius: width / 2
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(3)
                  anchors.verticalCenter: parent.verticalCenter
                  visible: evDel.unread
                  color: root.toneFor(evDel.ev.level)
                }

                Row {
                  id: evRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(14)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(8)

                  Text {
                    width: Style.space(64)
                    anchors.verticalCenter: parent.verticalCenter
                    text: evDel.ev.plugin.replace(/^alteringux\./, "")
                    elide: Text.ElideRight
                    color: Kit.Palette.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    // evOpen only shows on hover, and a Row skips an
                    // invisible child's gap along with the child itself --
                    // unconditionally subtracting its width AND a flat 3
                    // gaps' worth of spacing (right for the 4-child hovered
                    // case) starved this label by one phantom button-width
                    // and one phantom gap for the far more common unhovered,
                    // 3-child case, eliding messages more than it needed to.
                    width: evRow.width - Style.space(64) - timeLabel.width
                      - (evOpen.visible ? evOpen.width + parent.spacing : 0)
                      - parent.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: evDel.ev.message
                    elide: Text.ElideRight
                    color: root.barForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: evDel.unread
                  }

                  Text {
                    id: timeLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.relTime(root.nowMs - evDel.ev.ts)
                    color: Kit.Palette.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Button {
                    id: evOpen
                    anchors.verticalCenter: parent.verticalCenter
                    visible: evDel.ev.action.length > 0 && evHover.containsMouse
                    text: evDel.ev.actionLabel.length ? evDel.ev.actionLabel : "Open"
                    foreground: root.barForeground
                    bordered: true
                    onClicked: if (root.hostWidget) root.hostWidget.runAction(evDel.ev.action)
                  }
                }
              }
            }
          }
        }

        // ---- footer ---------------------------------------------
        PanelSeparator {}
        Flow {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: "Mark all read"
            foreground: root.barForeground
            bordered: true
            enabled: root.summary.unread > 0
            onClicked: if (root.hostWidget) root.hostWidget.markRead()
          }
          Button {
            text: "Clear alerts"
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
