import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// Transport panel for the currently-speaking Piper TTS job. Everything here
// acts on hostWidget (the BarWidget), which owns the state and the calls out
// to tts-player-ctl / piper-tts.
Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.ttsplayer"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  // Local mirror of the host's effective voice. Dropdown writes its own
  // `value` on select (which severs a plain binding), so we keep a writable
  // copy here and re-sync it from the host whenever the host's value moves.
  property string voiceSelection: hostWidget ? hostWidget.effectiveVoice : ""

  Connections {
    target: root.hostWidget
    ignoreUnknownSignals: true
    function onEffectiveVoiceChanged() {
      if (root.hostWidget) root.voiceSelection = root.hostWidget.effectiveVoice
    }
  }

  readonly property bool speaking: hostWidget && hostWidget.active
  readonly property var speeds: [1, 1.25, 1.5, 2]

  readonly property var guard: Kit.BugGuard.create("alteringux.ttsplayer", function (argv) { Quickshell.execDetached(argv) })

  readonly property real progress: {
    if (!hostWidget) return 0
    return Model.progressFraction({
      chunks: hostWidget.state ? hostWidget.state.chunks : 1,
      played: hostWidget.playedIndex,
      elapsed: hostWidget.elapsedSeconds,
      chars: hostWidget.state ? hostWidget.state.chars : 0
    })
  }

  readonly property string chunkText: {
    if (!hostWidget || !hostWidget.state) return ""
    return Model.chunkLabel({ chunks: hostWidget.state.chunks, played: hostWidget.playedIndex })
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

      // While the Voice dropdown's popup owns the keyboard, stop this catcher
      // from eating j/k/Enter/Esc before the list can use them.
      blocked: voiceDropdown.popupOpen

      onCloseRequested: root.close()
      onActivateRequested: if (root.speaking && hostWidget) hostWidget.togglePause()
      onDeleteRequested: if (root.speaking && hostWidget) hostWidget.stopPlayback()
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Pause or resume current speech", context: "TTS Player · shortcut focus" },
        { keys: "X", description: "Stop current speech", context: "TTS Player · shortcut focus" }
      ]

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Kit.PanelHead {
          glyph: hostWidget ? hostWidget.icon : ""   // nf-fa-bullhorn / pause / volume-off, live from the bar widget
          title: "Text to Speech"
          meta: !root.speaking ? "Idle" : (hostWidget.paused ? "Paused" : "Speaking")
          foreground: root.barForeground
        }

        MarqueeText {
          visible: root.speaking
          width: content.width
          text: {
            var base = Model.formatElapsed(hostWidget.elapsedSeconds)
            if (root.chunkText.length > 0) base += "  ·  " + root.chunkText
            return base
          }
          // Supplementary detail, not the primary status (that's the
          // PanelHead meta line above) — the hint-role treatment, matching
          // cliamp's analogous position/total line (ADR-0005).
          color: _webPalette.faint
          textFont.family: Style.font.family
          textFont.pixelSize: Style.font.caption
          requestedElide: Text.ElideRight
        }

        // Progress. Deliberately not a slider: piper-tts streams chunk by
        // chunk with no seekable timeline, so this is a read-only best-effort
        // fill, not a scrub bar.
        Rectangle {
          width: content.width
          height: Style.space(6)
          radius: height / 2
          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.18)
          visible: root.speaking

          Rectangle {
            height: parent.height
            radius: parent.radius
            width: Math.max(parent.height, parent.width * root.progress)
            color: root.barForeground
            opacity: hostWidget && hostWidget.paused ? 0.45 : 0.9
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
          }
        }

        Text {
          visible: root.speaking
          width: content.width
          text: "Seeking isn't available for streaming TTS."
          color: _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator {}

        // Pause / Stop.
        Row {
          spacing: Style.space(8)

          Kit.ActionButton {
            text: (hostWidget && hostWidget.paused) ? "Resume" : "Pause"
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text + " reading"
            foreground: root.barForeground
            bordered: true
            enabled: root.speaking
            onClicked: if (hostWidget) hostWidget.togglePause()
          }
          Kit.ActionButton {
            text: "Stop"
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: "Stop reading aloud"
            foreground: root.barForeground
            bordered: true
            enabled: root.speaking
            onClicked: if (hostWidget) hostWidget.stopPlayback()
          }
        }

        // Speed. Streaming audio can't be re-timed mid-flight, so this sets
        // the rate for the next reading (and for Loop); "Restart now" applies
        // it to the current one by re-speaking from the top.
        PanelSectionHeader {
          text: "SPEED"
          foreground: root.barForeground
        }

        Row {
          spacing: Style.space(6)

          Repeater {
            model: root.speeds
            Kit.ActionButton {
              required property var modelData
              text: (modelData === 1 ? "1" : String(modelData)) + "×"
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: "Set reading speed to " + String(modelData) + " times normal"
              foreground: root.barForeground
              bordered: hostWidget && Math.abs(hostWidget.speed - modelData) < 0.001
              onClicked: if (hostWidget) hostWidget.setSpeed(modelData)
            }
          }
        }

        Kit.ActionButton {
          text: "Restart now at " + (hostWidget ? (hostWidget.speed === 1 ? "1" : String(hostWidget.speed)) : "1") + "×"
          focusable: true
          Accessible.role: Accessible.Button
          Accessible.name: text
          foreground: root.barForeground
          bordered: true
          visible: root.speaking
          onClicked: if (hostWidget) hostWidget.restartAtSpeed()
        }

        PanelSeparator {}

        // Voice. Same streaming constraint as Speed — piper can't swap the
        // model mid-utterance — so choosing here re-speaks the current reading
        // from the top, and pins the voice for Loop / replays. With nothing
        // speaking it just records the choice.
        PanelSectionHeader {
          text: "VOICE"
          foreground: root.barForeground
        }

        Dropdown {
          id: voiceDropdown
          width: content.width
          showLabel: false
          activeFocusOnTab: true
          options: hostWidget ? hostWidget.voices : []
          value: root.voiceSelection
          foreground: root.barForeground
          onChanged: function (v) {
            root.voiceSelection = v
            if (hostWidget) hostWidget.setVoice(v)
          }
        }

        Text {
          visible: root.speaking
          width: content.width
          text: "Changing voice restarts the current reading."
          color: _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator {}

        Toggle {
          width: content.width
          activeFocusOnTab: true
          label: "Loop reading"
          description: (hostWidget && hostWidget.loopEnabled)
            ? "Restarts automatically when it finishes"
            : "Plays once"
          checked: hostWidget && hostWidget.loopEnabled
          foreground: root.barForeground
          onClicked: if (hostWidget) hostWidget.toggleLoop()
        }

        Toggle {
          width: content.width
          activeFocusOnTab: true
          label: "Mute"
          description: (hostWidget && hostWidget.muted)
            ? "Silenced — piper keeps running"
            : "Audible"
          checked: hostWidget && hostWidget.muted
          foreground: root.barForeground
          enabled: root.speaking
          onClicked: if (hostWidget) hostWidget.toggleMute()
        }

        Text {
          text: "Space: pause  ·  X: stop  ·  Esc: close"
          color: _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
