import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Start/cancel controls for the stopwatch overlay.
Panel {
  id: root
  moduleName: "alteringux.stopwatch"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  // Seeds from the persisted last-used interval once hostWidget is injected;
  // a user edit below breaks this binding and pins their choice for the session.
  property int intervalValue: hostWidget ? hostWidget.lastInterval : 5
  property string labelValue: ""

  readonly property var guard: Kit.BugGuard.create("alteringux.stopwatch", function(argv) { Quickshell.execDetached(argv) })

  // Shared by the label field's Enter key, the panel-level Enter/Space
  // shortcut, and the Start button, so there's exactly one "start" path.
  function startIfPossible() {
    guard.run("startIfPossible", function() {
      if (!hostWidget || hostWidget.active) return
      hostWidget.startStopwatch(root.intervalValue, root.labelValue)
      root.close()
    })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(280))
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

        Kit.PanelHead {
          glyph: "\uf2f2"   // nf-fa-stopwatch, matches the bar widget
          title: "Stopwatch"
          meta: {
            if (!(hostWidget && hostWidget.active)) return "Ready"
            return hostWidget.paused ? "Paused" : "Running"
          }
          foreground: root.barForeground
        }

        Text {
          visible: hostWidget && hostWidget.active
          text: hostWidget ? ((hostWidget.paused ? "Paused: " : "Running: ") + Model.formatElapsed(hostWidget.elapsedSeconds) + (hostWidget.label.length > 0 ? (" — " + hostWidget.label) : "")) : ""
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          width: content.width
          wrapMode: Text.WordWrap
        }

        // Voice on/off for the running stopwatch. Flips the CLI's marker file
        // via hostWidget.toggleVoice(); speak() re-reads it each interval, so
        // the change applies on the next announcement with no unit restart.
        // Hidden while the bell is on — the bell rings regardless of this, so
        // showing a "Muted" switch there would just be a contradiction.
        // Mouse-only (activeFocusOnTab off) to stay out of the panel's
        // Enter=start / X=cancel / Esc=close keyboard model.
        Toggle {
          id: voiceToggle
          visible: hostWidget && hostWidget.active && !hostWidget.chimeMode
          width: content.width
          activeFocusOnTab: false
          label: "Voice announcements"
          description: (hostWidget && hostWidget.voiceMuted)
            ? "Muted — silent until you switch this back on"
            : "Speaking the elapsed time every interval"
          checked: !(hostWidget && hostWidget.voiceMuted)
          foreground: root.barForeground
          onClicked: if (hostWidget) hostWidget.toggleVoice()
        }

        // Bell instead of the spoken time. Shown even while idle so it can be
        // set as the default for the next stopwatch (persisted to config); a
        // click while one is running also flips it live via the CLI marker.
        // Turning it on also clears any mute, so the bell is actually audible.
        // Mouse-only, same as the voice toggle.
        Toggle {
          id: bellToggle
          width: content.width
          activeFocusOnTab: false
          label: "Ring a bell"
          readonly property bool chOn: hostWidget
            ? (hostWidget.active ? hostWidget.chimeMode : hostWidget.chimeDefault)
            : false
          description: chOn
            ? "A bell at each interval, instead of speaking the time"
            : "Speak the elapsed time at each interval"
          checked: chOn
          foreground: root.barForeground
          onClicked: {
            if (!hostWidget) return
            var v = !chOn
            hostWidget.rememberChimeDefault(v)
            if (hostWidget.active) {
              hostWidget.setChimeMode(v)
              if (v && hostWidget.voiceMuted) hostWidget.setVoiceMuted(false)
            }
          }
        }

        Text {
          visible: hostWidget && !hostWidget.active && hostWidget.lastSessionSummary.length > 0
          text: hostWidget ? ("Last session: " + hostWidget.lastSessionSummary) : ""
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
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
            onModified: function(v) {
              root.intervalValue = v
              if (hostWidget) hostWidget.rememberInterval(v)
            }
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
            text: (hostWidget && hostWidget.paused) ? "Resume" : "Pause"
            foreground: root.barForeground
            bordered: true
            enabled: hostWidget && hostWidget.active
            onClicked: {
              if (!hostWidget) return
              if (hostWidget.paused) hostWidget.resumeStopwatch()
              else hostWidget.pauseStopwatch()
            }
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
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
