import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "ReminderFlowModel.js" as ReminderFlowModel
import "../alteringux.kit" as Kit
import "../shared"

Item {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string remindBin: Quickshell.env("HOME") + "/.local/bin/omarchy-remind"
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string step: "minutes"
  property string minutes: ""
  property string filterText: ""
  property string validationError: ""
  property bool creatingReminder: false
  property bool reminderCreated: false
  property bool operationFailed: false
  property string operationMessage: ""
  property string createErrorOutput: ""
  property bool repeat: false
  property string fontFamily: Style.font.menuFamily

  property color background: _webPalette.menuBackground
  property color foreground: _webPalette.menuText
  property color border: _webPalette.menuBorder
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: _webPalette.menuScrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(300), panel.width - Style.gapsOut * 2)
  readonly property string footerMessage: root.validationError || root.operationMessage
  onFooterMessageChanged: {
    var message = root.footerMessage
    if (!root.opened || !message) return
    Qt.callLater(function() {
      if (root.opened && footerStatus.visible && root.footerMessage === message)
        footerStatus.Accessible.announce(message)
    })
  }
  readonly property int validationHeight: root.footerMessage.length > 0
    ? Style.font.caption * 3 + Style.spacing.panelGap
    : 0
  readonly property int shortcutHintHeight: Style.font.caption * 2 + Style.spacing.panelGap
  property int cardHeight: Math.min(contentMargin * 2 + headerHeight + validationHeight + shortcutHintHeight, panel.height - Style.gapsOut * 2)
  readonly property string promptText: root.step === "message" ? "Reminder message" : "Remind in minutes"
  readonly property string shortcutHint: root.creatingReminder
    ? "Creating reminder…  ·  F1: help"
    : root.reminderCreated
      ? "Esc: close  ·  F1: help"
      : root.step === "minutes"
        ? "Enter: continue  ·  Tab: Repeat  ·  Esc: clear/close  ·  F1: help"
        : "Enter: create  ·  Tab: Repeat  ·  Esc: clear/back  ·  F1: help"

  readonly property var guard: Kit.BugGuard.create("alteringux.reminders", function(argv) { Quickshell.execDetached(argv) })

  Process {
    id: createProc
    running: false
    stderr: StdioCollector { onStreamFinished: root.createErrorOutput = this.text }
    onExited: function (code) {
      root.creatingReminder = false
      if (code === 0) {
        root.reminderCreated = true
        root.operationFailed = false
        root.operationMessage = "Reminder created. Press Esc to close."
      } else {
        var detail = String(root.createErrorOutput || "").trim().split(/\r?\n/)[0].slice(0, 180)
        root.operationFailed = true
        root.operationMessage = "Could not create reminder: " + (detail || ("process exited with code " + code))
      }
    }
  }

  function open(payloadJson) {
    guard.run("open", function() {
      if (root.creatingReminder) return
      var payload = ({})
      try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
      // Bug fix: this only ever assigned fontFamily when the payload carried
      // one, so a font passed on one open() stuck around forever afterwards —
      // including on a later open() with no payload, or after a theme/font
      // change moved Style.font.menuFamily on. Every open now starts from the
      // live default and overrides it only when the payload actually says to.
      root.fontFamily = payload.fontFamily || Style.font.menuFamily

      root.opened = true
      root.step = "minutes"
      root.minutes = ""
      root.filterText = ""
      root.validationError = ""
      root.operationMessage = ""
      root.operationFailed = false
      root.reminderCreated = false
      root.repeat = false

      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    })
  }

  function close() {
    if (root.creatingReminder) return
    root.opened = false
  }

  function toggleRepeat() {
    root.repeat = !root.repeat
  }

  function dismiss() {
    if (root.creatingReminder) return
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy.reminders")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.validationError = ""
    root.operationMessage = ""
    root.operationFailed = false
    root.reminderCreated = false
  }

  // Feature: step back to the minutes prompt instead of only being able to
  // dismiss the whole flow — the typed minutes come back into the field so
  // they're easy to correct rather than retyped from scratch.
  function backToMinutes() {
    root.step = "minutes"
    root.setFilter(root.minutes)
    root.minutes = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function submit() {
    guard.run("submit", function() {
      if (root.creatingReminder || root.reminderCreated) return
      var selection = root.filterText

      if (root.step === "minutes") {
        var nextMinutes = ReminderFlowModel.validMinutes(selection)

        if (!selection.trim()) {
          root.dismiss()
          return
        }

        if (!nextMinutes) {
          root.validationError = "Enter a positive whole number of minutes."
          return
        }

        root.minutes = nextMinutes
        root.step = "message"
        root.filterText = ""
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        return
      }

      if (root.step === "message") {
        var args = root.repeat
          ? [root.remindBin].concat(ReminderFlowModel.repeatReminderArgs(root.minutes, selection))
          : [root.omarchyPath + "/bin/omarchy-reminder"].concat(ReminderFlowModel.reminderArgs(root.minutes, selection))
        if (!args.length || args[0] === "") {
          root.validationError = "Could not prepare the reminder command. Check the Omarchy paths and try again."
          return
        }
        root.validationError = ""
        root.operationFailed = false
        root.reminderCreated = false
        root.operationMessage = "Creating reminder…"
        root.createErrorOutput = ""
        root.creatingReminder = true
        createProc.command = args
        createProc.running = true
      }
    })
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-reminders"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

      BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        readonly property var shortcutDescriptions: [
          { keys: "F1", description: "Open recovery and keyboard shortcut help", context: "Reminders" },
          { keys: "Enter / Return", description: root.step === "minutes" ? "Continue to the reminder message" : "Create the reminder", context: "Reminders · " + root.step + " step" },
          { keys: "Tab / Shift + Tab", description: "Move focus to or from the Repeat option", context: "Reminders" },
          { keys: "Enter / Space", description: "Toggle repeating reminders", context: "Reminders · Repeat option" },
          { keys: "Escape", description: root.creatingReminder ? "Wait for reminder creation to finish" : (root.reminderCreated ? "Close the completed reminder" : "Clear text; when empty, go back one step or close"), context: "Reminders" }
        ]

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_F1) {
            shortcutHelp.show()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (!root.creatingReminder) {
              if (root.reminderCreated) root.dismiss()
              else if (root.filterText) root.setFilter("")
              else if (root.step === "message") root.backToMinutes()
              else root.dismiss()
            }
            event.accepted = true
          } else if (root.creatingReminder) {
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            repeatToggle.forceActiveFocus()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit()
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset + root.validationHeight + root.shortcutHintHeight
        anchors.leftMargin: card.contentLeftInset

        MarqueeText {
          requestedTextFormat: Text.PlainText
          anchors.left: parent.left
          anchors.right: repeatToggle.left
          anchors.rightMargin: Style.spacing.panelGap
          anchors.verticalCenter: parent.verticalCenter
          text: root.filterText || (root.promptText + "...")
          color: root.foreground
          textFont.family: root.fontFamily
          textFont.pixelSize: Style.font.heading
          requestedElide: Text.ElideRight
        }

        // Repeat checkbox: toggle by click, keyboard, or assistive action. When checked, submitting
        // routes through `omarchy-remind --every <minutes>` instead of the
        // stock one-shot `omarchy-reminder`.
        Item {
          id: repeatToggle
          activeFocusOnTab: true
          Accessible.role: Accessible.CheckBox
          Accessible.name: "Repeat reminder"
          Accessible.description: "Press Space or Enter to toggle. Tab moves focus."
          Accessible.checked: root.repeat
          Accessible.onToggleAction: root.toggleRepeat()
          enabled: !root.creatingReminder && !root.reminderCreated
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              if (!root.creatingReminder) {
                if (root.reminderCreated) root.dismiss()
                else if (root.filterText) root.setFilter("")
                else if (root.step === "message") root.backToMinutes()
                else root.dismiss()
              }
              event.accepted = true
            } else if (root.creatingReminder) {
              event.accepted = true
            } else if (event.key === Qt.Key_F1) {
              shortcutHelp.show()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              keyCatcher.forceActiveFocus()
              event.accepted = true
            } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (!root.reminderCreated) root.toggleRepeat()
              event.accepted = true
            } else {
              event.accepted = true
            }
          }
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: repeatRow.implicitWidth
          implicitHeight: Math.max(repeatRow.implicitHeight, box.height)
          width: implicitWidth
          height: implicitHeight

          Rectangle {
            anchors.fill: parent
            anchors.margins: -Style.space(3)
            radius: root.cornerRadius
            color: "transparent"
            border.width: repeatToggle.activeFocus ? 1 : 0
            border.color: _webPalette.accent
          }

          Row {
            id: repeatRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            Rectangle {
              id: box
              width: Math.round(Style.font.subtitle * 1.15)
              height: width
              anchors.verticalCenter: parent.verticalCenter
              radius: root.cornerRadius > 0 ? Style.space(3) : 0
              color: root.repeat ? _webPalette.accent : "transparent"
              border.width: Math.max(1, Style.space(1))
              border.color: root.repeat ? _webPalette.accent : Util.alpha(root.foreground, 0.5)

              Behavior on color { ColorAnimation { duration: 100 } }

              Text {
                anchors.centerIn: parent
                visible: root.repeat
                text: "✓"
                color: root.background
                font.family: root.fontFamily
                font.pixelSize: Math.round(parent.height * 0.82)
                font.bold: true
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "Repeat"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { repeatToggle.forceActiveFocus(); root.toggleRepeat() }
          }
        }
      }

      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset + root.validationHeight
        text: root.shortcutHint
        color: _webPalette.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        Accessible.ignored: true
      }

      Text {
        id: footerStatus
        visible: root.footerMessage.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        text: root.footerMessage
        color: root.validationError || root.operationFailed ? _webPalette.negative
          : (root.reminderCreated ? _webPalette.positive : _webPalette.faint)
        Accessible.role: Accessible.StaticText
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
      }
    }

    Kit.RecoveryHelp {
      id: shortcutHelp
      returnFocusItem: keyCatcher
    }
  }
}
