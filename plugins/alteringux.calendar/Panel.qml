import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Month grid you can click a date on to see/add a time block, plus an Ask AI
// box wired to omarchy-calendar-ai. All state (month cells, selected day,
// AI answer) lives on the bar widget (hostWidget) — this panel just renders
// it and forwards actions, same shape as alteringux.conductor's cockpit.
Panel {
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(620)))
    focusTarget: null

    PanelKeyCatcher {
      anchors.fill: parent
      blocked: root.inputFocused

      onCloseRequested: root.close()

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

          // ---- month navigation + grid --------------------------------
          Row {
            width: content.width
            spacing: Style.space(8)

            Text {
              text: "‹"
              color: Color.accent
              font.pixelSize: Style.font.title
              MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.goMonth(-1) }
            }
            Text {
              width: content.width - Style.space(120)
              horizontalAlignment: Text.AlignHCenter
              text: Model.monthTitle(root.currentMonth)
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              text: "›"
              color: Color.accent
              font.pixelSize: Style.font.title
              MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.goMonth(1) }
            }
            Text {
              text: "Today"
              color: Kit.Palette.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.goToday() }
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
                  color: Kit.Palette.faint
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
                    color: cell.date !== "" && cell.date === root.selectedDate
                      ? Util.alpha(Color.accent, 0.25)
                      : (dayMouse.containsMouse && cell.inMonth ? Util.alpha(root.barForeground, 0.08) : "transparent")
                    border.width: cell.isToday ? 1 : 0
                    border.color: Color.accent

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
                        Rectangle { visible: dayCell.cell.hasHoliday; width: 4; height: 4; radius: 2; color: Kit.Palette.warning }
                        Rectangle { visible: dayCell.cell.hasBirthday; width: 4; height: 4; radius: 2; color: Kit.Palette.info }
                        Rectangle { visible: dayCell.cell.hasEvent; width: 4; height: 4; radius: 2; color: Kit.Palette.positive }
                      }
                    }

                    MouseArea {
                      id: dayMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      enabled: dayCell.cell.inMonth
                      cursorShape: dayCell.cell.inMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: root.selectDate(dayCell.cell.date)
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
              Rectangle { width: 6; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: Kit.Palette.warning }
              Text { text: "holiday"; color: Kit.Palette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            }
            Row {
              spacing: Style.space(4)
              Rectangle { width: 6; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: Kit.Palette.info }
              Text { text: "birthday"; color: Kit.Palette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            }
            Row {
              spacing: Style.space(4)
              Rectangle { width: 6; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: Kit.Palette.positive }
              Text { text: "event/block"; color: Kit.Palette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            }
          }

          PanelSeparator {}

          // ---- selected day detail -------------------------------------
          Kit.SectionHeading {
            width: content.width
            text: root.selectedDate || "Pick a date"
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
                text: "🎉 " + modelData
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
                text: "🎂 " + modelData.name + (modelData.age ? "  (turns " + modelData.age + ")" : "")
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

                Text {
                  width: content.width - Style.space(24)
                  text: (modelData.kind === "block" ? "⏱ " : "• ") + modelData.title + "  ·  " + Model.entrySubtitle(modelData)
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
                Text {
                  text: "✕"
                  color: Kit.Palette.negative
                  font.pixelSize: Style.font.bodySmall
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (hostWidget) hostWidget.removeEntry(modelData.id)
                  }
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
              width: (content.width - Style.space(140)) / 2
              placeholderText: "09:00"
              foreground: root.barForeground
              onActiveFocusChanged: root.inputFocused = activeFocus || endField.activeFocus || activityField.activeFocus
            }
            TextField {
              id: endField
              width: (content.width - Style.space(140)) / 2
              placeholderText: "10:00"
              foreground: root.barForeground
              onActiveFocusChanged: root.inputFocused = activeFocus || startField.activeFocus || activityField.activeFocus
            }
            Text {
              text: "Add"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!hostWidget || activityField.text.trim().length === 0) return
                  hostWidget.addBlock(root.selectedDate, startField.text.trim(), endField.text.trim(), activityField.text.trim())
                  activityField.text = ""
                }
              }
            }
          }
          TextField {
            id: activityField
            width: content.width
            visible: root.selectedDate !== ""
            placeholderText: "What are you blocking time for?"
            foreground: root.barForeground
            onActiveFocusChanged: root.inputFocused = activeFocus || startField.activeFocus || endField.activeFocus
            onAccepted: {
              if (!hostWidget || text.trim().length === 0) return
              hostWidget.addBlock(root.selectedDate, startField.text.trim() || "09:00", endField.text.trim() || "10:00", text.trim())
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

          Row {
            width: content.width
            spacing: Style.space(6)

            TextField {
              id: aiField
              width: content.width - Style.space(60)
              placeholderText: "“Move my dentist to Friday afternoon”…"
              foreground: root.barForeground
              enabled: hostWidget ? !hostWidget.aiBusy : true
              onActiveFocusChanged: root.inputFocused = activeFocus
              onAccepted: {
                if (!hostWidget || text.trim().length === 0) return
                hostWidget.askAi(text.trim())
              }
            }
            Text {
              text: hostWidget && hostWidget.aiBusy ? "…" : "Ask"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!hostWidget || aiField.text.trim().length === 0) return
                  hostWidget.askAi(aiField.text.trim())
                }
              }
            }
          }

          Text {
            width: content.width
            visible: hostWidget && hostWidget.aiBusy
            text: "Thinking…"
            color: Kit.Palette.faint
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
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
