import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// Month grid you can click a date on to see/add a time block, plus an Ask AI
// box wired to omarchy-calendar-ai. All state (month cells, selected day,
// AI answer) lives on the bar widget (hostWidget) — this panel just renders
// it and forwards actions, same shape as alteringux.conductor's cockpit.
Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.calendar"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var guard: Kit.BugGuard.create("alteringux.calendar", function (argv) { Quickshell.execDetached(argv) })

  readonly property var state: hostWidget ? hostWidget.state : Model.defaultState()
  readonly property string currentMonth: hostWidget ? hostWidget.currentMonth : ""
  readonly property var monthCells: hostWidget ? hostWidget.monthCells : []
  readonly property var dayDetail: hostWidget ? hostWidget.dayDetail : ({ date: "", events: [], birthdays: [], holidays: [] })

  property string selectedDate: ""
  property bool inputFocused: false

  function selectDate(ymd) {
    guard.run("selectDate", function () {
      if (!ymd || !hostWidget) return
      root.selectedDate = ymd
      hostWidget.loadDay(ymd)
    })
  }

  function goMonth(delta) {
    guard.run("goMonth", function () {
      if (!hostWidget) return
      hostWidget.loadMonth(Model.shiftMonth(root.currentMonth, delta))
    })
  }

  // Jump back to the current month and select today — the nav arrows only
  // move a month at a time, so getting back from a few months away otherwise
  // takes several clicks.
  function goToday() {
    guard.run("goToday", function () {
      if (!hostWidget) return
      var ymd = Qt.formatDate(new Date(), "yyyy-MM-dd")
      hostWidget.loadMonth(ymd.slice(0, 7))
      root.selectDate(ymd)
    })
  }

  onOpenedChanged: {
    if (opened && hostWidget && !root.selectedDate) root.selectDate(root.state.date || hostWidget.currentMonth + "-01")
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(620)))
    focusTarget: null

    Kit.PanelKeys {
      anchors.fill: parent
      blocked: root.inputFocused

      onCloseRequested: root.close()
      additionalShortcutDescriptions: [
        { keys: "Enter / Return / Space", description: "Select the focused date", context: "Calendar · control focus" }
      ]

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: content.implicitHeight

        Column {
          id: content
          width: parent.width
          spacing: Style.spacing.panelGap

          Kit.PanelHead {
            glyph: hostWidget ? hostWidget.icon : ""   // nf-fa-calendar, live from the bar widget
            title: "Calendar"
            meta: Model.todayBadgeCount(root.state) > 0
              ? (Model.todayBadgeCount(root.state) + " thing" + (Model.todayBadgeCount(root.state) === 1 ? "" : "s") + " today")
              : "nothing today"
            foreground: root.barForeground
          }

          Text {
            width: content.width
            visible: hostWidget && hostWidget.lastError.length > 0
            text: hostWidget ? hostWidget.lastError : ""
            color: _webPalette.negative
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // ---- month navigation + grid --------------------------------
          Row {
            width: content.width
            spacing: Style.space(8)

            Kit.ActionButton {
              id: prevMonthButton
              text: "‹"
              foreground: _webPalette.accent
              bordered: true
              Accessible.name: "Previous month"
              onClicked: root.goMonth(-1)
            }
            Text {
              width: Math.max(0, content.width - prevMonthButton.implicitWidth
                - nextMonthButton.implicitWidth - todayButton.implicitWidth - parent.spacing * 3)
              horizontalAlignment: Text.AlignHCenter
              text: Model.monthTitle(root.currentMonth)
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Kit.ActionButton {
              id: nextMonthButton
              text: "›"
              foreground: _webPalette.accent
              bordered: true
              Accessible.name: "Next month"
              onClicked: root.goMonth(1)
            }
            Kit.ActionButton {
              id: todayButton
              text: "Today"
              foreground: _webPalette.faint
              bordered: true
              Accessible.name: "Go to today"
              onClicked: root.goToday()
            }
          }

          Column {
            id: grid
            width: content.width
            spacing: Style.space(4)
            readonly property real cellW: (width - 6 * Style.space(4)) / 7

            Row {
              spacing: Style.space(4)
              Repeater {
                model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                delegate: Text {
                  required property string modelData
                  width: grid.cellW
                  horizontalAlignment: Text.AlignHCenter
                  text: modelData
                  color: _webPalette.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            Repeater {
              model: 6
              delegate: Row {
                id: weekRow
                required property int index
                spacing: Style.space(4)

                Repeater {
                  model: 7
                  delegate: Rectangle {
                    id: dayCell
                    required property int index
                    readonly property int cellIndex: weekRow.index * 7 + index
                    readonly property var cell: root.monthCells.length > cellIndex ? root.monthCells[cellIndex] : Model.blankCell()

                    width: grid.cellW
                    height: grid.cellW
                    radius: Style.cornerRadius
                    activeFocusOnTab: cell.inMonth
                    Accessible.role: Accessible.RadioButton
                    Accessible.ignored: !cell.inMonth
                    Accessible.name: "Select date " + Model.formatDateTitle(cell.date)
                    Accessible.description: (cell.date === root.selectedDate ? "Selected. " : "")
                      + (cell.isToday ? "Today." : "")
                    Accessible.checkable: true
                    Accessible.checked: cell.date === root.selectedDate
                    Accessible.onPressAction: activate()
                    color: cell.date !== "" && cell.date === root.selectedDate
                      ? Util.alpha(_webPalette.accent, 0.25)
                      : (dayMouse.containsMouse && cell.inMonth ? Util.alpha(root.barForeground, 0.08) : "transparent")
                    border.width: cell.isToday || activeFocus ? Style.spacing.hairline : 0
                    border.color: _webPalette.accent

                    function activate() { if (dayCell.cell.inMonth) root.selectDate(dayCell.cell.date) }
                    Keys.onReturnPressed: activate()
                    Keys.onEnterPressed: activate()
                    Keys.onSpacePressed: activate()

                    Column {
                      anchors.centerIn: parent
                      spacing: 2
                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: dayCell.cell.inMonth ? String(dayCell.cell.dayNum) : ""
                        color: dayCell.cell.inMonth ? root.barForeground : "transparent"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                      }
                      Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 2
                        Rectangle { visible: dayCell.cell.hasHoliday; width: 4; height: 4; radius: 2; color: _webPalette.warning }
                        Rectangle { visible: dayCell.cell.hasBirthday; width: 4; height: 4; radius: 2; color: _webPalette.info }
                        Rectangle { visible: dayCell.cell.hasEvent; width: 4; height: 4; radius: 2; color: _webPalette.positive }
                      }
                    }

                    MouseArea {
                      id: dayMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      enabled: dayCell.cell.inMonth
                      cursorShape: dayCell.cell.inMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: { dayCell.forceActiveFocus(); dayCell.activate() }
                    }
                  }
                }
              }
            }
          }

          // Same dots + colors as the day-grid markers below, instead of fixed-hue
          // emoji that don't track the theme and don't visually match the cells
          // they're explaining.
          Row {
            width: content.width
            spacing: Style.space(14)

            Row {
              spacing: Style.space(4)
              Rectangle { width: 6; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: _webPalette.warning }
              Text { text: "holiday"; color: _webPalette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            }
            Row {
              spacing: Style.space(4)
              Rectangle { width: 6; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: _webPalette.info }
              Text { text: "birthday"; color: _webPalette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            }
            Row {
              spacing: Style.space(4)
              Rectangle { width: 6; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: _webPalette.positive }
              Text { text: "event/block"; color: _webPalette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            }
          }

          PanelSeparator {}

          // ---- selected day detail -------------------------------------
          Kit.SectionHeading {
            width: content.width
            text: root.selectedDate ? Model.formatDateTitle(root.selectedDate) : "Pick a date"
            uppercase: false
            rule: true
            foreground: root.barForeground
          }

          Column {
            width: content.width
            spacing: Style.space(3)
            visible: root.dayDetail.date === root.selectedDate

            Repeater {
              model: root.dayDetail.holidays || []
              delegate: Text {
                required property string modelData
                width: content.width
                text: "󱁖 " + modelData
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
            Repeater {
              model: root.dayDetail.birthdays || []
              delegate: Text {
                required property var modelData
                width: content.width
                text: "󰃥 " + modelData.name + (modelData.age ? "  (turns " + modelData.age + ")" : "")
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }

            Kit.EmptyState {
              visible: (root.dayDetail.events || []).length === 0
              text: "Nothing scheduled."
              hint: "Add a time block below."
              foreground: root.barForeground
            }

            Repeater {
              model: root.dayDetail.events || []
              delegate: Row {
                required property var modelData
                width: content.width
                spacing: Style.space(8)

                MarqueeText {
                  width: Math.max(0, content.width - removeEntryButton.implicitWidth - parent.spacing)
                  text: (modelData.kind === "block" ? "󱎫 " : "• ") + modelData.title + "  ·  " + Model.entrySubtitle(modelData)
                  color: root.barForeground
                  textFont.family: Style.font.family
                  textFont.pixelSize: Style.font.bodySmall
                  requestedElide: Text.ElideRight
                }
                Kit.ActionButton {
                  id: removeEntryButton
                  text: "×"
                  foreground: _webPalette.negative
                  bordered: true
                  Accessible.name: "Remove calendar entry " + modelData.title
                  onClicked: if (hostWidget) hostWidget.removeEntry(modelData.id)
                }
              }
            }
          }

          // ---- block time on the selected day ---------------------------
          Kit.SectionHeading {
            width: content.width
            text: "Block time"
            uppercase: true
            rule: true
            foreground: root.barForeground
            visible: root.selectedDate !== ""
          }

          Row {
            width: content.width
            spacing: Style.space(6)
            visible: root.selectedDate !== ""

            TextField {
              id: startField
              width: Math.max(0, (parent.width - addBlockButton.implicitWidth - parent.spacing * 2) / 2)
              placeholderText: "9:00 AM"
              foreground: root.barForeground
              Accessible.name: "Block start time"
              onActiveFocusChanged: root.inputFocused = activeFocus || endField.activeFocus || activityField.activeFocus
            }
            TextField {
              id: endField
              width: Math.max(0, (parent.width - addBlockButton.implicitWidth - parent.spacing * 2) / 2)
              placeholderText: "10:00 AM"
              foreground: root.barForeground
              Accessible.name: "Block end time"
              onActiveFocusChanged: root.inputFocused = activeFocus || startField.activeFocus || activityField.activeFocus
            }
            Kit.ActionButton {
              id: addBlockButton
              text: "Add"
              foreground: _webPalette.accent
              bordered: true
              Accessible.name: "Add calendar block"
              onClicked: {
                var start = Model.normalizeTime(startField.text.trim() || "9:00 AM")
                var end = Model.normalizeTime(endField.text.trim() || "10:00 AM")
                if (!hostWidget || !start || !end) return
                hostWidget.addBlock(root.selectedDate, start, end, activityField.text.trim())
                activityField.text = ""
              }
            }
          }
          TextField {
            id: activityField
            width: content.width
            visible: root.selectedDate !== ""
            placeholderText: "What are you blocking time for?"
            foreground: root.barForeground
            Accessible.name: "Calendar block description"
            onActiveFocusChanged: root.inputFocused = activeFocus || startField.activeFocus || endField.activeFocus
            onAccepted: {
              if (!hostWidget || text.trim().length === 0) return
              var start = Model.normalizeTime(startField.text.trim() || "9:00 AM")
              var end = Model.normalizeTime(endField.text.trim() || "10:00 AM")
              if (!start || !end) return
              hostWidget.addBlock(root.selectedDate, start, end, text.trim())
              text = ""
            }
          }

          PanelSeparator {}

          // ---- Ask AI ----------------------------------------------------
          Kit.SectionHeading {
            width: content.width
            text: "Ask AI"
            uppercase: true
            rule: true
            foreground: root.barForeground
          }

          Text {
            width: content.width
            text: "For schedule changes, the assistant can add, move, or remove entries directly. Review the result below."
            color: _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Row {
            width: content.width
            spacing: Style.space(6)

            TextField {
              id: aiField
              width: Math.max(0, parent.width - askButton.implicitWidth - parent.spacing)
              placeholderText: "“Move my dentist to Friday afternoon”…"
              foreground: root.barForeground
              enabled: hostWidget ? !hostWidget.aiBusy : true
              Accessible.name: "Ask AI about calendar changes"
              onActiveFocusChanged: root.inputFocused = activeFocus
              onAccepted: {
                if (!hostWidget || text.trim().length === 0) return
                hostWidget.askAi(text.trim())
              }
            }
            Kit.ActionButton {
              id: askButton
              text: hostWidget && hostWidget.aiBusy ? "…" : "Ask"
              foreground: _webPalette.accent
              bordered: true
              enabled: hostWidget && !hostWidget.aiBusy && aiField.text.trim().length > 0
              Accessible.name: hostWidget && hostWidget.aiBusy ? "Asking calendar assistant" : "Ask calendar assistant"
              onClicked: {
                if (!hostWidget || aiField.text.trim().length === 0) return
                hostWidget.askAi(aiField.text.trim())
              }
            }
          }

          Text {
            width: content.width
            visible: hostWidget && hostWidget.aiBusy
            text: "Thinking…"
            color: _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Text {
            width: content.width
            visible: hostWidget && !hostWidget.aiBusy && hostWidget.aiAnswer.length > 0
            wrapMode: Text.WordWrap
            text: hostWidget ? hostWidget.aiAnswer : ""
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: content.width
            text: "Right-click widget: refresh  ·  Esc: close"
            color: _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
