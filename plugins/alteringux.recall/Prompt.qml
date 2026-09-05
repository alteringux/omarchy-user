import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// The intrusion surface. One window, three shapes, chosen by the daemon:
//   lesson    — the whole screen, a short paginated technique lesson, no
//               skip (you read it — that's the "teach" half of the loop).
//   checkin   — a centred card over a light scrim, dismissable, one due
//               card at a time: front, reveal, self-grade.
//   takeover  — the whole screen, near-opaque, EXCLUSIVE keyboard focus,
//               same review flow as checkin but can't be Alt-Tabbed past.
//
// It renders straight from the host widget's watched stores and turns every
// button into an omarchy-recall verb via the host. It never writes state
// itself.
Item {
  id: root

  property var hostWidget: null

  readonly property string mode: hostWidget ? hostWidget.promptKind : ""
  readonly property bool takeover: mode === "takeover"
  readonly property bool isLesson: mode === "lesson"
  readonly property var cardsValue: hostWidget ? hostWidget.cardsValue : Model.defaultCards()
  readonly property var promptCardIds: (hostWidget && hostWidget.stateValue.prompt) ? hostWidget.stateValue.prompt.cardIds : []
  readonly property string promptKey: root.mode + ":" + root.promptCardIds.join(",")

  function findCard(id) { return Model.findCard(root.cardsValue.cards, id) }

  // ---- lesson state -----------------------------------------------------
  property int slideIndex: 0
  readonly property var lessonCard: root.isLesson && root.promptCardIds.length ? root.findCard(root.promptCardIds[0]) : null
  readonly property int slideCount: root.lessonCard && root.lessonCard.slides ? root.lessonCard.slides.length : 0
  readonly property bool lastSlide: root.slideIndex >= root.slideCount - 1

  function finishLesson() {
    if (!root.hostWidget || !root.lessonCard) return
    root.hostWidget.lessonSeen(root.lessonCard.id)
    root.hostWidget.ackLesson()
  }
  function nextSlide() {
    if (root.lastSlide) root.finishLesson()
    else root.slideIndex += 1
  }

  // ---- review state (checkin / takeover) --------------------------------
  property int reviewIndex: 0
  property int gradedCount: 0
  property bool revealed: false
  readonly property var reviewCard: (!root.isLesson && root.reviewIndex < root.promptCardIds.length)
    ? root.findCard(root.promptCardIds[root.reviewIndex]) : null
  readonly property bool reviewDone: !root.isLesson && root.promptCardIds.length > 0 && root.reviewIndex >= root.promptCardIds.length

  onPromptKeyChanged: {
    root.slideIndex = 0
    root.reviewIndex = 0
    root.gradedCount = 0
    root.revealed = false
  }

  function reveal() { root.revealed = true }
  function gradeCurrent(g) {
    if (!root.hostWidget || !root.reviewCard) return
    root.hostWidget.gradeCard(root.reviewCard.id, g)
    root.gradedCount += 1
    root.reviewIndex += 1
    root.revealed = false
  }
  function finishReview(engaged) {
    if (!root.hostWidget) return
    root.hostWidget.ackReview(root.mode, engaged || root.gradedCount > 0)
  }
  function skipReview() { root.finishReview(root.gradedCount > 0) }
  function snoozeReview(minutes) { if (root.hostWidget) root.hostWidget.ackSnooze(root.mode, minutes) }

  PanelWindow {
    id: win
    visible: root.mode !== ""
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omarchy-recall-prompt"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.takeover ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, root.takeover ? 0.92 : (root.isLesson ? 0.85 : 0.45))

      // A lesson has no click-to-dismiss — you read it. A check-in's scrim
      // click is a soft "not now"; a takeover ignores it (use a button).
      MouseArea {
        anchors.fill: parent
        enabled: !root.takeover && !root.isLesson
        onClicked: root.skipReview()
      }

      Keys.onEscapePressed: {
        if (root.isLesson) return
        if (root.takeover) root.snoozeReview(10)
        else root.skipReview()
      }
      focus: true

      Rectangle {
        id: card
        anchors.centerIn: parent
        width: (root.takeover || root.isLesson)
          ? Math.min(parent.width - Style.space(120), Style.space(720))
          : Math.min(parent.width - Style.space(60), Style.space(460))
        height: Math.min(parent.height - Style.space(60), cardCol.implicitHeight + Style.space(48))
        radius: Style.cornerRadius
        color: Color.bar.background
        border.width: 1
        border.color: root.takeover
          ? Kit.Palette.negative
          : (root.isLesson ? Kit.Palette.info : Qt.rgba(Color.bar.text.r, Color.bar.text.g, Color.bar.text.b, 0.25))

        MouseArea { anchors.fill: parent }   // swallow clicks so the scrim handler doesn't fire

        Column {
          id: cardCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(24)
          spacing: Style.space(14)

          // ---- lesson view ---------------------------------------------
          Column {
            width: parent.width
            visible: root.isLesson
            spacing: Style.space(12)

            Text {
              width: parent.width
              text: root.lessonCard ? root.lessonCard.title : ""
              wrapMode: Text.WordWrap
              color: Color.bar.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              visible: root.slideCount > 0
              text: "Technique lesson · slide " + (root.slideIndex + 1) + " of " + root.slideCount
              color: Kit.Palette.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width
              text: (root.lessonCard && root.lessonCard.slides && root.lessonCard.slides.length > root.slideIndex)
                ? root.lessonCard.slides[root.slideIndex] : ""
              wrapMode: Text.WordWrap
              color: Color.bar.text
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
            }
            Row {
              width: parent.width
              spacing: Style.space(8)
              Button {
                text: root.lastSlide ? "Got it" : "Next"
                foreground: Color.bar.text
                bordered: true
                onClicked: root.nextSlide()
              }
            }
            Text {
              width: parent.width
              text: "You'll be quizzed on this tomorrow — that's the point."
              color: Kit.Palette.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          // ---- review view (checkin / takeover) --------------------------
          Column {
            width: parent.width
            visible: !root.isLesson
            spacing: Style.space(14)

            Text {
              width: parent.width
              text: root.takeover ? "Deal with this." : "Quick review"
              color: Color.bar.text
              font.family: Style.font.family
              font.pixelSize: root.takeover ? Style.font.title : Style.font.heading
              font.bold: true
            }
            Text {
              width: parent.width
              visible: root.promptCardIds.length > 0
              text: "Card " + Math.min(root.reviewIndex + 1, root.promptCardIds.length) + " of " + root.promptCardIds.length
              color: Kit.Palette.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              visible: root.reviewCard !== null
              text: root.reviewCard ? root.reviewCard.front : ""
              wrapMode: Text.WordWrap
              color: Color.bar.text
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
            }
            Text {
              width: parent.width
              visible: root.reviewCard !== null && root.revealed
              text: root.reviewCard ? root.reviewCard.back : ""
              wrapMode: Text.WordWrap
              color: Kit.Palette.info
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Text {
              width: parent.width
              visible: root.reviewDone
              text: "All caught up — nicely done."
              color: Kit.Palette.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Flow {
              width: parent.width
              spacing: Style.space(8)

              Button {
                visible: root.reviewCard !== null && !root.revealed
                text: "Reveal"
                foreground: Color.bar.text
                bordered: true
                onClicked: root.reveal()
              }
              Button {
                visible: root.reviewCard !== null && root.revealed
                text: "Again"
                foreground: Kit.Palette.negative
                bordered: true
                onClicked: root.gradeCurrent("again")
              }
              Button {
                visible: root.reviewCard !== null && root.revealed
                text: "Hard"
                foreground: Color.bar.text
                bordered: true
                onClicked: root.gradeCurrent("hard")
              }
              Button {
                visible: root.reviewCard !== null && root.revealed
                text: "Good"
                foreground: Color.bar.text
                bordered: true
                onClicked: root.gradeCurrent("good")
              }
              Button {
                visible: root.reviewCard !== null && root.revealed
                text: "Easy"
                foreground: Kit.Palette.positive
                bordered: true
                onClicked: root.gradeCurrent("easy")
              }
            }

            Flow {
              width: parent.width
              spacing: Style.space(8)

              Button {
                visible: !root.takeover && root.reviewCard !== null
                text: "Not now"
                foreground: Color.bar.text
                bordered: true
                onClicked: root.skipReview()
              }
              Button {
                visible: !root.takeover && root.reviewCard !== null
                text: "15 min"
                foreground: Color.bar.text
                bordered: true
                onClicked: root.snoozeReview(15)
              }
              Button {
                visible: root.takeover && root.reviewCard !== null
                text: "I hear you — 10 min"
                foreground: Color.bar.text
                bordered: true
                onClicked: root.snoozeReview(10)
              }
              Button {
                visible: root.reviewDone
                text: "Close"
                foreground: Color.bar.text
                bordered: true
                onClicked: root.finishReview(true)
              }
            }
          }
        }
      }
    }
  }
}
