import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Stats + settings popup for the pomodoro widget. Manual start/pause/skip/
// reset buttons here call the same functions the keybinding IPC calls, so
// there is exactly one implementation of each control.
Panel {
  id: root
  moduleName: "alteringux.pomodoro"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var guard: Kit.BugGuard.create("alteringux.pomodoro", function(argv) { Quickshell.execDetached(argv) })

  readonly property var config: hostWidget ? hostWidget.config : Model.defaultConfig()
  readonly property var stats: hostWidget ? hostWidget.stats : Model.defaultStats()
  readonly property string today: Model.todayDateString()
  // Same bucket BarWidget.todayBucket derives, reused rather than recomputed.
  readonly property var todayBucket: hostWidget ? hostWidget.todayBucket : { completed: 0, focusedMs: 0 }
  readonly property var weekly: Model.weeklyTotals(stats, today)
  readonly property real allTimeFocusedMs: Model.allTimeFocusedMs(stats)

  function updateConfig(patch) {
    if (hostWidget) hostWidget.updateConfig(patch)
  }

  function playSound(key) {
    if (hostWidget) hostWidget.playSound(key)
  }

  // True while any duration/sound input has focus, so a keystroke meant for
  // that field (e.g. typing "r" into a sound path) isn't swallowed as a
  // panel-level shortcut.
  function anyFieldFocused() {
    if (workField.field && workField.field.activeFocus) return true
    if (shortBreakField.field && shortBreakField.field.activeFocus) return true
    if (longBreakField.field && longBreakField.field.activeFocus) return true
    if (cycleField.field && cycleField.field.activeFocus) return true
    if (reminderField.field && reminderField.field.activeFocus) return true
    for (var i = 0; i < soundRepeater.count; i++) {
      var item = soundRepeater.itemAt(i)
      if (item && item.field && item.field.activeFocus) return true
    }
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent
      blocked: root.anyFieldFocused()

      onCloseRequested: root.close()
      onActivateRequested: if (hostWidget) hostWidget.togglePause()
      onDeleteRequested: if (hostWidget) hostWidget.skipPhase()
      onTextKey: function(t) {
        if ((t === "r" || t === "R") && hostWidget) hostWidget.resetSession()
      }

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(14)

      Kit.PanelHead {
        glyph: "\uf017"   // nf-fa-clock_o, matches the bar widget at rest
        title: "Pomodoro"
        meta: hostWidget && hostWidget.phase !== Model.PHASE_IDLE
          ? Model.phaseLabel(hostWidget.phase) + (hostWidget.running ? " · running" : hostWidget.ready ? " · ready" : " · paused")
          : "idle"
        foreground: root.barForeground
      }

      PanelSectionHeader {
        text: "STATISTICS"
        foreground: root.barForeground
      }

      Grid {
        width: parent.width
        columns: 2
        columnSpacing: Style.space(10)
        rowSpacing: Style.space(6)

        Text { text: "Completed today"; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        Text { text: String(root.todayBucket.completed); color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: true }

        Text { text: "Focused today"; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        Text { text: Model.formatDuration(root.todayBucket.focusedMs); color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: true }

        Text { text: "This week"; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        Text { text: root.weekly.completed + " (" + Model.formatDuration(root.weekly.focusedMs) + ")"; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: true }

        Text { text: "All-time focus"; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        Text { text: Model.formatDuration(root.allTimeFocusedMs); color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: true }

        Text { text: "Streak"; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        Text { text: root.stats.streak + (root.stats.streak === 1 ? " day" : " days"); color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: true }
      }

      PanelSeparator {}

      PanelSectionHeader {
        text: "CONTROLS"
        foreground: root.barForeground
      }

      Row {
        spacing: Style.space(8)

        Button {
          text: hostWidget && hostWidget.running ? "Pause" : "Start"
          foreground: root.barForeground
          bordered: true
          onClicked: if (hostWidget) hostWidget.togglePause()
        }
        Button {
          text: "Skip"
          foreground: root.barForeground
          bordered: true
          onClicked: if (hostWidget) hostWidget.skipPhase()
        }
        Button {
          text: "Reset"
          foreground: root.barForeground
          bordered: true
          onClicked: if (hostWidget) hostWidget.resetSession()
        }
      }

      PanelSeparator {}

      PanelSectionHeader {
        text: "DURATIONS"
        foreground: root.barForeground
      }

      Row {
        spacing: Style.space(14)

        NumberField {
          id: workField
          label: "Work (min)"
          value: root.config.workMinutes
          from: 1
          to: 180
          foreground: root.barForeground
          onModified: function(v) { root.updateConfig({ workMinutes: v }) }
        }
        NumberField {
          id: shortBreakField
          label: "Short break"
          value: root.config.shortBreakMinutes
          from: 1
          to: 60
          foreground: root.barForeground
          onModified: function(v) { root.updateConfig({ shortBreakMinutes: v }) }
        }
      }

      // Adaptive hint, built from recent completion/interruption history at
      // the current work length. Never applied automatically — the user
      // clicks Apply or ignores it.
      Row {
        visible: hostWidget && hostWidget.workSuggestion !== null && hostWidget.workSuggestion !== undefined && hostWidget.workSuggestion !== root.config.workMinutes
        spacing: Style.space(8)

        Text {
          text: hostWidget && hostWidget.workSuggestion > root.config.workMinutes
                ? "You've been finishing every " + root.config.workMinutes + "m block lately — try " + (hostWidget ? hostWidget.workSuggestion : "") + "m?"
                : "You've been cutting " + root.config.workMinutes + "m blocks short lately — try " + (hostWidget ? hostWidget.workSuggestion : "") + "m?"
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          width: content.width - applySuggestionButton.implicitWidth - Style.space(8)
          wrapMode: Text.WordWrap
        }
        Button {
          id: applySuggestionButton
          text: "Apply"
          foreground: root.barForeground
          bordered: true
          onClicked: if (hostWidget) root.updateConfig({ workMinutes: hostWidget.workSuggestion })
        }
      }

      Row {
        spacing: Style.space(14)

        NumberField {
          id: longBreakField
          label: "Long break"
          value: root.config.longBreakMinutes
          from: 1
          to: 120
          foreground: root.barForeground
          onModified: function(v) { root.updateConfig({ longBreakMinutes: v }) }
        }
        NumberField {
          id: cycleField
          label: "Cycle length"
          value: root.config.longBreakCycle
          from: 1
          to: 12
          foreground: root.barForeground
          onModified: function(v) { root.updateConfig({ longBreakCycle: v }) }
        }
      }

      Row {
        spacing: Style.space(14)

        NumberField {
          id: reminderField
          label: "Reminder (min)"
          value: root.config.reminderMinutes
          from: 1
          to: 60
          foreground: root.barForeground
          onModified: function(v) { root.updateConfig({ reminderMinutes: v }) }
        }
      }

      PanelSeparator {}

      PanelSectionHeader {
        text: "SOUNDS (blank = default)"
        foreground: root.barForeground
      }

      Repeater {
        id: soundRepeater
        model: [
          { key: "workStart", label: "Work start" },
          { key: "breakStart", label: "Short break start" },
          { key: "longBreakStart", label: "Long break start" }
        ]

        Row {
          id: soundRow
          required property var modelData
          property alias field: soundField
          width: content.width
          spacing: Style.space(8)

          Text {
            id: soundLabel
            width: Style.space(110)
            text: modelData.label
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }

          TextField {
            id: soundField
            width: soundRow.width - soundLabel.width - testButton.implicitWidth - soundRow.spacing * 2
            text: root.config.sounds[modelData.key] || ""
            foreground: root.barForeground
            placeholderText: "/path/to/sound.oga"
            onEditingFinished: {
              var patch = { sounds: {} }
              patch.sounds[modelData.key] = text
              root.updateConfig(patch)
            }
          }

          Button {
            id: testButton
            text: "Test"
            foreground: root.barForeground
            bordered: true
            onClicked: root.playSound(modelData.key)
          }
        }
      }

      PanelSeparator {}

      // Hint / tertiary line — Style.font.caption + Kit.Palette.faint per the
      // panel text-hierarchy ramp (docs/adr/0005), not the meta-tag treatment
      // (this is a full sentence, not a glanceable status).
      Text {
        text: "Enter: start/pause  ·  X: skip  ·  R: reset  ·  Esc: close"
        color: Kit.Palette.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
    }
  }
}
