import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

Panel {
  id: root
  moduleName: "alteringux.score"
  ipcTarget: "alteringux.score"
  manageIpc: false

  readonly property var guard: Kit.BugGuard.create("alteringux.score", function(argv) { Quickshell.execDetached(argv) })

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Bind straight to the host widget's watched stores (docs/adr/0006): when
  // omarchy-score rewrites score-state.json the watch re-read updates
  // hostWidget.state and these re-evaluate — no copy-on-click sync.
  readonly property var config: root.hostWidget ? root.hostWidget.config : ({})
  readonly property int score: (root.hostWidget && root.hostWidget.state) ? (root.hostWidget.state.score || 0) : 0
  readonly property var history: (root.hostWidget && root.hostWidget.state) ? (root.hostWidget.state.history || []) : []

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(16)

        // Score display
        Row {
          width: parent.width
          spacing: Style.space(12)

          Text {
            text: root.config.icon || ""
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.fontPx(4)
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Kit.MetaText {
              width: implicitWidth   // parent Column is shrink-wrapped, not width-bound
              content: "Score"
              foreground: root.bar.foreground
            }
            Text {
              text: String(root.score)
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }
          }
        }

        // Controls -- minus / undo / reset / plus
        Row {
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: [
              { key: "dec",   label: "\u2212 " + (root.config.step || 1), enabled: true },
              { key: "undo",  label: "Undo",                             enabled: !!(root.hostWidget && root.hostWidget.canUndo) },
              { key: "reset", label: "Reset",                            enabled: true },
              { key: "inc",   label: "+ " + (root.config.step || 1),     enabled: true }
            ]

            delegate: Rectangle {
              required property var modelData
              width: (parent.width - Style.space(24)) / 4
              height: Style.space(36)
              radius: Style.cornerRadius
              opacity: modelData.enabled ? 1.0 : 0.4
              color: (btnArea.containsMouse && modelData.enabled)
                ? Style.hoverFillFor(root.bar.foreground, Color.accent)
                : Util.alpha(root.bar.foreground, 0.1)

              Text {
                anchors.centerIn: parent
                text: modelData.label
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: btnArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: modelData.enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.hostWidget) {
                    if (modelData.key === "dec") root.hostWidget.decrement()
                    else if (modelData.key === "undo") root.hostWidget.undo()
                    else if (modelData.key === "reset") root.hostWidget.resetScore()
                    else root.hostWidget.increment()
                  }
                }
              }
            }
          }
        }

        // Divider
        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: root.bar.foreground
          opacity: 0.12
        }

        // History
        Column {
          width: parent.width
          spacing: Style.space(8)

          Row {
            width: parent.width
            spacing: Style.space(6)

            Kit.MetaText {
              // Override MetaText's own default (width: parent.width) — that
              // default assumes it's the sole child of a width-anchored
              // container; here it shares a Row with the "N today" tally, so
              // it must size to its own text instead of claiming the whole
              // row and pushing the tally off past the edge.
              width: implicitWidth
              content: "History"
              foreground: root.bar.foreground
            }

            // Small same-day tally, purely derived from the history array
            // already on hand — no extra persistence.
            Text {
              readonly property int todayCount: Model.countToday(root.history)
              visible: todayCount > 0
              text: todayCount + " today"
              color: Kit.Palette.faint
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Repeater {
            model: root.history.slice(-10).reverse()

            RowLayout {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: modelData.action === "increment" ? "+" + modelData.value
                  : modelData.action === "decrement" ? "−" + modelData.value
                  : "-reset"
                color: modelData.action === "increment" ? Kit.Palette.positive
                  : modelData.action === "decrement" ? Kit.Palette.negative
                  : Kit.Palette.warning
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                Layout.preferredWidth: Style.space(40)
              }

              Text {
                text: modelData.action === "reset"
                  ? String(modelData.from) + " → " + String(modelData.to)
                  : String(modelData.action)
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              // Fills the remaining width so the timestamp pins to the right
              // edge. The previous `Item { width: parent.width - x }` filled
              // all the way to the row's right edge on its own, then the
              // timestamp Text was appended AFTER it — pushing the timestamp
              // past the visible row and off the panel entirely. Layout.fillWidth
              // on a genuine RowLayout spacer is the pattern already used
              // elsewhere in these plugins (dashboard, stocks, flow) for
              // exactly this "pin trailing content right" case.
              Item { Layout.fillWidth: true }

              Text {
                text: {
                  var d = new Date(modelData.timestamp)
                  return Qt.formatTime(d, "HH:mm")
                }
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Kit.EmptyState {
            visible: root.history.length === 0
            text: "No history yet"
            hint: "Use the + / \u2212 buttons or scroll the bar widget."
            foreground: root.bar.foreground
          }
        }
      }
    }
  }
}
