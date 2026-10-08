import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Start/cancel controls for the stopwatch overlay.
Panel {
  property QtObject _webPalette: Kit.Palette {}
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

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(280))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    Kit.PanelKeys {
      anchors.fill: parent
      // While a text field is being edited, let every keystroke (including
      // space, h/j/k/l, x) reach it untouched instead of being intercepted
      // as a panel shortcut.
      blocked: labelField.activeFocus || (intervalField.field && intervalField.field.activeFocus)

      onCloseRequested: root.close()
      onActivateRequested: root.startIfPossible()
      onDeleteRequested: if (hostWidget && hostWidget.active) hostWidget.cancelStopwatch()
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Start the stopwatch", context: "Stopwatch · shortcut focus" },
        { keys: "X", description: "Cancel the active stopwatch", context: "Stopwatch · shortcut focus" }
      ]

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

        // The live readout, promoted to a hero figure (like the countdown
        // cards' days-remaining number, or timers' elapsed line) instead of
        // flat body text — it's the one thing this panel exists to show while
        // a stopwatch is running, and the accent/warning colour repeats the
        // running/paused distinction the badge glyphs already carry.
        Text {
          visible: hostWidget && hostWidget.active
          text: hostWidget ? ((hostWidget.paused ? "Paused: " : "Running: ") + Model.formatElapsed(hostWidget.elapsedSeconds) + (hostWidget.label.length > 0 ? (" — " + hostWidget.label) : "")) : ""
          color: (hostWidget && hostWidget.paused) ? _webPalette.warning : _webPalette.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
          width: content.width
          wrapMode: Text.WordWrap
        }

        // Sound on/off for the running stopwatch. Flips the CLI's marker file
        // via hostWidget.toggleVoice(); speak() re-reads it each interval, so
        // the change applies on the next announcement with no unit restart.
        // Shown in bell mode too now — the mute marker silences the bell as
        // well, for "show me the interval in the bar, don't ring it".
        // These toggles join the panel's F6 control-focus route; the global
        // start/cancel shortcuts only run while the panel key catcher owns focus.
        Toggle {
          id: voiceToggle
          visible: hostWidget && hostWidget.active
          width: content.width
          activeFocusOnTab: true
          label: (hostWidget && hostWidget.chimeMode) ? "Interval bell" : "Voice announcements"
          description: (hostWidget && hostWidget.voiceMuted)
            ? "Muted — the interval still ticks over in the bar, silently"
            : ((hostWidget && hostWidget.chimeMode)
               ? "Ringing a bell every interval"
               : "Speaking the elapsed time every interval")
          checked: !(hostWidget && hostWidget.voiceMuted)
          foreground: root.barForeground
          onClicked: if (hostWidget) hostWidget.toggleVoice()
        }

        // Bell instead of the spoken time. Shown even while idle so it can be
        // set as the default for the next stopwatch (persisted to config); a
        // click while one is running also flips it live via the CLI marker.
        // Turning it on also clears any mute, so the bell is actually audible.
        // Keyboard focusable alongside the voice toggle.
        Toggle {
          id: bellToggle
          width: content.width
          activeFocusOnTab: true
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
          color: _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          width: content.width
          wrapMode: Text.WordWrap
        }

        // "N sessions today, HH:MM total" — an at-a-glance daily total from
        // the same history log the last-session comparison already reads,
        // shown only once idle and once there's something to report.
        Text {
          visible: hostWidget && !hostWidget.active && hostWidget.todaySummary.length > 0
          text: hostWidget ? hostWidget.todaySummary : ""
          color: _webPalette.faint
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

        Flow {
          width: content.width
          spacing: Style.space(8)

          Kit.ActionButton {
            text: "Start"
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            foreground: root.barForeground
            bordered: true
            enabled: !(hostWidget && hostWidget.active)
            onClicked: root.startIfPossible()
          }
          Kit.ActionButton {
            text: (hostWidget && hostWidget.paused) ? "Resume" : "Pause"
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text + " stopwatch"
            foreground: root.barForeground
            bordered: true
            onClicked: {
              if (!hostWidget) return
              if (hostWidget.paused) {
                hostWidget.resumeStopwatch()
                hostWidget.pausedEpoch = 0
              } else {
                hostWidget.pauseStopwatch()
                hostWidget.pausedEpoch = Math.floor(Date.now() / 1000)
              }
            }
          }
          Kit.ActionButton {
            text: "Cancel"
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel stopwatch"
            foreground: root.barForeground
            bordered: true
            enabled: hostWidget && hostWidget.active
            onClicked: if (hostWidget) hostWidget.cancelStopwatch()
          }
        }

        Text {
          width: content.width
          text: "Enter: start  ·  X: cancel  ·  Esc: close"
          color: _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
