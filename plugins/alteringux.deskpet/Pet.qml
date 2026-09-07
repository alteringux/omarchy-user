import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// The floating companion itself: a full-screen transparent layer-shell
// window (matches grip's Prompt.qml / the stock OSD) whose `mask` is
// clamped down to just the pet's own hit box, so the rest of the desktop
// stays fully click-through -- this window only intercepts input right where
// the sprite is drawn.
//
// Position is user-dragged and persisted as a screen-relative fraction
// (posFracX/Y) via hostWidget.setPosition, so it lands sensibly on whatever
// monitor size loads it. Everything it says comes from Model.js's phrase
// banks; this file only decides *when* to ask for a line.
Item {
  id: root

  property var hostWidget: null

  readonly property var state: hostWidget ? hostWidget.state : Model.defaultState()
  readonly property var liveState: hostWidget ? hostWidget.liveState : Model.defaultState()
  readonly property var pet: hostWidget ? hostWidget.pet : Model.petById("cat")
  readonly property bool muted: !!root.state.muted
  readonly property bool isFirstEverRun: hostWidget && hostWidget.ageDaysValue === 0
    && (root.state.totalPokes || 0) === 0 && (root.state.totalFeeds || 0) === 0

  // Re-checked against the current unlock set (not just "was it equippable
  // once") so an accessory that somehow ended up in a hand-edited state file
  // without its achievement doesn't render.
  readonly property var accessory: {
    var id = root.state.accessoryId
    if (!id || !hostWidget) return null
    if (!Model.isAccessoryUnlocked(id, hostWidget.liveState, hostWidget.nowMs)) return null
    for (var i = 0; i < Model.ACCESSORIES.length; i++) if (Model.ACCESSORIES[i].id === id) return Model.ACCESSORIES[i]
    return null
  }

  // ---- speech bubble ------------------------------------------------
  property string bubbleText: ""
  property bool bubbleVisible: false

  Timer { id: bubbleHideTimer; interval: 5500; onTriggered: root.bubbleVisible = false }

  function say(text, durationMs) {
    if (root.muted || !text || !text.length) return
    root.bubbleText = text
    root.bubbleVisible = true
    bubbleHideTimer.interval = durationMs || 5500
    bubbleHideTimer.restart()
  }

  // Only mutates state; the resulting reaction (bubble line + particles) is
  // dispatched uniformly from onStateChanged below, so a poke/feed/play
  // triggered from the panel or an IPC hotkey makes the floating pet react
  // exactly the same way a direct click does.
  function poke() { if (hostWidget) hostWidget.pokePet() }

  // ---- particle bursts -------------------------------------------------
  // Purely decorative, spawned as children of hitBox so they sit at the
  // right local coordinates; each instance destroys itself when its own
  // animation finishes. `targetY` is passed in as a plain number at
  // creation (not bound to `y`) -- binding it to `particle.y` instead would
  // make the animation's target recompute every frame as y itself moves,
  // chasing a perpetually receding goal instead of settling.
  Component {
    id: particleComponent
    Text {
      id: particle
      property real targetY: y
      font.pixelSize: Style.space(16)
      ParallelAnimation {
        running: true
        NumberAnimation { target: particle; property: "y"; to: particle.targetY; duration: 900; easing.type: Easing.OutQuad }
        NumberAnimation { target: particle; property: "opacity"; to: 0; duration: 900 }
        onStopped: particle.destroy()
      }
    }
  }
  function spawnParticles(kind) {
    var glyphs = kind === "heart" ? ["❤️", "💕", "💗"]
      : kind === "food" ? ["🍎", "🍪", "🍓"]
      : ["✨", "⭐", "🌟"]
    for (var i = 0; i < 3; i++) {
      var startX = hitBox.width / 2 - 8 + (Math.random() * 28 - 14)
      var startY = hitBox.height / 2 - 6
      particleComponent.createObject(hitBox, {
        text: glyphs[Math.floor(Math.random() * glyphs.length)],
        x: startX,
        y: startY,
        targetY: startY - (46 + Math.random() * 30)
      })
    }
  }

  // ---- ambient (unsolicited, Clippy-style) chatter -------------------
  Timer { id: ambientTimer; running: false; repeat: false; onTriggered: root._fireAmbient() }

  function _fireAmbient() {
    if (hostWidget && !root.liveState.asleep) {
      root.say(Model.pickAmbientLine(root.pet, {
        isLowBattery: hostWidget.isLowBattery,
        minutesIdleValue: hostWidget.minutesIdleValue,
        moodLabelValue: hostWidget.mood,
        hourValue: hostWidget.hourValue
      }, Math.random() * 10000))
    }
    root._scheduleAmbient()
  }

  function _scheduleAmbient() {
    var minutes = (root.state && root.state.speechFreqMin > 0) ? root.state.speechFreqMin : 3
    var jitter = 0.7 + Math.random() * 0.6
    ambientTimer.interval = Math.max(20000, Math.round(minutes * 60000 * jitter))
    ambientTimer.restart()
  }

  // ---- opt-in real screen-vision commentary ---------------------------
  // Separate from the canned ambient chatter above: on its own (much
  // longer) timer, shells out to deskpet-look, which screenshots the
  // desktop and asks a Featherless vision model for one line in the pet's
  // voice. Off by default (see Model.defaultState) since it sends actual
  // screen content to a third-party API each time it fires.
  property bool _lookBusy: false
  property string _lookSystemPrompt: ""

  Process {
    id: lookProcess
    running: false
    command: [Quickshell.env("HOME") + "/.local/bin/deskpet-look", "--system", root._lookSystemPrompt]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._onLookResult(text)
    }
    onExited: root._lookBusy = false
  }

  function _onLookResult(text) {
    var line = (text || "").trim()
    if (line.length > 0) root.say(line, 9000)
  }

  Timer { id: screenLookTimer; running: false; repeat: false; onTriggered: root._fireScreenLook() }

  function _fireScreenLook() {
    if (hostWidget && root.state.screenWatchEnabled && !root.liveState.asleep && !root.muted && !root._lookBusy) {
      root._lookSystemPrompt = Model.screenLookSystemPrompt(root.pet)
      root._lookBusy = true
      lookProcess.running = true
    }
    root._scheduleScreenLook()
  }

  function _scheduleScreenLook() {
    var minutes = (root.state && root.state.screenLookFreqMin > 0) ? root.state.screenLookFreqMin : 20
    var jitter = 0.85 + Math.random() * 0.3
    screenLookTimer.interval = Math.max(5 * 60000, Math.round(minutes * 60000 * jitter))
    screenLookTimer.restart()
  }

  // ---- reaction dispatch ------------------------------------------------
  // Every interaction -- click on the pet, a panel button, an IPC hotkey --
  // funnels through hostWidget into the same raw `state` this binds to.
  // Reacting here (rather than at each call site) means the floating pet
  // responds the same way no matter which door the interaction came in.
  property var prevRawState: null

  onStateChanged: {
    var prev = root.prevRawState
    var next = root.state
    if (prev && hostWidget) {
      var unlocked = Model.newlyUnlocked(prev, next, hostWidget.nowMs)
      if (next.agedUp && !prev.agedUp) {
        root.say(Model.pickAgeUpLine(root.pet), 7000)
        spawnParticles("sparkle")
        bounceAnim.restart()
      } else if (unlocked.length > 0) {
        root.say("🏆 " + unlocked[0].name + " — " + unlocked[0].description, 7000)
        spawnParticles("sparkle")
      } else if ((next.totalPokes || 0) > (prev.totalPokes || 0)) {
        root.say(Model.pickPokeLine(root.pet, next, Math.random() * 10000))
        spawnParticles("heart")
        bounceAnim.restart()
      } else if ((next.totalFeeds || 0) > (prev.totalFeeds || 0)) {
        root.say(Model.pickFeedLine(root.pet, Math.random() * 10000))
        spawnParticles("food")
        bounceAnim.restart()
      } else if ((next.totalPlays || 0) > (prev.totalPlays || 0)) {
        root.say(Model.pickPlayLine(root.pet, Math.random() * 10000))
        spawnParticles("sparkle")
        bounceAnim.restart()
      } else if (next.petId !== prev.petId) {
        if (next.shiny) root.say(Model.pickShinyLine(root.pet), 7000)
        else root.say(Model.pickGreeting(root.pet, Math.random() * 10000))
      }
    }
    root.prevRawState = next
    // Interacting with the pet quiets ambient chatter down for a beat rather
    // than talking over the user right after they just fed/played/poked it.
    root._scheduleAmbient()
  }

  // ---- sleep transitions ----------------------------------------------
  property bool wasAsleep: false
  onLiveStateChanged: {
    var asleepNow = root.liveState.asleep
    if (asleepNow && !root.wasAsleep) root.say(Model.sleepyLine(root.pet))
    else if (!asleepNow && root.wasAsleep) root.say(Model.wakeLine(root.pet))
    root.wasAsleep = asleepNow
  }

  Component.onCompleted: {
    root._scheduleAmbient()
    root._scheduleScreenLook()
    greetTimer.start()
  }
  Timer {
    id: greetTimer
    interval: 700
    onTriggered: {
      root.say(Model.pickGreeting(root.pet, Math.random() * 10000))
      if (root.isFirstEverRun) introTimer.start()
    }
  }
  Timer {
    id: introTimer
    interval: 3200
    onTriggered: root.say("Right-click me any time for settings — feed me, pick a different pet, whatever.")
  }

  PanelWindow {
    id: win
    visible: true
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omarchy-deskpet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Only the hit box catches input; everywhere else on the screen passes
    // clicks straight through to whatever's underneath.
    mask: Region { item: hitBox }

    readonly property real hitSize: 64

    Item {
      id: petContainer
      readonly property real defaultFracX: 0.9
      readonly property real defaultFracY: 0.8
      readonly property real maxX: Math.max(0, win.width - width)
      readonly property real maxY: Math.max(0, win.height - height)

      width: win.hitSize
      height: win.hitSize
      x: (root.state.posFracX !== null && root.state.posFracX !== undefined)
        ? root.state.posFracX * maxX : defaultFracX * maxX
      y: (root.state.posFracY !== null && root.state.posFracY !== undefined)
        ? root.state.posFracY * maxY : defaultFracY * maxY

      // ---- roam: opt-in wandering around the whole screen ----------------
      // Off by default (Model.defaultState roamMode: "off"). While enabled
      // and awake and not being dragged, picks a random point on screen and
      // animates there at a constant speed -- "gallop" is just a much
      // higher px/sec and a shorter pause between legs than "walk", so the
      // two read as different gaits rather than one being a faster copy of
      // the other. Animating x/y here permanently breaks the posFracX/Y
      // binding above (same as a manual drag does today); once roaming
      // stops we persist the resting spot once via hostWidget.setPosition
      // so a reload resumes from there instead of snapping back.
      readonly property string roamMode: root.state.roamMode || "off"
      property bool roamed: false
      property bool facingLeft: false
      property bool moving: false

      function roamSpeedPxPerSec() { return petContainer.roamMode === "gallop" ? 220 : 70 }
      function roamPauseMs() {
        return petContainer.roamMode === "gallop" ? (400 + Math.random() * 700) : (1500 + Math.random() * 2500)
      }

      NumberAnimation { id: roamMoveX; target: petContainer; property: "x"; easing.type: Easing.Linear; onStopped: petContainer.moving = false }
      NumberAnimation { id: roamMoveY; target: petContainer; property: "y"; easing.type: Easing.Linear }

      // ---- gimmicky "in motion" flourishes ---------------------------
      // Purely decorative: a little dust/motion-line trail kicked up behind
      // it while a leg is in flight, gallop kicking up more and faster than
      // a walk. Reuses the same particleComponent the poke/feed/play bursts
      // use, just with different glyphs and a downward drift instead of up.
      Timer {
        id: dustTimer
        running: petContainer.moving
        repeat: true
        interval: petContainer.roamMode === "gallop" ? 180 : 420
        onTriggered: petContainer.spawnDust()
      }

      function spawnDust() {
        var gallop = petContainer.roamMode === "gallop"
        var trailX = hitBox.width / 2 + (petContainer.facingLeft ? 1 : -1) * (14 + Math.random() * 6)
        var startY = hitBox.height * 0.7 + (Math.random() * 8 - 4)
        particleComponent.createObject(hitBox, {
          text: gallop ? "💨" : "·",
          "font.pixelSize": gallop ? Style.space(14) : Style.space(10),
          x: trailX,
          y: startY,
          opacity: 0.75,
          targetY: startY + (gallop ? 10 : 4)
        })
      }

      Timer {
        id: roamTimer
        running: true
        repeat: false
        interval: 2000
        onTriggered: {
          var idle = petContainer.roamMode === "off" || root.liveState.asleep || interactArea.dragging
          if (idle) {
            if (petContainer.roamed && hostWidget && petContainer.maxX > 0 && petContainer.maxY > 0) {
              hostWidget.setPosition(petContainer.x / petContainer.maxX, petContainer.y / petContainer.maxY)
            }
            petContainer.roamed = false
            roamTimer.interval = 2500
            roamTimer.restart()
            return
          }

          var targetX = Math.random() * petContainer.maxX
          var targetY = Math.random() * petContainer.maxY
          var dx = targetX - petContainer.x
          var dy = targetY - petContainer.y
          var dist = Math.sqrt(dx * dx + dy * dy)
          var duration = Math.max(300, Math.round((dist / petContainer.roamSpeedPxPerSec()) * 1000))

          petContainer.facingLeft = dx < 0
          petContainer.moving = true
          roamMoveX.to = targetX; roamMoveX.duration = duration
          roamMoveY.to = targetY; roamMoveY.duration = duration
          roamMoveX.restart(); roamMoveY.restart()

          if (petContainer.roamMode === "gallop" && Math.random() < 0.3) {
            root.say(Model.pickZoomLine(root.pet, Math.random() * 10000), 2200)
          }

          petContainer.roamed = true
          roamTimer.interval = duration + petContainer.roamPauseMs()
          roamTimer.restart()
        }
      }

      // ---- speech bubble: purely decorative, drawn outside the mask ---
      Rectangle {
        id: bubble
        visible: root.bubbleVisible
        opacity: root.bubbleVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        anchors.bottom: hitBox.top
        anchors.bottomMargin: Style.space(8)
        anchors.horizontalCenter: hitBox.horizontalCenter
        width: Math.min(Style.space(220), bubbleLabel.implicitWidth + Style.space(24))
        height: bubbleLabel.implicitHeight + Style.space(16)
        radius: Style.cornerRadius
        color: Color.bar.background
        border.width: 1
        border.color: Qt.rgba(Color.bar.text.r, Color.bar.text.g, Color.bar.text.b, 0.25)

        Text {
          id: bubbleLabel
          anchors.fill: parent
          anchors.margins: Style.space(8)
          text: root.bubbleText
          wrapMode: Text.WordWrap
          color: Color.bar.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
        }

        // Little tail pointing down at the pet.
        Rectangle {
          width: Style.space(12)
          height: Style.space(12)
          color: parent.color
          border.width: 1
          border.color: parent.border.color
          rotation: 45
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.bottom
          anchors.topMargin: -Style.space(7)
          z: -1
        }
      }

      // ---- the sprite itself -------------------------------------------
      Item {
        id: hitBox
        width: win.hitSize
        height: win.hitSize

        property real bobOffset: 0
        property real walkOffset: 0
        property real blinkScale: 1

        SequentialAnimation {
          running: !root.liveState.asleep
          loops: Animation.Infinite
          // Bobs noticeably faster while mid-gallop, for a bit of energy.
          NumberAnimation { target: hitBox; property: "bobOffset"; to: -6; duration: petContainer.roamMode === "gallop" ? 220 : 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: hitBox; property: "bobOffset"; to: 0; duration: petContainer.roamMode === "gallop" ? 220 : 900; easing.type: Easing.InOutSine }
        }

        // Occasional blink: a quick vertical squash.
        Timer {
          running: !root.liveState.asleep
          repeat: true
          interval: 2500 + Math.random() * 3500
          onTriggered: { interval = 2500 + Math.random() * 3500; blinkAnim.restart() }
        }
        SequentialAnimation {
          id: blinkAnim
          NumberAnimation { target: hitBox; property: "blinkScale"; to: 0.85; duration: 70 }
          NumberAnimation { target: hitBox; property: "blinkScale"; to: 1.0; duration: 90 }
        }

        // Occasional short "walk" drift, only while awake and not dragged.
        Timer {
          running: !root.liveState.asleep && !interactArea.dragging
          repeat: true
          interval: 14000 + Math.random() * 20000
          onTriggered: {
            interval = 14000 + Math.random() * 20000
            walkAnim.to = (Math.random() < 0.5 ? -1 : 1) * (10 + Math.random() * 14)
            walkAnim.restart()
          }
        }
        SequentialAnimation {
          id: walkAnim
          property real to: 0
          NumberAnimation { target: hitBox; property: "walkOffset"; to: walkAnim.to; duration: 900; easing.type: Easing.InOutQuad }
          NumberAnimation { target: hitBox; property: "walkOffset"; to: 0; duration: 900; easing.type: Easing.InOutQuad }
        }

        // A little upward hop on poke, for feedback beyond the bubble.
        SequentialAnimation {
          id: bounceAnim
          NumberAnimation { target: hitBox; property: "bobOffset"; to: -14; duration: 110; easing.type: Easing.OutQuad }
          NumberAnimation { target: hitBox; property: "bobOffset"; to: 0; duration: 180; easing.type: Easing.OutBounce }
        }

        Text {
          id: glyphText
          text: root.pet.glyph
          font.pixelSize: Style.space(46)
          x: (hitBox.width - width) / 2 + hitBox.walkOffset
          y: (hitBox.height - height) / 2 + hitBox.bobOffset
          scale: hitBox.blinkScale
          // Mirrors to face the direction it's currently roaming toward, and
          // squashes/stretches cartoon-run style while a leg is in flight --
          // gallop stretches harder than a walk does.
          transform: Scale {
            origin.x: glyphText.width / 2
            origin.y: glyphText.height / 2
            xScale: (petContainer.facingLeft ? -1 : 1)
              * (petContainer.moving ? (petContainer.roamMode === "gallop" ? 1.3 : 1.12) : 1.0)
            yScale: petContainer.moving ? (petContainer.roamMode === "gallop" ? 0.78 : 0.92) : 1.0
            Behavior on xScale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            Behavior on yScale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
          }
          opacity: root.liveState.asleep ? 0.6 : 1.0
          Behavior on opacity { NumberAnimation { duration: 400 } }
        }

        // Equipped accessory rides along with the bob/walk offsets so it
        // reads as worn rather than pasted on.
        Text {
          visible: root.accessory !== null
          text: root.accessory ? root.accessory.glyph : ""
          font.pixelSize: Style.space(22)
          x: (hitBox.width - width) / 2 + hitBox.walkOffset
          y: glyphText.y - height * 0.55
        }

        // A slow twinkle in the corner marks the rare shiny variant.
        Text {
          visible: root.state.shiny === true
          text: "✨"
          font.pixelSize: Style.space(14)
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.leftMargin: -Style.space(2)
          anchors.bottomMargin: -Style.space(2)

          SequentialAnimation on opacity {
            running: root.state.shiny === true
            loops: Animation.Infinite
            NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
          }
        }

        Text {
          visible: root.liveState.asleep
          opacity: root.liveState.asleep ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 400 } }
          text: "💤"
          font.pixelSize: Style.space(18)
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: -Style.space(4)
          anchors.topMargin: -Style.space(4)

          SequentialAnimation on y {
            running: root.liveState.asleep
            loops: Animation.Infinite
            NumberAnimation { to: -Style.space(6); duration: 1200; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 1200; easing.type: Easing.InOutSine }
          }
        }

        MouseArea {
          id: interactArea
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true

          property real pressGX: 0
          property real pressGY: 0
          property real startContainerX: 0
          property real startContainerY: 0
          property bool dragging: false
          property bool draggedEnough: false

          // Deltas must be measured in a frame that doesn't move with the
          // item being dragged. mouse.x/y are relative to interactArea
          // itself, which moves as petContainer moves -- using those
          // directly makes the delta fight itself every frame (the pet
          // lags far behind the cursor, feels sticky). Map to the window's
          // root item instead, which stays fixed for the whole drag.
          onPressed: function (mouse) {
            if (mouse.button === Qt.RightButton) return
            roamMoveX.stop(); roamMoveY.stop()   // hand control to the drag, don't fight an in-flight roam leg
            var g = interactArea.mapToItem(null, mouse.x, mouse.y)
            pressGX = g.x
            pressGY = g.y
            startContainerX = petContainer.x
            startContainerY = petContainer.y
            dragging = true
            draggedEnough = false
          }
          onPositionChanged: function (mouse) {
            if (!dragging) return
            var g = interactArea.mapToItem(null, mouse.x, mouse.y)
            var dx = g.x - pressGX
            var dy = g.y - pressGY
            if (Math.abs(dx) > 4 || Math.abs(dy) > 4) draggedEnough = true
            if (draggedEnough) {
              petContainer.x = Math.max(0, Math.min(petContainer.maxX, startContainerX + dx))
              petContainer.y = Math.max(0, Math.min(petContainer.maxY, startContainerY + dy))
            }
          }
          onReleased: function (mouse) {
            if (mouse.button === Qt.RightButton) return
            dragging = false
            if (draggedEnough) {
              var fx = petContainer.maxX > 0 ? petContainer.x / petContainer.maxX : petContainer.defaultFracX
              var fy = petContainer.maxY > 0 ? petContainer.y / petContainer.maxY : petContainer.defaultFracY
              if (hostWidget) hostWidget.setPosition(fx, fy)
            } else {
              root.poke()
            }
          }
          onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton && hostWidget) hostWidget.open()
          }
        }
      }
    }
  }
}
