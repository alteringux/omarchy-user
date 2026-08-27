import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Start/cancel controls for the countdown overlay.
Panel {
  id: root
  moduleName: "alteringux.countdown"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  property string modeValue: Model.MODE_MINUTES  // Model.MODE_MINUTES | Model.MODE_SECONDS (Quick)
  property int minutesValue: 5
  property int secondsValue: 10
  property string labelValue: ""
  property bool loopValue: false

  readonly property int durationValue: modeValue === Model.MODE_SECONDS ? secondsValue : minutesValue
  readonly property bool canStart: Model.canStart(root.durationValue)

  // Shared by the label field's Enter key, the panel-level Enter/Space
  // shortcut, and the Start button, so there's exactly one "start" path.
  function startIfPossible() {
    if (!hostWidget || hostWidget.active || !root.canStart) return
    hostWidget.startCountdown(root.modeValue, root.durationValue, root.labelValue, root.loopValue)
    root.close()
  }

  // ---- Self-improving presets: ranks past countdowns by usage frequency
  // (see omarchy-countdown-log + Model.rankPresets) so the most-used
  // durations/labels surface as one-tap chips, and rarely-used ones fall
  // out of the ranking on their own as newer usage accumulates.
  readonly property string home: Quickshell.env("HOME")
  readonly property string historyPath: home + "/.local/state/omarchy/countdown-history.json"
  property var presets: []

  function applyHistory(raw) {
    try {
      var parsed = raw && raw.length > 0 ? JSON.parse(raw) : []
      root.presets = Model.rankPresets(parsed, 4)
    } catch (e) {
      root.presets = []
    }
  }

  function applyPreset(p) {
    root.modeValue = p.mode
    if (p.mode === Model.MODE_SECONDS) root.secondsValue = p.duration
    else root.minutesValue = p.duration
    root.labelValue = p.label
    root.startIfPossible()
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyHistory(text())
    onLoadFailed: root.presets = []
    onFileChanged: reload()
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
      blocked: labelField.activeFocus || (minutesField.field && minutesField.field.activeFocus)

      onCloseRequested: root.close()
      onActivateRequested: root.startIfPossible()
      onDeleteRequested: if (hostWidget && hostWidget.active) hostWidget.cancelCountdown()

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelSectionHeader {
          text: "COUNTDOWN"
          foreground: root.barForeground
        }

        Text {
          visible: hostWidget && hostWidget.active
          text: hostWidget ? ("Running: " + Model.formatRemaining(hostWidget.remainingSeconds) + (hostWidget.label.length > 0 ? (" — " + hostWidget.label) : "")) : ""
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          width: content.width
          wrapMode: Text.WordWrap
        }

        Row {
          spacing: Style.space(8)
          visible: root.presets.length > 0 && !(hostWidget && hostWidget.active)

          Repeater {
            model: root.presets
            delegate: Button {
              text: (modelData.mode === Model.MODE_SECONDS ? modelData.duration + "s" : modelData.duration + "m")
                    + (modelData.label.length > 0 ? (" " + modelData.label) : "")
              foreground: root.barForeground
              bordered: true
              onClicked: root.applyPreset(modelData)
            }
          }
        }

        ButtonGroup {
          options: [
            { value: Model.MODE_MINUTES, label: "Minutes" },
            { value: Model.MODE_SECONDS, label: "Quick" }
          ]
          value: root.modeValue
          foreground: root.barForeground
          onChanged: function(v) { root.modeValue = v }
        }

        Row {
          spacing: Style.space(14)
          visible: root.modeValue === Model.MODE_MINUTES

          NumberField {
            id: minutesField
            label: "Minutes"
            value: root.minutesValue
            from: 1
            to: 180
            foreground: root.barForeground
            onModified: function(v) { root.minutesValue = v }
          }
        }

        Column {
          width: content.width
          spacing: Style.space(6)
          visible: root.modeValue === Model.MODE_SECONDS

          Text {
            text: "Quick countdown: " + root.secondsValue + "s"
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          PanelSlider {
            width: parent.width
            minimum: 0
            maximum: 10
            step: 1
            integer: true
            value: root.secondsValue
            onMoved: function(v) { root.secondsValue = v }
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

        Toggle {
          width: content.width
          label: "Loop"
          description: "Restart automatically until cancelled."
          foreground: root.barForeground
          checked: root.loopValue
          onClicked: root.loopValue = !root.loopValue
        }

        PanelSeparator {}

        Row {
          spacing: Style.space(8)

          Button {
            text: "Start"
            foreground: root.barForeground
            bordered: true
            enabled: !(hostWidget && hostWidget.active) && root.canStart
            onClicked: root.startIfPossible()
          }
          Button {
            text: "Cancel"
            foreground: root.barForeground
            bordered: true
            enabled: hostWidget && hostWidget.active
            onClicked: if (hostWidget) hostWidget.cancelCountdown()
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
