import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Start/cancel controls for the stopwatch overlay.
Panel {
  id: root
  moduleName: "alteringux.stopwatch"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  property int intervalValue: 5
  property string labelValue: ""

  // Shared by the label field's Enter key, the panel-level Enter/Space
  // shortcut, and the Start button, so there's exactly one "start" path.
  function startIfPossible() {
    if (!hostWidget || hostWidget.active) return
    hostWidget.startStopwatch(root.intervalValue, root.labelValue)
    root.close()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(260))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent
      // While a text field is being edited, let every keystroke (including
      // space, h/j/k/l, x) reach it untouched instead of being intercepted
      // as a panel shortcut.
      blocked: labelField.activeFocus || (intervalField.field && intervalField.field.activeFocus)

      onCloseRequested: root.close()
      onActivateRequested: root.startIfPossible()
      onDeleteRequested: if (hostWidget && hostWidget.active) hostWidget.cancelStopwatch()

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelSectionHeader {
          text: "STOPWATCH"
          foreground: root.barForeground
        }

        Text {
          visible: hostWidget && hostWidget.active
          text: hostWidget ? ("Running: " + Model.formatElapsed(hostWidget.elapsedSeconds) + (hostWidget.label.length > 0 ? (" — " + hostWidget.label) : "")) : ""
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          width: content.width
          wrapMode: Text.WordWrap
        }

        Text {
          visible: hostWidget && !hostWidget.active && hostWidget.lastSessionSummary.length > 0
          text: hostWidget ? ("Last session: " + hostWidget.lastSessionSummary) : ""
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          width: content.width
          wrapMode: Text.WordWrap
        }

        Row {
          spacing: Style.space(14)

          NumberField {
            id: intervalField
            label: "Announce every (min)"
            value: root.intervalValue
            from: 1
            to: 60
            foreground: root.barForeground
            onModified: function(v) { root.intervalValue = v }
          }
        }

        Row {
          width: content.width
          spacing: Style.space(8)

          TextField {
            id: labelField
            width: parent.width
            text: root.labelValue
            placeholderText: "Label (optional)"
            foreground: root.barForeground
            onEditingFinished: root.labelValue = text
            // Enter submits, like pressing OK.
            onAccepted: {
              root.labelValue = text
              root.startIfPossible()
            }
          }
        }

        PanelSeparator {}

        Row {
          spacing: Style.space(8)

          Button {
            text: "Start"
            foreground: root.barForeground
            bordered: true
            enabled: !(hostWidget && hostWidget.active)
            onClicked: root.startIfPossible()
          }
          Button {
            text: "Cancel"
            foreground: root.barForeground
            bordered: true
            enabled: hostWidget && hostWidget.active
            onClicked: if (hostWidget) hostWidget.cancelStopwatch()
          }
        }

        Text {
          text: "Enter: start  ·  X: cancel  ·  Esc: close"
          color: Qt.darker(root.barForeground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
