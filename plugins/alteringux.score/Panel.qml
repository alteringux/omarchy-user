import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

Panel {
  property QtObject _webPalette: Kit.Palette {}
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

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    Kit.PanelKeys {
      id: keyCatcher
      anchors.fill: parent
      sectionNavigation: true
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(16)

        Kit.PanelHead {
          title: "Score"
          foreground: _webPalette.barTextColorFor(root.bar.foreground)
        }

        // Score display
        Row {
          id: scoreRow
          width: parent.width
          spacing: Style.space(12)

          Text {
            id: scoreIcon
            text: root.config.icon || ""
            color: _webPalette.barTextColorFor(root.bar.foreground)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.fontPx(4)
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            width: Math.max(0, scoreRow.width - scoreIcon.implicitWidth - scoreRow.spacing)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            MarqueeText {
              width: parent.width
              text: String(root.score)
              requestedElide: Text.ElideRight
              color: _webPalette.barTextColorFor(root.bar.foreground)
              textFont.family: root.bar.fontFamily
              textFont.pixelSize: Style.font.display
              textFont.bold: true
              Accessible.role: Accessible.StaticText
              Accessible.name: text
            }
          }
        }

        Text {
          width: parent.width
          text: "F6: controls/shortcuts  ·  Esc: close"
            + "\nTab/Shift+Tab: panels in shortcut focus; controls in control focus"
          textFormat: Text.PlainText
          color: _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
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

            delegate: Kit.ActionButton {
              required property var modelData
              width: (parent.width - Style.space(24)) / 4
              height: Style.space(36)
              Accessible.name: modelData.key === "dec" ? "Decrease score by " + (root.config.step || 1)
                : modelData.key === "inc" ? "Increase score by " + (root.config.step || 1)
                : modelData.key === "undo" ? "Undo last score change" : "Reset score"
              Accessible.description: modelData.enabled ? "" : "Unavailable: there is no score change to undo"
              enabled: modelData.enabled
              focusable: true
              opacity: modelData.enabled ? 1.0 : 0.4
              text: modelData.label
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.body
              foreground: _webPalette.barTextColorFor(root.bar.foreground)
              background: Util.alpha(_webPalette.barTextColorFor(root.bar.foreground), 0.1)

              function activate() {
                if (!modelData.enabled || !root.hostWidget) return
                if (modelData.key === "dec") root.hostWidget.decrement()
                else if (modelData.key === "undo") root.hostWidget.undo()
                else if (modelData.key === "reset") root.hostWidget.resetScore()
                else root.hostWidget.increment()
              }

              onClicked: activate()
            }
          }
        }

        // Divider
        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: _webPalette.barTextColorFor(root.bar.foreground)
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
              foreground: _webPalette.barTextColorFor(root.bar.foreground)
            }

            // Small same-day tally, purely derived from the history array
            // already on hand — no extra persistence.
            Text {
              readonly property int todayCount: Model.countToday(root.history)
              visible: todayCount > 0
              text: todayCount + " today"
              color: _webPalette.faint
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
                color: modelData.action === "increment" ? _webPalette.positive
                  : modelData.action === "decrement" ? _webPalette.negative
                  : _webPalette.warning
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                Layout.preferredWidth: Style.space(40)
              }

              Text {
                text: modelData.action === "reset"
                  ? String(modelData.from) + " → " + String(modelData.to)
                  : String(modelData.action)
                color: _webPalette.faint
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
                color: _webPalette.faint
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Kit.EmptyState {
            visible: root.history.length === 0
            text: "No history yet"
            hint: "Use the + / \u2212 buttons or scroll the bar widget."
            foreground: _webPalette.barTextColorFor(root.bar.foreground)
          }
        }
      }
    }
  }
}
