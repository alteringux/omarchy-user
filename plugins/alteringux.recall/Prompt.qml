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
  // Slide position is persisted (hostWidget.stateValue.prompt.slideIndex) so
  // a shell restart resumes an in-progress lesson instead of restarting it
  // at slide 1. That initializer only matters at component creation --
  // nextSlide() below owns slideIndex as plain local state from then on and
  // pushes each step back to disk.
  property int slideIndex: (hostWidget && hostWidget.stateValue.prompt && typeof hostWidget.stateValue.prompt.slideIndex === "number")
    ? hostWidget.stateValue.prompt.slideIndex : 0
  readonly property var lessonCard: root.isLesson && root.promptCardIds.length ? root.findCard(root.promptCardIds[0]) : null
  readonly property int slideCount: root.lessonCard && root.lessonCard.slides ? root.lessonCard.slides.length : 0
  readonly property bool lastSlide: root.slideIndex >= root.slideCount - 1

  function finishLesson() {
    if (!root.hostWidget) return
    if (root.lessonCard) root.hostWidget.lessonSeen(root.lessonCard.id)
    // A stale or malformed lesson prompt must still be dismissible.
    root.hostWidget.ackLesson()
  }
  function nextSlide() {
    if (root.lastSlide) { root.finishLesson(); return }
    root.slideIndex += 1
    if (root.hostWidget) root.hostWidget.setLessonSlide(root.slideIndex)
  }

  // ---- review state (checkin / takeover) --------------------------------
  // No local cursor into promptCardIds: the "current card" is always the
  // first of promptCardIds that's still due right now. Grading persists to
  // recall-cards.json and pushes the card's dueAt forward -- even "Again"
  // goes 10 minutes out -- so a graded card drops out of this list on its
  // own. That makes review resumable across a shell restart for free, with
  // no separate progress counter to lose.
  property bool revealed: false
  property double nowMs: Date.now()
  Timer { interval: 10000; repeat: true; running: root.mode !== "" && !root.isLesson; onTriggered: root.nowMs = Date.now() }

  readonly property var remainingIds: root.promptCardIds.filter(function (id) {
    var c = root.findCard(id)
    return c !== null && c.dueAt <= root.nowMs
  })
  readonly property var reviewCard: (!root.isLesson && root.remainingIds.length) ? root.findCard(root.remainingIds[0]) : null
  readonly property int gradedCount: root.promptCardIds.length - root.remainingIds.length
  readonly property bool reviewDone: !root.isLesson && root.remainingIds.length === 0

  // ---- multiple-choice clue, for when you need a nudge before Reveal ----
  property bool clueLoading: false
  property var clueOptions: []
  readonly property bool clueShown: root.clueOptions.length > 0

  function requestClue() {
    if (!root.hostWidget || !root.reviewCard || root.clueLoading || root.clueShown) return
    root.clueLoading = true
    root.hostWidget.fetchChoices(root.reviewCard.id)
  }
  function pickClue(text) {
    root.revealed = true   // picking an option settles it either way — show the real answer
  }
  Connections {
    target: root.hostWidget
    function onLastChoicesChanged() {
      if (!root.hostWidget || !root.reviewCard) return
      if (root.hostWidget.lastChoicesForId !== root.reviewCard.id) return
      root.clueOptions = root.hostWidget.lastChoices
      root.clueLoading = false
    }
  }

  function resetCardUi() {
    root.revealed = false
    root.clueOptions = []
    root.clueLoading = false
  }

  // Same instance, new prompt (e.g. one checkin ends and another begins
  // without the component being destroyed): reset the lesson cursor. A
  // fresh component creation after a shell restart does NOT fire this (QML
  // doesn't fire onXChanged for the initial value), so the persisted
  // slideIndex above survives untouched.
  onPromptKeyChanged: root.slideIndex = 0

  readonly property string currentCardId: root.reviewCard ? root.reviewCard.id : ""
  onCurrentCardIdChanged: root.resetCardUi()

  function reveal() { root.revealed = true }
  function gradeCurrent(g) {
    if (!root.hostWidget || !root.reviewCard) return
    root.hostWidget.gradeCard(root.reviewCard.id, g)
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
              text: root.lessonCard ? root.lessonCard.title : "Lesson unavailable"
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
                ? root.lessonCard.slides[root.slideIndex] : "This lesson is no longer available."
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
              text: "Card " + Math.min(root.gradedCount + 1, root.promptCardIds.length) + " of " + root.promptCardIds.length
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

            // ---- multiple-choice clue --------------------------------
            Text {
              width: parent.width
              visible: root.clueLoading
              text: "Fetching a clue…"
              color: Kit.Palette.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Column {
              width: parent.width
              visible: root.clueShown && !root.revealed
              spacing: Style.space(6)

              Repeater {
                model: root.clueOptions

                Rectangle {
                  id: clueRow
                  required property string modelData
                  width: parent.width
                  height: Style.space(30)
                  radius: Style.cornerRadius
                  color: clueHover.containsMouse
                    ? Qt.rgba(Color.bar.text.r, Color.bar.text.g, Color.bar.text.b, 0.12)
                    : Qt.rgba(Color.bar.text.r, Color.bar.text.g, Color.bar.text.b, 0.06)

                  Text {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    verticalAlignment: Text.AlignVCenter
                    text: clueRow.modelData
                    elide: Text.ElideRight
                    color: Color.bar.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                  MouseArea {
                    id: clueHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickClue(clueRow.modelData)
                  }
                }
              }
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
                visible: root.reviewCard !== null && !root.revealed && !root.clueShown && !root.clueLoading
                text: "Clue"
                foreground: Kit.Palette.info
                bordered: true
                onClicked: root.requestClue()
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
