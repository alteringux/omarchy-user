import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// The exercise surface. One layer-shell window, two situations:
//   intro  — a scheduled review is queued (hostWidget.promptKind set, no
//            round yet): a centred card, Start / Not now / Snooze.
//   round  — hostWidget.stateValue.round is set: run the Spot-the-Change
//            phases locally (study → blank → test → review), then hand the
//            grade + accuracy + click list back to omarchy-glimpse.
//
// It renders straight from the host widget's watched stores and turns every
// button into an omarchy-glimpse verb via the host. It never writes state.
Item {
  id: root

  property var hostWidget: null

  readonly property string promptKind: hostWidget ? hostWidget.promptKind : ""
  readonly property bool takeover: root.promptKind === "takeover"
  readonly property var round: (hostWidget && hostWidget.stateValue && hostWidget.stateValue.round) ? hostWidget.stateValue.round : null
  readonly property var promptCardIds: (hostWidget && hostWidget.stateValue.prompt) ? hostWidget.stateValue.prompt.cardIds : []
  readonly property bool showIntro: root.round === null && root.promptKind !== ""
  readonly property string roundKey: root.round ? root.round.id : ""
  // A verb already in flight (see BarWidget.qml's pendingVerb queue) — every
  // button below that calls into hostWidget disables while true, so a fast
  // double-click can't fire the same grade/ack/start twice in a row.
  readonly property bool busy: !!(hostWidget && hostWidget.busy)

  // ---- round-local state ------------------------------------------------
  property string phase: "study"                 // study | blank | test | review
  property var clicks: []                         // [{x,y}] normalised to image content
  property var scoreResult: null                  // Model.scoreHits output
  property bool comparing: false                  // hold-to-see-original in review

  readonly property int changeCount: root.round && root.round.truth ? root.round.truth.length : 1

  onRoundKeyChanged: {
    root.phase = "study"
    root.clicks = []
    root.scoreResult = null
    root.comparing = false
    countdownFill.fraction = 1.0
    countdownAnim.duration = root.round ? Math.max(500, root.round.exposureMs) : 5000
    countdownAnim.restart()
  }

  function toTest() { root.phase = "test" }
  function toReview() {
    root.scoreResult = Model.scoreHits(root.round ? root.round.truth : [], root.clicks)
    root.phase = "review"
  }
  function submitTest() { if (root.clicks.length > 0) root.toReview() }

  function addClick(nx, ny) {
    if (root.phase !== "test") return
    if (root.clicks.length >= root.changeCount) return
    var next = root.clicks.slice()
    next.push({ x: nx, y: ny })
    root.clicks = next
    if (root.clicks.length >= root.changeCount) Qt.callLater(root.toReview)
  }

  function gradeRound(g) {
    if (!root.hostWidget || !root.scoreResult || root.busy) return
    var acc = Math.round(root.scoreResult.accuracy * 10000) / 10000
    root.hostWidget.finishRound(g, acc, JSON.stringify(root.clicks))
  }

  // ---- intro actions --------------------------------------------------
  function startFromIntro() {
    if (!root.hostWidget) return
    root.hostWidget.startScheduled(root.promptCardIds.length ? root.promptCardIds[0] : "")
  }
  function dismissIntro() { if (root.hostWidget) root.hostWidget.ackPrompt(root.promptKind, 0) }
  function snoozeIntro(min) { if (root.hostWidget) root.hostWidget.ackPrompt(root.promptKind, min) }
  function abandonRound() { if (root.hostWidget) root.hostWidget.abandonRound() }

  // ---- phase timers --------------------------------------------------
  Timer {
    id: studyTimer
    interval: root.round ? Math.max(500, root.round.exposureMs) : 5000
    running: root.round !== null && root.phase === "study"
    onTriggered: root.phase = "blank"
  }
  Timer {
    id: blankTimer
    interval: root.round ? Math.max(0, root.round.blankMs) : 600
    running: root.round !== null && root.phase === "blank"
    onTriggered: root.toTest()
  }

  PanelWindow {
    id: win
    visible: root.round !== null || root.promptKind !== ""
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omarchy-glimpse-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (root.takeover && root.showIntro) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: scrim
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, root.round !== null ? 0.97 : (root.takeover ? 0.9 : 0.55))
      focus: true

      Keys.onEscapePressed: {
        if (root.showIntro) {
          if (root.takeover) root.snoozeIntro(10)
          else root.dismissIntro()
          return
        }
        if (root.round !== null && root.phase !== "review") root.abandonRound()
      }
      Keys.onSpacePressed: if (root.phase === "review") root.comparing = true
      Keys.onReleased: function (e) { if (e.key === Qt.Key_Space) { root.comparing = false; e.accepted = true } }

      // ================= INTRO =================
      Rectangle {
        anchors.centerIn: parent
        visible: root.showIntro
        width: Math.min(parent.width - Style.space(80), Style.space(520))
        height: introCol.implicitHeight + Style.space(48)
        radius: Style.cornerRadius
        color: Color.bar.background
        border.width: 1
        border.color: root.takeover ? Kit.Palette.negative : Kit.Palette.info

        MouseArea { anchors.fill: parent }

        Column {
          id: introCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(24)
          spacing: Style.space(14)

          Text {
            width: parent.width
            text: root.takeover ? "Scene review — overdue" : "Scene review ready"
            color: Color.bar.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            width: parent.width
            text: "You'll get one look at a scene, then spot what changed in an altered copy. Under a minute."
            wrapMode: Text.WordWrap
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Flow {
            width: parent.width
            spacing: Style.space(8)
            Button {
              text: "Start"
              foreground: Color.bar.text
              bordered: true
              enabled: !root.busy
              onClicked: root.startFromIntro()
            }
            Button {
              visible: !root.takeover
              text: "Not now"
              foreground: Color.bar.text
              bordered: true
              enabled: !root.busy
              onClicked: root.dismissIntro()
            }
            Button {
              text: root.takeover ? "10 min" : "Snooze 1h"
              foreground: Color.bar.text
              bordered: true
              enabled: !root.busy
              onClicked: root.snoozeIntro(root.takeover ? 10 : 60)
            }
          }
        }
      }

      // ================= ROUND =================
      Item {
        id: stage
        anchors.fill: parent
        visible: root.round !== null

        readonly property bool showA: root.phase === "study" || (root.phase === "review" && root.comparing)
        readonly property bool showImage: root.phase === "study" || root.phase === "test" || root.phase === "review"

        Image {
          id: sceneImg
          anchors.fill: parent
          anchors.margins: Style.space(40)
          anchors.bottomMargin: Style.space(96)
          visible: stage.showImage
          source: root.round ? (stage.showA ? root.round.imageA : root.round.imageB) : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          cache: true
          smooth: true

          readonly property real offX: (width - paintedWidth) / 2
          readonly property real offY: (height - paintedHeight) / 2

          // ---- click capture (test phase) ----
          MouseArea {
            anchors.fill: parent
            enabled: root.phase === "test"
            cursorShape: root.phase === "test" ? Qt.CrossCursor : Qt.ArrowCursor
            onClicked: function (m) {
              var nx = (m.x - sceneImg.offX) / sceneImg.paintedWidth
              var ny = (m.y - sceneImg.offY) / sceneImg.paintedHeight
              if (nx < 0 || nx > 1 || ny < 0 || ny > 1) return
              root.addClick(nx, ny)
            }
          }

          // ---- user click markers ----
          Repeater {
            model: root.clicks
            Rectangle {
              required property var modelData
              required property int index
              readonly property bool hit: root.scoreResult && root.scoreResult.clickResults[index]
                ? root.scoreResult.clickResults[index].hit : false
              width: Style.space(24); height: width; radius: width / 2
              color: "transparent"
              border.width: 3
              border.color: root.phase === "review"
                ? (hit ? Kit.Palette.positive : Kit.Palette.negative)
                : Color.bar.text
              x: sceneImg.offX + modelData.x * sceneImg.paintedWidth - width / 2
              y: sceneImg.offY + modelData.y * sceneImg.paintedHeight - height / 2
              Text {
                anchors.centerIn: parent
                visible: root.phase === "review"
                text: parent.hit ? "✓" : "✕"
                color: parent.border.color
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
          }

          // ---- truth rectangles (review phase) ----
          Repeater {
            model: root.phase === "review" && root.round ? root.round.truth : []
            Rectangle {
              required property var modelData
              color: "transparent"
              border.width: 2
              border.color: Kit.Palette.info
              radius: Style.cornerRadius
              x: sceneImg.offX + modelData.x * sceneImg.paintedWidth
              y: sceneImg.offY + modelData.y * sceneImg.paintedHeight
              width: Math.max(Style.space(18), modelData.w * sceneImg.paintedWidth)
              height: Math.max(Style.space(18), modelData.h * sceneImg.paintedHeight)
            }
          }
        }

        // ---- blank gap ----
        Rectangle {
          anchors.fill: parent
          visible: root.phase === "blank"
          color: Qt.rgba(0.5, 0.5, 0.5, 1)
        }

        // ---- study countdown bar ----
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(40)
          height: Style.space(4)
          radius: 2
          visible: root.phase === "study"
          color: Util.alpha(Color.bar.text, 0.15)

          Rectangle {
            id: countdownFill
            property real fraction: 1.0
            height: parent.height
            radius: parent.radius
            color: Kit.Palette.info
            width: parent.width * fraction
            NumberAnimation {
              id: countdownAnim
              target: countdownFill
              property: "fraction"
              to: 0.0
              easing.type: Easing.Linear
            }
          }
        }

        // ---- instruction / result strip ----
        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(28)
          spacing: Style.space(10)

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            color: Color.bar.text
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            text: {
              if (root.phase === "study") return "Look closely…"
              if (root.phase === "blank") return ""
              if (root.phase === "test") return "Click the " + root.changeCount + " spot" + (root.changeCount > 1 ? "s" : "") + " that changed  (" + root.clicks.length + "/" + root.changeCount + ")"
              if (root.scoreResult) return "You found " + root.scoreResult.hits + " of " + root.scoreResult.total + "  ·  " + Model.formatPct(root.scoreResult.accuracy)
              return ""
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(8)
            visible: root.phase === "test" || root.phase === "review"

            Button {
              visible: root.phase === "test"
              text: "Submit"
              foreground: Color.bar.text
              bordered: true
              enabled: root.clicks.length > 0
              onClicked: root.submitTest()
            }
            Button {
              visible: root.phase === "test"
              text: "Nothing else"
              foreground: Kit.Palette.faint
              bordered: true
              onClicked: root.toReview()
            }

            Rectangle {
              visible: root.phase === "review"
              width: cmpLabel.implicitWidth + Style.space(20)
              height: Style.space(28)
              radius: Style.cornerRadius
              color: root.comparing
                ? Util.alpha(Kit.Palette.info, 0.25)
                : Util.alpha(Color.bar.text, 0.08)
              Text {
                id: cmpLabel
                anchors.centerIn: parent
                text: "Hold to see original"
                color: Color.bar.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea {
                anchors.fill: parent
                onPressed: root.comparing = true
                onReleased: root.comparing = false
                onCanceled: root.comparing = false
              }
            }

            Button {
              visible: root.phase === "review"
              text: "Again"
              foreground: root.scoreResult && root.scoreResult.grade === "again" ? Kit.Palette.negative : Color.bar.text
              bordered: true
              enabled: !root.busy
              onClicked: root.gradeRound("again")
            }
            Button {
              visible: root.phase === "review"
              text: "Hard"
              foreground: root.scoreResult && root.scoreResult.grade === "hard" ? Kit.Palette.warning : Color.bar.text
              bordered: true
              enabled: !root.busy
              onClicked: root.gradeRound("hard")
            }
            Button {
              visible: root.phase === "review"
              text: "Good"
              foreground: root.scoreResult && root.scoreResult.grade === "good" ? Kit.Palette.info : Color.bar.text
              bordered: true
              enabled: !root.busy
              onClicked: root.gradeRound("good")
            }
            Button {
              visible: root.phase === "review"
              text: "Easy"
              foreground: root.scoreResult && root.scoreResult.grade === "easy" ? Kit.Palette.positive : Color.bar.text
              bordered: true
              enabled: !root.busy
              onClicked: root.gradeRound("easy")
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.phase === "study" || root.phase === "test"
            text: root.phase === "study" ? "Esc to cancel" : "Blue boxes will show the real changes after you submit"
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
