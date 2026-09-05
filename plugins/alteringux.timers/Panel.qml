import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Overlay for the timers plugin: one-tap chips for your most-used labels, a
// "what are you starting?" input, then a newest-first list of cards — each
// with the label, its live count-up elapsed time (amber once it passes that
// label's typical run time), and a × to remove it permanently.
Panel {
  id: root
  moduleName: "alteringux.timers"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  // "running long" tint — a warning amber, not urgent red. From Kit.Palette
  // now (the shell theme palette still has no dedicated warning role).
  readonly property color longColor: Kit.Palette.warning

  // How many card labels are being edited in place. While > 0 the panel
  // forwards keystrokes to the field (Esc to cancel especially). See
  // docs/adr/0003.
  property int inlineEditors: 0

  readonly property var guard: Kit.BugGuard.create("alteringux.timers", function(argv) { Quickshell.execDetached(argv) })

  readonly property var entries: hostWidget ? hostWidget.entries : []
  readonly property var completed: hostWidget ? hostWidget.completed : []
  // Adaptive: a chip-heavy user gets a longer row (see BarWidget).
  readonly property int chipLimit: hostWidget ? hostWidget.adaptiveChipLimit : 4
  // Most-used past labels that aren't already running — one-tap re-add.
  readonly property var chips: Model.rankLabels(root.completed, root.entries, root.chipLimit)
  // Footer summary: total running + done-today.
  readonly property string totalsText: hostWidget ? hostWidget.totalsText : ""
  // Ticks off the bar widget's 1s timer so every elapsed binding below
  // re-evaluates while the panel is open.
  readonly property double nowMs: hostWidget ? hostWidget.nowMs : Date.now()

  function submit() {
    guard.run("submit", function() {
      if (!hostWidget) return
      var text = addField.text
      if (!text || text.trim().length === 0) return
      hostWidget.addEntry(text)
      addField.text = ""
      addField.forceActiveFocus()
    })
  }

  // Full humanised creation stamp, shown when the elapsed line is clicked,
  // e.g. "Sunday, 31 August 2026 · 6:56 pm". Uses the running shell's locale
  // and timezone via Qt — the one bit of card text not covered by Model.js
  // unit tests (it's a thin Qt.formatDateTime call).
  function formatCreatedAt(ms) {
    return guard.call("formatCreatedAt", function() {
      return Qt.formatDateTime(new Date(ms), "dddd, d MMMM yyyy · h:mm ap")
    }, "")
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(520)))
    focusTarget: addField

    PanelKeyCatcher {
      anchors.fill: parent
      // While the input is focused, or a card label is being edited in place,
      // let every keystroke (space, x, hjkl, Esc) reach the field instead of
      // being intercepted as a panel shortcut.
      blocked: addField.activeFocus || root.inlineEditors > 0

      onCloseRequested: root.close()
      onActivateRequested: root.submit()

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: content.implicitHeight

        Column {
          id: content
          width: parent.width
          spacing: Style.spacing.panelGap

          Kit.PanelHead {
            glyph: "\uf252"   // nf-fa-hourglass_half, matches the bar widget
            title: "Timers"
            meta: root.entries.length > 0 ? (root.entries.length + " running") : "idle"
            foreground: root.barForeground
          }

// One bordered pill per remembered label (freq + recency ranked, from
  // the rolling completion log): tap the label to start a timer, tap its
  // × to forget just that label. The label text tail-elides with '…' so a
  // long one can't overflow the panel edge. Hidden until there's history
  // to rank.
  Flow {
    width: content.width
    spacing: Style.space(6)
    visible: root.chips.length > 0

    Repeater {
      model: root.chips
      delegate: Rectangle {
        id: chip
        required property var modelData
        readonly property string fullText: modelData

        width: chipRow.implicitWidth + Style.space(16)
        height: chipRow.implicitHeight + Style.space(8)
        radius: Style.cornerRadius
        color: chipMouse.containsMouse ? Util.alpha(root.barForeground, 0.10) : "transparent"
        border.width: 1
        border.color: Util.alpha(root.barForeground, 0.25)

        // Start a timer from the label. Sits below the × handler in the
        // stack, so clicks on the × don't reach this.
        MouseArea {
          id: chipMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (hostWidget) {
            hostWidget.addEntry(modelData)
            hostWidget.recordChipUse()
          }
        }

        Row {
          id: chipRow
          anchors.centerIn: parent
          spacing: Style.space(6)

          Text {
            text: chipMetrics.elidedText
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter

            TextMetrics {
              id: chipMetrics
              text: chip.fullText
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Qt.ElideRight
              // panel width minus this pill's padding, the × and its gap
              elideWidth: content.width - Style.space(48)
            }
          }

          Text {
            text: "×"
            color: root.barForeground
            opacity: forgetMouse.containsMouse ? 1 : 0.45
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
              id: forgetMouse
              anchors.fill: parent
              anchors.margins: -4
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (hostWidget) hostWidget.forgetLabel(modelData)
            }
          }
        }
      }
    }
  }

          Row {
            width: content.width
            spacing: Style.space(8)

            TextField {
              id: addField
              width: parent.width - addButton.implicitWidth - parent.spacing
              placeholderText: "What are you starting?"
              foreground: root.barForeground
              onAccepted: root.submit()
            }
            Button {
              id: addButton
              text: "Add"
              foreground: root.barForeground
              bordered: true
              enabled: addField.text.trim().length > 0
              onClicked: root.submit()
            }
          }

          Kit.EmptyState {
            visible: root.entries.length === 0
            text: "No active timers."
            hint: root.chips.length > 0 ? "Tap a label above, or type a new one." : "Type what you're starting above."
            foreground: root.barForeground
          }

          Repeater {
            model: root.entries
            delegate: Rectangle {
              id: card
              required property var modelData

              readonly property bool paused: Model.isPaused(modelData)
              // Typical run time for this label, from past completions -- null
              // until it has BASELINE_MIN_SAMPLES of them.
              readonly property var labelBaseline: Model.baselineFor(root.completed, modelData.label)
              readonly property double elapsedMs: Model.entryElapsedMs(modelData, root.nowMs)
              readonly property bool runningLong: !card.paused && Model.isRunningLong(elapsedMs, labelBaseline)
              // Click the elapsed line to swap it for the full creation stamp.
              property bool showCreatedAt: false

              width: content.width
              height: cardCol.implicitHeight + Style.space(24)
              radius: Style.cornerRadius
              clip: true
              color: Util.alpha(root.barForeground, 0.05)
              border.width: 1
              border.color: card.runningLong ? Util.alpha(root.longColor, 0.55)
                                             : Util.alpha(root.barForeground, 0.14)

              Column {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(12)
                anchors.rightMargin: Style.space(30)
                spacing: Style.space(4)

                Kit.InlineEdit {
                  width: parent.width
                  text: card.modelData.label
                  foreground: root.barForeground
                  pixelSize: Style.font.body
                  bold: true
                  placeholderText: "What are you timing?"
                  onEditingChanged: root.inlineEditors += editing ? 1 : -1
                  onAccepted: function(value) {
                    if (hostWidget) hostWidget.renameEntry(card.modelData.id, value)
                  }
                }
                Text {
                  id: elapsedText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: card.showCreatedAt
                    ? root.formatCreatedAt(card.modelData.createdAt)
                    : (Model.formatElapsed(card.elapsedMs) + (card.paused ? "  \u00b7  paused" : ""))
                  color: card.showCreatedAt ? root.barForeground
                    : card.paused ? Kit.Palette.faint
                    : (card.runningLong ? root.longColor : Color.accent)
                  opacity: card.showCreatedAt ? 0.8 : 1.0
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: !card.showCreatedAt

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.showCreatedAt = !card.showCreatedAt
                  }
                }
                Text {
                  visible: !!card.labelBaseline
                  text: card.labelBaseline
                    ? ((card.runningLong ? "over its usual ~" : "usually ~") + Model.formatElapsed(card.labelBaseline.median))
                    : ""
                  color: card.runningLong ? root.longColor : root.barForeground
                  opacity: card.runningLong ? 0.9 : 0.5
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              // Pause/resume + remove, top-right of the card.
              Row {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.space(10)
                spacing: Style.space(6)

                Text {
                  text: card.paused ? "\u25b6" : "\u23f8"
                  color: card.paused ? Color.accent : root.barForeground
                  opacity: card.paused ? 1.0 : 0.5
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (hostWidget) hostWidget.togglePauseEntry(card.modelData.id)
                  }
                }
                Text {
                  text: "\u00d7"
                  color: root.barForeground
                  opacity: 0.5
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (hostWidget) hostWidget.removeEntry(card.modelData.id)
                  }
                }
              }
            }
          }

          // Footer: adaptive summary of running + done-today, shown once
          // there's something to total.
          Text {
            visible: root.totalsText.length > 0
            width: content.width
            text: root.totalsText
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          PanelSeparator {}

          Text {
            text: "Enter: add  ·  ⏸ pause/resume  ·  click a time for its start date  ·  Esc: close"
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
