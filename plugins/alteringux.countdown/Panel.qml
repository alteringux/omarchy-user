import QtQuick
import "../shared"
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Overlay for the countdown plugin: an inline month calendar to pick the
// event's date (today and every past day are disabled), a "what's it for"
// field, one-tap chips for labels you've counted down to before, then a
// soonest-first list of cards — each with the label, its big days-remaining
// figure (click it to toggle exact minutes remaining; amber inside 3 days,
// dimmed once past), the target date, and a × to delete it. Same shape as the
// alteringux.timers overlay.
Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.countdown"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  // How many card labels are currently being edited in place. While > 0 the
  // panel forwards keystrokes to the field (Esc to cancel especially) instead
  // of treating them as panel shortcuts. See docs/adr/0003.
  property int inlineEditors: 0

  // "soon" tint — the shared warning amber (alteringux.timers' "running
  // long" colour lives here too now: Kit.Palette.warning, not a re-hardcoded hex).
  readonly property color soonColor: _webPalette.warning

  // Month the calendar is showing, and the day picked in it ("" = none yet).
  property int viewYear: (new Date()).getFullYear()
  property int viewMonth: (new Date()).getMonth()
  property string selectedKey: ""

  // Monday-start single-letter weekday headers.
  readonly property var weekdayLetters: ["M", "T", "W", "T", "F", "S", "S"]
  readonly property int calGap: 4

  readonly property double nowMs: hostWidget ? hostWidget.nowMs : Date.now()
  readonly property string todayKey: Model.todayKey(root.nowMs)
  readonly property bool canGoPrev: !Model.isCurrentOrPastMonth(root.viewYear, root.viewMonth, root.nowMs)
  readonly property real selectedEpoch: root.selectedKey === "" ? 0 : Model.epochForKey(root.selectedKey)
  readonly property bool hasValidSelection: root.selectedKey !== "" && Model.isFutureKey(root.selectedKey, root.nowMs)

  readonly property var guard: Kit.BugGuard.create("alteringux.countdown", function(argv) { Quickshell.execDetached(argv) })

  readonly property var entries: hostWidget ? hostWidget.entries : []
  readonly property var added: hostWidget ? hostWidget.added : []
  readonly property var sorted: Model.sortedBySoonest(root.entries)
  readonly property var chips: Model.rankLabels(root.added, root.entries, 4)

  property int submittedGeneration: -1
  property string submittedText: ""
  property string submittedKey: ""
  readonly property bool submissionPending: hostWidget && hostWidget.actionPending && submittedGeneration === hostWidget.actionGeneration

  Connections {
    target: root.hostWidget
    ignoreUnknownSignals: true
    function onActionFeedback(message, generation, success) {
      if (generation === root.submittedGeneration) {
        if (success && labelField.text === root.submittedText && root.selectedKey === root.submittedKey) {
          labelField.text = ""
          root.selectedKey = ""
        }
        root.submittedGeneration = -1
      }
      if (root.opened && feedbackText.visible) feedbackText.Accessible.announce(message)
    }
  }

  // Snap the calendar back to the current month and clear the pick each time
  // the overlay opens, so a stale month view from days ago can't linger.
  onOpenedChanged: if (opened) resetView()

  function resetView() {
    var d = new Date(root.nowMs)
    root.viewYear = d.getFullYear()
    root.viewMonth = d.getMonth()
    root.selectedKey = ""
  }

  function shiftMonth(delta) {
    guard.run("shiftMonth", function() {
      if (delta < 0 && !root.canGoPrev) return
      var m = Model.stepMonth(root.viewYear, root.viewMonth, delta)
      root.viewYear = m.year
      root.viewMonth = m.month
    })
  }

  // Shared by the label field's Enter key, the panel-level Enter shortcut, and
  // the Add button — one "add" path.
  function submit() {
    guard.run("submit", function() {
      if (!hostWidget || root.submissionPending) return
      var text = labelField.text
      if (!text || text.trim().length === 0) return
      if (!root.hasValidSelection) return
      root.submittedText = text
      root.submittedKey = root.selectedKey
      root.submittedGeneration = hostWidget.addEntryAt(text, root.selectedEpoch)
      labelField.forceActiveFocus()
    })
  }

  // A chip prefills the label and jumps the calendar to (and selects) the
  // date its remembered day count lands on.
  function applyChip(chip) {
    guard.run("applyChip", function() {
      var days = chip.days && chip.days >= 1 ? chip.days : 7
      var target = Model.targetEpochFor(days, root.nowMs)
      root.selectedKey = Model.keyForEpoch(target)
      var d = new Date(target)
      root.viewYear = d.getFullYear()
      root.viewMonth = d.getMonth()
      labelField.text = chip.label
      labelField.forceActiveFocus()
    })
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(560)))
    focusTarget: labelField

    Kit.PanelKeys {
      anchors.fill: parent
      // While the label field is focused, or a card label is being edited in
      // place, let every keystroke (space, x, hjkl, Esc) reach the field
      // instead of being intercepted as a panel shortcut.
      blocked: labelField.activeFocus || root.inlineEditors > 0

      onCloseRequested: root.close()
      onActivateRequested: root.submit()
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Add a countdown from the current input", context: "Countdown · shortcut focus" }
      ]

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: content.implicitHeight

        Column {
          id: content
          width: parent.width
          spacing: Style.spacing.panelGap

          Kit.PanelHead {
            glyph: "\uf073"   // nf-fa-calendar — matches the bar widget
            title: "Countdowns"
            meta: root.entries.length > 0
              ? (root.entries.length + (root.entries.length === 1 ? " countdown" : " countdowns"))
              : "none set"
            foreground: root.barForeground
          }

          Text {
            id: feedbackText
            width: parent.width
            text: root.hostWidget ? root.hostWidget.actionStatus : ""
            visible: text.length > 0
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          // ---- date picker -------------------------------------------
          readonly property real calCellW: Math.floor((content.width - root.calGap * 6) / 7)
          readonly property real calCellH: Style.space(26)

          Column {
            width: content.width
            spacing: Style.space(4)

            // Month nav header
            Item {
              width: parent.width
              height: prevBtn.implicitHeight

              Kit.ActionButton {
                focusable: true
                Accessible.role: Accessible.Button
                Accessible.name: "Previous month"
                id: prevBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                foreground: root.barForeground
                bordered: true
                enabled: root.canGoPrev
                onClicked: root.shiftMonth(-1)
              }
              Text {
                anchors.centerIn: parent
                text: Model.monthLabel(root.viewYear, root.viewMonth)
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Kit.ActionButton {
                focusable: true
                Accessible.role: Accessible.Button
                Accessible.name: "Next month"
                id: nextBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                foreground: root.barForeground
                bordered: true
                onClicked: root.shiftMonth(1)
              }
            }

            // Weekday letters
            Row {
              spacing: root.calGap
              Repeater {
                model: root.weekdayLetters
                delegate: Text {
                  required property var modelData
                  width: content.calCellW
                  horizontalAlignment: Text.AlignHCenter
                  text: modelData
                  color: root.barForeground
                  opacity: 0.45
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            // 6 week rows
            Repeater {
              model: Model.monthGrid(root.viewYear, root.viewMonth, 1)
              delegate: Row {
                id: weekRow
                required property var modelData
                spacing: root.calGap

                Repeater {
                  model: weekRow.modelData
                  delegate: Rectangle {
                    id: cell
                    required property var modelData
                    readonly property bool future: Model.isFutureKey(modelData.key, root.nowMs)
                    readonly property bool selected: modelData.key === root.selectedKey
                    readonly property bool isToday: modelData.key === root.todayKey

                    width: content.calCellW
                    height: content.calCellH
                    radius: Style.cornerRadius
                    activeFocusOnTab: cell.future
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: "Select " + Qt.formatDate(
                      new Date(cell.modelData.year, cell.modelData.month, cell.modelData.day), "dddd, MMMM d, yyyy")
                    Accessible.checkable: true
                    Accessible.checked: cell.selected
                    Accessible.description: (cell.isToday ? "Today. " : "")
                      + (!cell.future ? "Past dates are unavailable for countdowns." : "")
                    Accessible.onPressAction: activate()
                    color: cell.selected ? Util.alpha(_webPalette.accent, 0.9)
                          : (cellMouse.containsMouse && cell.future ? Util.alpha(root.barForeground, 0.12)
                          : "transparent")
                    border.width: activeFocus || (cell.isToday && !cell.selected) ? Style.spacing.hairline : 0
                    border.color: activeFocus ? _webPalette.accent : Util.alpha(root.barForeground, 0.35)

                    function activate() { if (cell.future) root.selectedKey = cell.modelData.key }
                    Keys.onReturnPressed: activate()
                    Keys.onEnterPressed: activate()
                    Keys.onSpacePressed: activate()

                    Text {
                      anchors.centerIn: parent
                      text: cell.modelData.day
                      color: cell.selected ? _webPalette.background : root.barForeground
                      opacity: cell.selected ? 1
                        : (!cell.modelData.inMonth ? 0.22
                        : (cell.future ? 0.95 : 0.3))
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      font.bold: cell.selected || cell.isToday
                    }

                    MouseArea {
                      id: cellMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      enabled: cell.future
                      cursorShape: Qt.PointingHandCursor
                      onClicked: { cell.forceActiveFocus(); cell.activate() }
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              text: root.selectedKey === ""
                ? "Pick a future date"
                : Model.formatTarget(root.selectedEpoch) + "  ·  "
                  + Model.formatRemaining(Model.daysRemaining(root.selectedEpoch, root.nowMs))
              color: root.hasValidSelection ? _webPalette.accent : root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: root.hasValidSelection
            }
          }

          // ---- label + add -----------------------------------------
          Row {
            width: content.width
            spacing: Style.space(8)

            TextField {
              id: labelField
              width: parent.width - addButton.implicitWidth - parent.spacing
              placeholderText: "What are you counting down to?"
              foreground: root.barForeground
              onAccepted: root.submit()
            }
            Kit.ActionButton {
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: text
              id: addButton
              text: "Add"
              foreground: root.barForeground
              bordered: true
              enabled: labelField.text.trim().length > 0 && root.hasValidSelection && !root.submissionPending
              onClicked: root.submit()
            }
          }

          // ---- your usual labels ----------------------------------
          // One bordered pill per remembered label: tap the label to prefill
          // the form, tap its × to forget just that label. The label text
          // tail-elides with "…" so a long one can't overflow the panel edge.
          Flow {
            width: content.width
            spacing: Style.space(6)
            visible: root.chips.length > 0

            Repeater {
              model: root.chips
              delegate: Rectangle {
                id: chip
                required property var modelData
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Use remembered countdown " + chip.fullText
                Accessible.onPressAction: root.applyChip(chip.modelData)
                readonly property string fullText: modelData.label
                  + (modelData.days >= 1 ? ("  " + modelData.days + "d") : "")

                width: chipRow.implicitWidth + Style.space(16)
                height: chipRow.implicitHeight + Style.space(8)
                radius: Style.cornerRadius
                color: chipMouse.containsMouse ? Util.alpha(root.barForeground, 0.10) : "transparent"
                border.width: 1
                border.color: activeFocus ? _webPalette.accent : Util.alpha(root.barForeground, 0.25)

                Keys.onReturnPressed: root.applyChip(chip.modelData)

                Keys.onEnterPressed: root.applyChip(chip.modelData)
                Keys.onSpacePressed: root.applyChip(chip.modelData)

                // Prefill from the label. Sits below the × handler in the
                // stack, so clicks on the × don't reach this.
                MouseArea {
                  id: chipMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { chip.forceActiveFocus(); root.applyChip(chip.modelData) }
                }

                Row {
                  id: chipRow
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  MarqueeText {
                    text: chip.fullText
                    width: content.width - Style.space(48)
                    color: root.barForeground
                    textFont.family: Style.font.family
                    textFont.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: forgetChipAction
                    text: "×"
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Forget countdown label " + chip.modelData.label
                    Accessible.onPressAction: activate()
                    color: activeFocus ? _webPalette.accent : root.barForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.underline: activeFocus
                    anchors.verticalCenter: parent.verticalCenter

                    function activate() { if (hostWidget) hostWidget.forgetLabel(chip.modelData.label) }
                    Keys.onReturnPressed: activate()
                    Keys.onEnterPressed: activate()
                    Keys.onSpacePressed: activate()

                    MouseArea {
                      id: forgetMouse
                      anchors.fill: parent
                      anchors.margins: -4
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: { forgetChipAction.forceActiveFocus(); forgetChipAction.activate() }
                    }
                  }
                }
              }
            }
          }

          // ---- countdown list ------------------------------------
          Kit.EmptyState {
            visible: root.entries.length === 0
            text: "No countdowns yet."
            hint: "Pick a future date above, or type what you're counting down to."
            foreground: root.barForeground
          }

          Repeater {
            model: root.sorted
            delegate: Rectangle {
              id: card
              required property var modelData
              readonly property int daysLeft: Model.daysRemaining(modelData.targetEpoch, root.nowMs)
              property bool showingMinutes: false
              readonly property bool soon: daysLeft >= 0 && daysLeft <= 3
              readonly property bool past: daysLeft < 0

              width: content.width
              height: cardCol.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              clip: true
              color: Util.alpha(root.barForeground, card.past ? 0.03 : 0.05)
              border.width: 1
              border.color: card.soon ? Util.alpha(root.soonColor, 0.55)
                                      : _webPalette.cardBorderFor(root.barForeground)

              Text {
                id: removeCountdownAction
                text: "×"
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Remove countdown " + card.modelData.label
                Accessible.onPressAction: activate()
                color: activeFocus ? _webPalette.accent : root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.underline: activeFocus
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.space(8)

                function activate() { if (hostWidget) hostWidget.removeEntry(card.modelData.id) }
                Keys.onReturnPressed: activate()
                Keys.onEnterPressed: activate()
                Keys.onSpacePressed: activate()

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -6
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { removeCountdownAction.forceActiveFocus(); removeCountdownAction.activate() }
                }
              }

              Column {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(10)
                anchors.rightMargin: Style.space(28)
                spacing: Style.space(4)

                Kit.InlineEdit {
                  width: parent.width
                  text: card.modelData.label
                  foreground: card.past ? _webPalette.muted : root.barForeground
                  pixelSize: Style.font.body
                  bold: true
                  placeholderText: "What are you counting down to?"
                  onEditingChanged: root.inlineEditors += editing ? 1 : -1
                  onAccepted: function(value) {
                    if (hostWidget) hostWidget.renameEntry(card.modelData.id, value)
                  }
                }
                Item {
                  width: parent.width
                  height: remainingText.implicitHeight

                  Text {
                    id: remainingText
                    width: parent.width
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: card.showingMinutes
                      ? "Show days remaining for " + card.modelData.label
                      : "Show minutes remaining for " + card.modelData.label
                    Accessible.onPressAction: activate()
                    text: card.showingMinutes
                      ? Model.formatMinutesRemaining(
                          Model.minutesRemaining(modelData.targetEpoch, root.nowMs))
                      : Model.formatRemaining(card.daysLeft)
                    color: activeFocus ? _webPalette.accent : card.soon ? root.soonColor : (card.past ? root.barForeground : _webPalette.accent)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.heading
                    font.bold: true
                    font.underline: activeFocus

                    function activate() { card.showingMinutes = !card.showingMinutes }
                    Keys.onReturnPressed: activate()
                    Keys.onEnterPressed: activate()
                    Keys.onSpacePressed: activate()
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { remainingText.forceActiveFocus(); remainingText.activate() }
                  }
                }
                Text {
                  text: Model.formatTarget(modelData.targetEpoch)
                  color: _webPalette.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          PanelSeparator {}

          Text {
            text: "Enter: add  ·  Esc: close"
            color: _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
