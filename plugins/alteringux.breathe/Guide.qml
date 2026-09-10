import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// The fullscreen breath guide: a transparent layer-shell window (the same
// shape as deskpet's Pet.qml and the stock OSD) carrying one large orb that
// swells and settles with the breath.
//
// Unlike the desk pet, this overlay deliberately does NOT clamp its input
// mask: while you are breathing it owns the screen, so a stray click lands on
// pause rather than on whatever was underneath. It takes keyboard focus on
// demand for Space and Escape, and the window only exists while
// hostWidget.guideVisible — the bar widget's LazyLoader tears it down
// otherwise, so an idle plugin holds no surface.
//
// Every number it draws comes from hostWidget.live (one shared
// Model.resolve), and the orb radius comes from Model.orbScale via that same
// result. Re-deriving either here is what would let the overlay and the
// panel's compact guide drift out of step.
Item {
  id: root

  property var hostWidget: null

  readonly property var live: hostWidget ? hostWidget.live : null
  readonly property var technique: hostWidget ? hostWidget.technique : null
  readonly property var config: hostWidget ? hostWidget.config : Model.defaultConfig()
  readonly property bool running: hostWidget ? hostWidget.running : false
  readonly property bool paused: hostWidget ? hostWidget.paused : false
  readonly property bool done: hostWidget ? hostWidget.done : false
  readonly property bool reduceMotion: root.config && root.config.reduceMotion === true

  readonly property color tone: hostWidget ? hostWidget.toneColor : Kit.Palette.info
  readonly property real orbScale: root.live ? root.live.orbScale : Model.SCALE_MIN

  readonly property string phaseKind: root.live ? root.live.phaseKind : ""
  readonly property bool isHold: root.live ? root.live.isHold : false
  readonly property bool isRetention: root.phaseKind === Model.PHASE.RETENTION
  readonly property bool isRecovery: root.phaseKind === Model.PHASE.RECOVERY
  readonly property bool isSwitch: root.phaseKind === Model.PHASE.SWITCH
  readonly property bool isPowerBreaths: root.phaseKind === Model.PHASE.POWER_BREATHS

  // A technique carrying a caution shows it before the first cycle turns over,
  // then gets out of the way — a warning that stays on screen for eight
  // minutes stops being read.
  readonly property bool showWarning: !!(root.technique && root.technique.warning)
    && root.live && root.live.cycleIndex === 0 && !root.done

  function act(name, fn) {
    if (hostWidget && hostWidget.usage) hostWidget.usage.record("guide:" + name)
    fn()
  }

  PanelWindow {
    id: win
    visible: true
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omarchy-breathe"
    WlrLayershell.layer: WlrLayer.Overlay
    // On demand rather than Exclusive: the guide wants Space and Escape while
    // it is up, but must not hold the compositor's keyboard hostage if it is
    // ever left open.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    readonly property real shortSide: Math.min(win.width, win.height)
    // The orb at full swell occupies a bit over a third of the short side:
    // large enough to breathe with peripherally, small enough to leave the
    // readout and the rings uncrowded.
    readonly property real orbMax: shortSide * 0.34

    // ---- scrim ---------------------------------------------------------
    // Painted from the theme background so the overlay reads correctly in a
    // light theme as well as a dark one, and faded rather than snapped.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
      opacity: root.done ? Math.max(0, (root.config.overlayDim || 0.82) - 0.15)
                         : (root.config.overlayDim || 0.82)
      Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    }

    // ---- input ---------------------------------------------------------
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function (mouse) {
        if (mouse.button === Qt.RightButton) root.act("close", function () { root.hostWidget.hideGuide() })
        else if (!root.done) root.act("toggle", function () { root.hostWidget.toggleSession() })
        else root.act("close", function () { root.hostWidget.hideGuide() })
      }
    }

    FocusScope {
      anchors.fill: parent
      focus: true
      Component.onCompleted: forceActiveFocus()

      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
          // Close the overlay WITHOUT killing the session: a glance away is
          // not an abandon, and the bar keeps counting.
          root.act("escape", function () { root.hostWidget.hideGuide() })
          event.accepted = true
        } else if (event.key === Qt.Key_Space) {
          if (!root.done) root.act("space", function () { root.hostWidget.toggleSession() })
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          // Skip the rest of a hold when you cannot last it out. Gated to an
          // active hold and to an arrow key (deliberate, not a stray letter),
          // and it only advances the breath — it never ends the session.
          if (root.running && root.isHold) root.act("skip", function () { root.hostWidget.skipHold() })
          event.accepted = true
        }
        // Deliberately no key that ENDS a session. This surface takes
        // compositor keyboard focus while it is up, so a stray keystroke
        // lands here; every binding it offers must therefore be reversible.
        // Finishing early is a decision, and it lives on the panel button.
      }
    }

    // ---- the breath ----------------------------------------------------
    Item {
      id: stage
      anchors.centerIn: parent
      width: win.orbMax * 2.6
      height: width
      opacity: root.done ? 0 : 1
      visible: opacity > 0.01
      Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

      // Two rings that trail the core at different rates. They are not
      // decoration for its own sake: the lag makes the direction of travel
      // readable at a glance, so you can tell an inhale from an exhale
      // without reading the word.
      Repeater {
        model: root.reduceMotion ? 0 : 2
        Rectangle {
          readonly property real spread: 1.0 + (index + 1) * 0.13
          anchors.centerIn: parent
          width: win.orbMax * 2 * root.orbScale * spread
          height: width
          radius: width / 2
          color: "transparent"
          border.width: Math.max(1, win.shortSide * 0.0015)
          border.color: root.tone
          opacity: (0.20 - index * 0.07) * (root.paused ? 0.4 : 1)

          // The lag itself. A longer duration on the outer ring is what
          // makes the swell look like it is propagating outward.
          Behavior on width {
            NumberAnimation { duration: 320 + index * 260; easing.type: Easing.OutCubic }
          }
          Behavior on opacity { NumberAnimation { duration: 300 } }
        }
      }

      // Soft glow: a wide, very faint disc under the core.
      Rectangle {
        anchors.centerIn: parent
        visible: !root.reduceMotion
        width: win.orbMax * 2 * root.orbScale * 1.35
        height: width
        radius: width / 2
        color: root.tone
        opacity: 0.10 * (root.paused ? 0.45 : 1)
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      }

      // The core.
      Rectangle {
        id: orb
        anchors.centerIn: parent
        width: win.orbMax * 2 * root.orbScale
        height: width
        radius: width / 2
        color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, root.paused ? 0.10 : 0.22)
        border.width: Math.max(1.5, win.shortSide * 0.0022)
        border.color: root.paused ? Kit.Palette.faint : root.tone

        // No Behavior on width: orbScale is already recomputed every frame
        // from the shared resolve, so animating it again would lag the breath
        // behind its own countdown.

        // A hold is the tense part of a pattern. Nothing moves, so without
        // this the screen looks frozen rather than held.
        SequentialAnimation on opacity {
          running: root.isHold && !root.paused && !root.reduceMotion
          loops: Animation.Infinite
          NumberAnimation { to: 0.72; duration: 1400; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1.0;  duration: 1400; easing.type: Easing.InOutSine }
          onStopped: orb.opacity = 1
        }

        Behavior on color { ColorAnimation { duration: 260 } }
      }

      // ---- progress rings ------------------------------------------------
      // Drawn rather than stacked: an arc that sweeps needs a real path, and
      // Canvas keeps it anti-aliased at any orb size.
      Canvas {
        id: rings
        anchors.fill: parent
        antialiasing: true

        readonly property real phaseFraction: root.live ? root.live.phaseFraction : 0
        readonly property real sessionFraction: root.live ? root.live.sessionFraction : 0
        onPhaseFractionChanged: requestPaint()
        onSessionFractionChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var cx = width / 2
          var cy = height / 2
          var start = -Math.PI / 2      // 12 o'clock
          var inner = win.orbMax * 1.30
          var outer = win.orbMax * 1.46

          // Phase progress — the ring you actually watch.
          ctx.lineWidth = Math.max(2, win.shortSide * 0.004)
          ctx.strokeStyle = Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.16)
          ctx.beginPath(); ctx.arc(cx, cy, inner, 0, Math.PI * 2); ctx.stroke()

          if (phaseFraction > 0) {
            ctx.strokeStyle = Qt.rgba(root.tone.r, root.tone.g, root.tone.b, root.paused ? 0.35 : 0.95)
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.arc(cx, cy, inner, start, start + Math.PI * 2 * phaseFraction)
            ctx.stroke()
          }

          // Whole-session progress, deliberately thinner and further out so
          // it never competes with the phase ring for attention.
          var fg = Color.foreground
          ctx.lineWidth = Math.max(1, win.shortSide * 0.0018)
          ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.12)
          ctx.beginPath(); ctx.arc(cx, cy, outer, 0, Math.PI * 2); ctx.stroke()

          if (sessionFraction > 0) {
            ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.40)
            ctx.lineCap = "butt"
            ctx.beginPath()
            ctx.arc(cx, cy, outer, start, start + Math.PI * 2 * sessionFraction)
            ctx.stroke()
          }
        }
      }

      // ---- readout -------------------------------------------------------
      Column {
        anchors.centerIn: parent
        spacing: Style.space(6)
        width: win.orbMax * 1.9

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.live ? root.live.phaseLabel : ""
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.display
          font.bold: true
          elide: Text.ElideRight
        }

        // The count. A hold counts UP, everything else counts down — during a
        // retention the number you want is how long you have lasted.
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: !root.isSwitch
          text: {
            if (!root.live) return ""
            return Model.formatClock(root.isHold ? root.live.phaseElapsedMs : root.live.phaseRemainingMs)
          }
          color: root.tone
          font.family: Style.font.family
          font.pixelSize: Style.font.displayLarge
          font.bold: true
        }

        // Wim Hof's power-breath block: a slow countdown here would be
        // meaningless, the breath number is the thing being tracked.
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: root.isPowerBreaths && root.live && root.live.breathCount
          text: root.live && root.live.breathCount
            ? "breath " + (root.live.breathIndex + 1) + " of " + root.live.breathCount : ""
          color: Color.foreground
          opacity: 0.75
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        // Alternate nostril: which side is the entire instruction, so it gets
        // the big treatment rather than hiding in the phase label.
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: root.isSwitch
          text: "Switch hands"
          color: root.tone
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Item { width: 1; height: Style.space(4) }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.technique
            ? root.technique.name + " · " + root.technique.pattern
            : ""
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.2
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.live ? ("cycle " + (root.live.cycleIndex + 1) + " of " + root.live.cycleCount) : ""
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }

    // ---- paused ---------------------------------------------------------
    // A paused session must never be mistaken for a hung one, so say it in
    // words as well as stopping the orb and lifting the scrim.
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: stage.bottom
      anchors.topMargin: Style.space(18)
      visible: root.paused && !root.done
      text: "Paused"
      color: Kit.Palette.warning
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
      font.letterSpacing: 2
    }

    // ---- caution --------------------------------------------------------
    Rectangle {
      id: warning
      visible: root.showWarning
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(40)
      width: Math.min(parent.width - Style.space(64), Style.space(560))
      height: warningText.implicitHeight + Style.space(24)
      radius: Style.cornerRadius
      color: Kit.Palette.cardBg
      border.width: 1
      border.color: Kit.Palette.warning
      opacity: 0.95

      Text {
        id: warningText
        anchors.centerIn: parent
        width: parent.width - Style.space(24)
        horizontalAlignment: Text.AlignHCenter
        text: root.technique && root.technique.warning ? root.technique.warning : ""
        color: Color.foreground
        wrapMode: Text.WordWrap
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    // ---- completion ------------------------------------------------------
    // Calm and self-dismissing: a modal that demands a click to close is the
    // wrong last impression for a breathing exercise.
    Column {
      id: completion
      anchors.centerIn: parent
      spacing: Style.space(10)
      visible: root.done
      opacity: root.done ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Model.PLUGIN_GLYPH
        color: Kit.Palette.positive
        font.family: Style.font.family
        font.pixelSize: Style.font.displayLarge
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.technique ? root.technique.name + " complete" : "Complete"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: {
          if (!root.live) return ""
          var cycles = root.live.cycleCount
          return cycles + " cycles · " + Model.formatDuration(Math.round(root.live.sessionElapsedMs / 1000))
        }
        color: Kit.Palette.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.2
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property int streak: root.hostWidget ? Model.streakOf(root.hostWidget.stats).current : 0
        visible: streak > 0
        text: streak + (streak === 1 ? " day streak" : " day streak")
        color: Kit.Palette.positive
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    // Let the completion state be read, then take the overlay down on its own.
    Timer {
      interval: 4200
      running: root.done
      onTriggered: if (root.hostWidget) root.hostWidget.hideGuide()
    }

    // ---- hint ------------------------------------------------------------
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(28)
      visible: !root.done
      text: (root.running && root.isHold ? "→ skip · " : "") + "Space pause · Esc hide"
      color: Kit.Palette.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      opacity: 0.7
    }
  }
}
