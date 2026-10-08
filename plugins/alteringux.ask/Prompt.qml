import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit
import "RequestGeneration.js" as RequestGeneration
import "../shared"

Item {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string query: ""
  property string answer: ""
  property string error: ""
  property bool busy: false
  property int requestSerial: 0
  property var requestGeneration: RequestGeneration.create()
  property string pendingQuery: ""
  property bool pendingVoice: false

  property string home: Quickshell.env("HOME")
  readonly property string askScript: root.home + "/.local/bin/omarchy-nanogpt-ask"
  readonly property string piperBin: root.home + "/.local/bin/piper-tts"
  readonly property string ttsTag: "nanogpt-ask"

  property color background: _webPalette.menuBackground
  property color foreground: _webPalette.menuText
  property color border: _webPalette.menuBorder
  property color scrim: _webPalette.menuScrim
  property var borderSpec: Border.surfaceSpec("menu", "border", root.border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(620), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(440), panel.height - Style.gapsOut * 2)
  property int voiceRowHeight: Style.space(30)

  readonly property var guard: Kit.BugGuard.create("alteringux.ask", function(argv) { Quickshell.execDetached(argv) })

  Kit.Store {
    id: configStore
    fileName: "ask-nanogpt-config.json"
    parse: function(raw) {
      var config = { voiceEnabled: false }
      try {
        var parsed = raw && raw.length ? JSON.parse(raw) : ({})
        if (typeof parsed.voiceEnabled === "boolean")
          config.voiceEnabled = parsed.voiceEnabled
      } catch (e) {}
      return config
    }
  }

  readonly property bool voiceEnabled: configStore.loaded &&
    configStore.value && configStore.value.voiceEnabled === true

  function open(payloadJson) {
    guard.run("open", function() {
      root.cancelActiveRequest()
      root.stopSpeech()
      root.opened = true
      root.query = ""
      root.answer = ""
      root.error = ""
      root.busy = false
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    })
  }

  function stopSpeech() {
    Quickshell.execDetached([root.piperBin, "--stop", "--tag", root.ttsTag])
  }

  function cancelActiveRequest() {
    root.requestSerial = RequestGeneration.cancel(root.requestGeneration)
    root.pendingQuery = ""
    root.pendingVoice = false
    if (askProcess.running) askProcess.running = false
    root.busy = false
  }

  function startRequest(serial, text, voice) {
    RequestGeneration.activate(root.requestGeneration, serial)
    askProcess.requestSerial = serial
    askProcess.command = [root.askScript, voice ? "--voice" : "--no-voice", text]
    askProcess.running = true
  }

  function maybeStartPendingRequest() {
    var serial = RequestGeneration.takePending(root.requestGeneration)
    if (!serial) return
    var text = root.pendingQuery
    var voice = root.pendingVoice
    root.pendingQuery = ""
    root.pendingVoice = false
    if (!root.opened || serial !== root.requestSerial) return
    root.startRequest(serial, text, voice)
  }

  function cancelActiveRequestLegacy() {
    root.requestSerial++
    if (askProcess.running) askProcess.running = false
    root.busy = false
  }

  function close() {
    root.cancelActiveRequest()
    root.stopSpeech()
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "alteringux.ask")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setVoiceEnabled(enabled) {
    if (!configStore.loaded) return
    var next = {}
    var current = configStore.value || ({})
    for (var key in current) next[key] = current[key]
    next.voiceEnabled = !!enabled
    configStore.value = next
    configStore.save()
    if (!next.voiceEnabled) {
      root.cancelActiveRequest()
      root.stopSpeech()
    }
  }

  function submit() {
    guard.run("submit", function() {
      var text = root.query.trim()
      if (!text || root.busy) return

      root.answer = ""
      root.error = ""
      root.busy = true
      var serial = RequestGeneration.begin(root.requestGeneration)
      root.requestSerial = serial
      // Keep the old Process generation in place until its stdout and exit
      // signals have both arrived. Reusing the mutable generation property
      // before then lets a late old response pass as the new request.
      if (askProcess.running) {
        RequestGeneration.queue(root.requestGeneration, serial)
        root.pendingQuery = text
        root.pendingVoice = root.voiceEnabled
        askProcess.running = false
      } else {
        root.stopSpeech()
        root.startRequest(serial, text, root.voiceEnabled)
      }
      // A completed answer must not become part of the next prompt when the
      // user starts a follow-up in the same panel.
      root.query = ""
    })
  }

  function applyAnswer(serial, text) {
    guard.run("applyAnswer", function() {
      if (!root.opened || serial !== root.requestSerial) return
      root.answer = String(text || "").trim()
      root.busy = false
      if (!root.answer) root.error = "NanoGPT returned an empty answer."
    })
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-ask-nanogpt"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit()
            event.accepted = true
          } else if (!root.busy && Util.editsFilter(event, root.query)) {
            root.query = Util.editedFilter(event, root.query)
            event.accepted = true
          } else if (!root.busy && event.text && event.text.length === 1 &&
                     event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.query += event.text
            event.accepted = true
          }
        }

        Column {
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: Style.spacing.panelGap

          Row {
            width: parent.width
            height: root.headerHeight
            spacing: Style.spacing.md

            Text {
              width: Math.max(0, parent.width - statusText.width - parent.spacing)
              anchors.verticalCenter: parent.verticalCenter
              text: "Ask NanoGPT"
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              id: statusText
              anchors.verticalCenter: parent.verticalCenter
              text: root.busy ? "Thinking…" : ""
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            id: shortcutHint
            width: parent.width
            text: root.busy ? "Esc: cancel and close" : "Enter: ask  ·  Esc: close"
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
          }

          Rectangle {
            width: parent.width
            height: Style.space(42)
            radius: root.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            border.width: 1
            border.color: root.query.length > 0 ? _webPalette.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)

            MarqueeText {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.query || "Type a question…"
              color: root.foreground
              textFont.family: Style.font.menuFamily
              textFont.pixelSize: Style.font.body
              requestedElide: Text.ElideRight
            }
          }

          Row {
            id: voiceRow
            width: parent.width
            height: root.voiceRowHeight
            spacing: Style.spacing.md
            activeFocusOnTab: configStore.loaded
            Accessible.role: Accessible.CheckBox
            Accessible.name: "Voice responses"
            Accessible.checkable: true
            Accessible.checked: root.voiceEnabled
            Accessible.focusable: configStore.loaded
            Accessible.onPressAction: toggleVoice()
            Accessible.onToggleAction: toggleVoice()

            function toggleVoice() {
              if (configStore.loaded) root.setVoiceEnabled(!root.voiceEnabled)
            }

            Keys.onReturnPressed: toggleVoice()
            Keys.onEnterPressed: toggleVoice()
            Keys.onSpacePressed: toggleVoice()

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Voice"
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
            }

            Rectangle {
              id: voiceSwitch
              width: Style.space(44)
              height: Style.space(24)
              radius: height / 2
              anchors.verticalCenter: parent.verticalCenter
              color: root.voiceEnabled ? _webPalette.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
              border.width: voiceRow.activeFocus ? Style.spacing.hairline : 0
              border.color: _webPalette.accent

              Rectangle {
                width: Style.space(18)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: root.voiceEnabled ? parent.width - width - Style.space(3) : Style.space(3)
                color: root.voiceEnabled ? root.background : root.foreground
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.voiceEnabled ? "On" : "Off"
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              anchors.fill: parent
              enabled: configStore.loaded
              onClicked: { voiceRow.forceActiveFocus(); voiceRow.toggleVoice() }
            }
          }


          Text {
            width: parent.width
            visible: !!root.error
            text: root.error
            color: _webPalette.urgent
            wrapMode: Text.WordWrap
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
          }

          Kit.PanelScroll {
            width: parent.width
            height: Math.max(0, parent.height - root.headerHeight - Style.space(42) - root.voiceRowHeight
              - shortcutHint.height - Style.spacing.panelGap * 4
              - (root.error ? Style.font.bodySmall + Style.spacing.panelGap : 0))
            contentHeight: answerText.implicitHeight
            visible: !!root.answer

            Text {
              id: answerText
              width: parent.width
              textFormat: Text.PlainText
              text: root.answer
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              lineHeight: 1.15
            }
          }

          Kit.EmptyState {
            width: parent.width
            visible: !root.busy && !root.answer && !root.error
            text: "Ask anything"
            hint: root.voiceEnabled
              ? "Answers use NanoGPT and are spoken with Piper TTS."
              : "Answers use NanoGPT. Voice is off by default; toggle Voice to speak."
            foreground: root.foreground
          }
        }
      }
    }
  }

  Process {
    id: askProcess
    running: false
    property int requestSerial: 0

    stdout: StdioCollector {
      id: askOutput
      waitForEnd: true
      onStreamFinished: {
        var serial = askProcess.requestSerial
        RequestGeneration.markOutput(root.requestGeneration, serial)
        root.applyAnswer(serial, askOutput.text)
        root.maybeStartPendingRequest()
      }
    }

    stderr: StdioCollector {
      id: askError
      waitForEnd: true
    }

    onExited: function(exitCode) {
      var serial = askProcess.requestSerial
      RequestGeneration.markExited(root.requestGeneration, serial)
      if (root.opened && RequestGeneration.accepts(root.requestGeneration, serial)
          && exitCode !== 0) {
        root.busy = false
        root.error = askError.text.trim() || ("NanoGPT request failed (exit " + exitCode + ").")
      }
      root.maybeStartPendingRequest()
    }
  }
}
