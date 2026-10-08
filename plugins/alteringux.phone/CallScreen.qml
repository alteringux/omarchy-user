import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// The fullscreen call screen: a transparent layer-shell window (the same shape
// as alteringux.breathe's Guide.qml and the stock OSD) that shows who you are
// talking to, the call state, a turn-driven ring, the rolling transcript, and
// the Mute / Hold / End controls — or Answer / Decline while a call is ringing.
//
// It never ends the call on a stray key: Esc hides the window (the call keeps
// running and the bar keeps the pill), and ending lives on the button only —
// the same lesson as the breathe overlay.
Item {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  property var hostWidget: null

  readonly property var call: hostWidget ? hostWidget.call : Model.defaultCall()
  readonly property string state: hostWidget ? hostWidget.state : "IDLE"
  readonly property bool ringing: root.state === "RINGING"
  readonly property bool dialing: root.state === "DIALING"
  readonly property bool connected: root.state === "CONNECTED"
  readonly property bool muted: root.call.muted === true
  readonly property bool hold: root.call.hold === true
  readonly property string turn: root.call.turn || "idle"
  readonly property int elapsed: hostWidget ? hostWidget.elapsedSeconds : 0

  readonly property color accent: _webPalette.foreground

  // "Call ended" grace: the daemon resets call.json to IDLE the moment a call
  // finishes; hold the screen briefly so the ending is legible, then dismiss.
  property bool ended: false
  onStateChanged: {
    if (root.state === "IDLE" || root.state === "ENDED") {
      root.ended = true
      endTimer.restart()
    } else {
      root.ended = false
      endTimer.stop()
    }
  }
  Timer {
    id: endTimer
    interval: 2500
    onTriggered: if (root.hostWidget) root.hostWidget.dismissCallScreen()
  }

  readonly property string stateLine: {
    if (root.ended) return "Call ended"
    if (root.ringing) return (root.call.reason && root.call.reason.length ? root.call.reason : "Incoming call")
    if (root.dialing) return "Calling…"
    if (root.hold) return "On hold"
    if (root.muted) return "Muted · " + Model.formatCallClock(root.elapsed * 1000)
    var base = "Connected " + Model.formatCallClock(root.elapsed * 1000)
    if (root.turn === "thinking") return base + " · thinking"
    if (root.turn === "tool") return base + " · " + (root.call.toolLabel || "using a tool")
    if (root.turn === "speaking") return base + " · speaking"
    if (root.turn === "listening") return base + " · listening"
    return base
  }

  property bool showTranscript: true

  PanelWindow {
    id: win
    visible: true
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omarchy-phone"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    readonly property real shortSide: Math.min(win.width, win.height)

    // ---- scrim ------------------------------------------------------
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(_webPalette.background.r, _webPalette.background.g, _webPalette.background.b, 1)
      opacity: 0.9
      Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    // A plain click on the backdrop hides the screen (call continues), matching
    // Esc. Controls below sit above this and consume their own clicks.
    MouseArea {
      anchors.fill: parent
      onClicked: if (root.hostWidget) root.hostWidget.dismissCallScreen()
    }

    FocusScope {
      anchors.fill: parent
      focus: true
      Component.onCompleted: forceActiveFocus()
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
          if (root.hostWidget) root.hostWidget.dismissCallScreen()
          event.accepted = true
        } else if (event.key === Qt.Key_M && root.connected) {
          if (root.hostWidget) root.hostWidget.toggleMute()
          event.accepted = true
        } else if (event.key === Qt.Key_Return && root.ringing) {
          if (root.hostWidget) root.hostWidget.answer()
          event.accepted = true
        }
        // Deliberately no key that ENDS the call.
      }
    }

    Column {
      anchors.centerIn: parent
      width: Math.min(win.width - Style.space(80), Style.space(560))
      spacing: Style.space(18)

      // ---- the ring -------------------------------------------------
      Item {
        id: ring
        anchors.horizontalCenter: parent.horizontalCenter
        width: win.shortSide * 0.34
        height: width

        // Two trailing rings whose spread + opacity track the turn: livelier
        // while the contact speaks, a slow breath while listening, a steady
        // hold while thinking / on hold.
        readonly property real base: (root.turn === "speaking") ? 1.14
                                   : (root.turn === "listening") ? 1.06
                                   : 1.0
        readonly property bool pulsing: root.connected && !root.hold && !root.ended

        Repeater {
          model: 2
          Rectangle {
            required property int index
            readonly property real spread: 1.0 + (index + 1) * 0.16
            anchors.centerIn: parent
            width: ring.width * ring.base * spread * (pulse.on ? 1.0 : 0.9)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1, win.shortSide * 0.0016)
            border.color: root.accent
            opacity: (0.18 - index * 0.06) * (root.hold || root.ended ? 0.4 : 1)
            Behavior on width { NumberAnimation { duration: 380 + index * 220; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 300 } }
          }
        }

        Rectangle {
          id: core
          anchors.centerIn: parent
          width: ring.width * (pulse.on ? 1.0 : 0.92)
          height: width
          radius: width / 2
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)
          border.width: Math.max(1.5, win.shortSide * 0.002)
          border.color: root.ended ? _webPalette.faint
                       : root.ringing ? _webPalette.urgent
                       : root.accent
          Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.InOutSine } }

          Text {
            anchors.centerIn: parent
            text: "" // nf-fa-phone
            font.family: Style.font.family
            font.pixelSize: win.shortSide * 0.09
            color: root.accent
          }
        }

        QtObject {
          id: pulse
          property bool on: false
        }
        Timer {
          interval: root.turn === "speaking" ? 480 : 1600
          repeat: true
          running: ring.pulsing || root.ringing
          triggeredOnStart: true
          onTriggered: pulse.on = !pulse.on
        }
      }

      // ---- who + state -------------------------------------------
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.call.contactName || "Call"
        color: _webPalette.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        font.bold: true
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.stateLine
        color: root.ringing ? _webPalette.urgent : _webPalette.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.letterSpacing: 1.1
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !!(root.call.lastError && root.call.lastError.length) && !root.ended
        text: root.call.lastError
        color: _webPalette.warning
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !!(root.hostWidget && root.hostWidget.actionStatus)
        text: root.hostWidget ? root.hostWidget.actionStatus : ""
        color: root.hostWidget && root.hostWidget.actionFailed ? _webPalette.negative : _webPalette.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: Math.min(parent.width, Style.space(520))
        horizontalAlignment: Text.AlignHCenter
        Accessible.role: Accessible.StaticText
        Accessible.name: text
      }

      // ---- transcript -------------------------------------------
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.showTranscript && root.connected && transcriptCol.children.length > 0
        width: parent.width
        height: Math.min(Style.space(220), transcriptFlick.contentHeight + Style.space(20))
        radius: Style.cornerRadius
        color: _webPalette.cardBackgroundFor(_webPalette.foreground)

        Flickable {
          id: transcriptFlick
          anchors.fill: parent
          anchors.margins: Style.space(10)
          clip: true
          contentHeight: transcriptCol.implicitHeight
          contentY: Math.max(0, contentHeight - height)
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: transcriptCol
            width: transcriptFlick.width
            spacing: Style.space(6)

            Repeater {
              model: root.call.transcript || []
              Text {
                required property var modelData
                width: transcriptCol.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: (modelData.role === "assistant"
                        ? (root.call.contactName || "Them")
                        : "You") + ":  " + modelData.text
                color: modelData.role === "assistant" ? _webPalette.foreground : _webPalette.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      // ---- controls -------------------------------------------
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(12)
        visible: !root.ended

        // Ringing: Answer / Decline.
        PhoneButton {
          visible: root.ringing
          label: "Answer"
          glyph: ""
          tone: "positive"
          onActivated: if (root.hostWidget) root.hostWidget.answer()
        }
        PhoneButton {
          visible: root.ringing
          label: "Decline"
          glyph: ""
          tone: "negative"
          onActivated: if (root.hostWidget) root.hostWidget.decline()
        }

        // In a call: Mute / Hold / End.
        PhoneButton {
          visible: root.connected || root.dialing
          label: root.muted ? "Unmute" : "Mute"
          glyph: root.muted ? "" : ""
          active: root.muted
          onActivated: if (root.hostWidget) root.hostWidget.toggleMute()
        }
        PhoneButton {
          visible: root.connected
          label: root.hold ? "Resume" : "Hold"
          glyph: root.hold ? "" : ""
          active: root.hold
          onActivated: if (root.hostWidget) root.hostWidget.toggleHold()
        }
        PhoneButton {
          visible: root.connected || root.dialing
          label: "End call"
          glyph: ""
          tone: "negative"
          onActivated: if (root.hostWidget) root.hostWidget.hangup()
        }
      }

      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.connected
        spacing: Style.space(4)

        PhoneButton {
          anchors.horizontalCenter: parent.horizontalCenter
          label: root.showTranscript ? "Hide transcript" : "Show transcript"
          onActivated: root.showTranscript = !root.showTranscript
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "M mute · Esc hide"
          color: _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          Accessible.role: Accessible.StaticText
          Accessible.name: text
        }
      }
    }
  }

  // A small pill button used across the control row.
  component PhoneButton: Rectangle {
    id: pb
    property string label: ""
    property string glyph: ""
    property string tone: "neutral" // neutral | positive | negative
    property bool active: false
    signal activated()
    Accessible.role: Accessible.Button
    Accessible.name: pb.label
    Accessible.onPressAction: if (pb.enabled && pb.visible) pb.activated()
    Accessible.description: pb.active ? "Active" : ""
    activeFocusOnTab: true

    readonly property color toneColor: pb.tone === "positive" ? _webPalette.positive
                                     : pb.tone === "negative" ? _webPalette.negative
                                     : _webPalette.foreground

    implicitWidth: pbRow.implicitWidth + Style.space(26)
    implicitHeight: pbRow.implicitHeight + Style.space(16)
    radius: height / 2
    color: pb.active ? Qt.rgba(pb.toneColor.r, pb.toneColor.g, pb.toneColor.b, 0.22)
          : (pbArea.containsMouse ? Qt.rgba(pb.toneColor.r, pb.toneColor.g, pb.toneColor.b, 0.12) : "transparent")
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? _webPalette.accent : (pb.active ? pb.toneColor : Qt.rgba(pb.toneColor.r, pb.toneColor.g, pb.toneColor.b, 0.45))

    Row {
      id: pbRow
      anchors.centerIn: parent
      spacing: Style.space(8)
      Text {
        text: pb.glyph
        color: pb.toneColor
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        visible: pb.glyph.length > 0
      }
      Text {
        text: pb.label
        color: _webPalette.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    MouseArea {
      id: pbArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { pb.forceActiveFocus(); pb.activated() }
    }
    Keys.onReturnPressed: pb.activated()
    Keys.onEnterPressed: pb.activated()
    Keys.onSpacePressed: pb.activated()
  }
}
