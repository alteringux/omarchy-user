import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// The phone panel: pick a contact and call them, edit a contact's persona /
// voice / flags, read (or wipe) what a contact remembers about you, and set up
// incoming calls. Everything acts on hostWidget (the BarWidget), which owns the
// state and the calls out to ~/.local/bin/omarchy-phone.
//
// Both views (list + edit) are built inline as siblings and toggled by
// `root.view`, rather than Loader + Component — the form glue needs to touch
// the field ids directly, and Component-scoped ids are not reachable from the
// file scope.
Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.phone"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var contacts: hostWidget ? (hostWidget.contacts || []) : []
  readonly property var voices: hostWidget ? (hostWidget.voices || []) : []
  readonly property var config: hostWidget && hostWidget.configLoaded ? hostWidget.config : Model.defaultConfig()
  readonly property string callState: hostWidget ? hostWidget.state : "IDLE"
  readonly property bool onCall: root.callState !== "IDLE" && root.callState !== "ENDED"

  readonly property var guard: Kit.BugGuard.create("alteringux.phone", function (argv) { Quickshell.execDetached(argv) })

  property string view: "list"           // "list" | "edit"
  property var editing: null             // the contact being edited (null = new)
  property string memoryText: ""
  property string memoryError: ""

  readonly property var frequencies: ["off", "rare", "occasional", "often"]

  readonly property bool anyFieldFocused:
    fName.activeFocus || fLength.activeFocus || fModel.activeFocus ||
    quietFrom.activeFocus || quietTo.activeFocus ||
    fBackstory.focused || fPersonality.focused || fSpeech.focused || fRules.focused

  function openNew() {
    root.editing = null
    root.memoryText = ""
    loadForm(null)
    root.view = "edit"
  }
  function openEdit(c) {
    root.editing = c
    root.memoryText = ""
    root.memoryError = ""
    loadForm(c)
    root.view = "edit"
    if (root.hostWidget && !memoryProc.running) { memoryProc.command = [root.hostWidget.scriptPath, "memory", c.id]; memoryProc.running = true }
  }
  function backToList() { root.view = "list"; root.editing = null }

  function loadForm(c) {
    var d = c || Model.defaultContact()
    fName.text = d.name || ""
    fVoice.value = d.voice || "en_US-amy-medium"
    fLength.text = (d.lengthScale !== undefined && d.lengthScale !== null) ? String(d.lengthScale) : "1.0"
    fModel.text = d.model || ""
    fFreq.value = d.frequency || "off"
    fCanInitiate.checked = d.canInitiate === true
    fSpeaksFirst.checked = d.speaksFirst !== false
    fLooseGuard.checked = d.looseGuard === true
    var p = d.persona || {}
    fBackstory.text = p.backstory || ""
    fPersonality.text = p.personality || ""
    fSpeech.text = p.speechStyle || ""
    fRules.text = Array.isArray(p.rules) ? p.rules.join("\n") : ""
  }

  function saveForm() {
    var obj = {
      name: fName.text.trim(),
      voice: fVoice.value,
      lengthScale: fLength.text.trim() || "1.0",
      model: fModel.text.trim(),
      frequency: fFreq.value,
      canInitiate: fCanInitiate.checked,
      speaksFirst: fSpeaksFirst.checked,
      looseGuard: fLooseGuard.checked,
      persona: {
        backstory: fBackstory.text.trim(),
        personality: fPersonality.text.trim(),
        speechStyle: fSpeech.text.trim(),
        rules: fRules.text.split("\n").map(function (s) { return s.trim() }).filter(function (s) { return s.length })
      }
    }
    if (root.editing && root.editing.id) obj.id = root.editing.id
    if (!obj.name.length) return
    if (root.hostWidget) root.hostWidget.saveContact(obj)
    root.backToList()
  }

  Process {
    id: memoryProc
    running: false
    property bool started: false
    property bool attempted: false
    onStarted: started = true
    onRunningChanged: {
      if (running) { started = false; attempted = true }
      else if (attempted && !started) {
        attempted = false
        root.memoryError = "Contact memory unavailable. Check ~/.local/bin/omarchy-phone."
      }
    }
    onExited: function(code, status) {
      started = false
      attempted = false
      if (code !== 0 || status !== 0) root.memoryError = "Contact memory could not be loaded (exit " + code + ")."
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.memoryText = String(text || "").trim()
      }
    }
  }

  onOpenedChanged: {
    if (opened) {
      root.view = "list"
      if (root.hostWidget) { root.hostWidget.refreshContacts(); root.hostWidget.refreshVoices() }
    }
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(Math.min(
      root.view === "edit" ? editCol.implicitHeight : listCol.implicitHeight, Style.space(520)))

    Kit.PanelKeys {
      anchors.fill: parent
      blocked: voiceDropdown.popupOpen || freqDropdown.popupOpen || root.anyFieldFocused
      escapeShortcutDescription: root.view === "edit" ? "Return to contacts" : "Close the panel"
      escapeShortcutContext: root.view === "edit" ? "Phone · contact editor shortcut focus" : "Phone · shortcut focus"
      additionalShortcutDescriptions: [
        { keys: "Enter / Return / Space", description: "Call the focused contact", context: "Phone contacts · control focus" }
      ]
      onCloseRequested: { if (root.view === "edit") root.backToList(); else root.close() }

      // ─────────────────────────────────────────────── LIST ──
      Kit.PanelScroll {
        id: listScroll
        anchors.fill: parent
        visible: root.view === "list"
        contentHeight: listCol.implicitHeight
        handleColor: root.barForeground

        Column {
          id: listCol
          width: listScroll.width
          spacing: Style.space(12)

          Kit.PanelHead {
            glyph: ""   // nf-fa-phone
            title: "Phone"
            meta: root.onCall
              ? (root.callState + " · " + (root.hostWidget ? root.hostWidget.call.contactName : ""))
              : (root.contacts.length + " contacts")
            foreground: root.barForeground
          }
          Text {
            id: phoneActionFeedback
            width: listCol.width
            visible: root.view === "list" && !!(root.hostWidget && root.hostWidget.actionStatus)
            text: root.hostWidget ? root.hostWidget.actionStatus : ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.hostWidget && root.hostWidget.actionFailed ? _webPalette.negative : _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            Accessible.role: Accessible.StaticText
            Accessible.name: text
            Connections {
              target: root.hostWidget
              ignoreUnknownSignals: true
              function onActionFeedback(message) {
                if (root.opened && phoneActionFeedback.visible) phoneActionFeedback.Accessible.announce(message)
              }
            }
          }

          Kit.EmptyState {
            visible: root.contacts.length === 0
            width: listCol.width
            text: "No contacts yet"
            hint: "Add one below, or run  omarchy-phone seed"
            foreground: root.barForeground
          }

          Repeater {
            model: root.contacts
            delegate: Rectangle {
              id: crow
              required property var modelData
              activeFocusOnTab: !root.onCall
              Accessible.role: Accessible.Button
              Accessible.name: "Call " + crow.modelData.name
              Accessible.onPressAction: activate()
              width: listCol.width
              implicitHeight: crowLayout.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              border.width: activeFocus ? Style.spacing.hairline : 0
              border.color: _webPalette.accent
              color: crowArea.containsMouse
                ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
                : "transparent"

              function activate() {
                if (!root.onCall && root.hostWidget) root.hostWidget.startCall(crow.modelData.id)
              }
              Keys.onReturnPressed: activate()
              Keys.onEnterPressed: activate()
              Keys.onSpacePressed: activate()

              MouseArea {
                id: crowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.onCall ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: {
                  if (!root.onCall && root.hostWidget) {
                    crow.forceActiveFocus()
                    crow.activate()
                  }
                }
              }

              RowLayout {
                id: crowLayout
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(8)

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2
                  MarqueeText {
                    text: crow.modelData.name + (crow.modelData.looseGuard ? "  ·  unfiltered" : "")
                    focusableOnOverflow: false
                    color: _webPalette.foreground
                    textFont.family: Style.font.family
                    textFont.pixelSize: Style.font.body
                    textFont.bold: true
                    requestedElide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                  MarqueeText {
                    text: crow.modelData.voice
                      + (crow.modelData.canInitiate && crow.modelData.frequency !== "off"
                         ? "  ·  may call you (" + crow.modelData.frequency + ")" : "")
                    focusableOnOverflow: false
                    color: _webPalette.faint
                    textFont.family: Style.font.family
                    textFont.pixelSize: Style.font.caption
                    requestedElide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                }

                Kit.ActionButton {
                  text: "Edit"
                  focusable: true
                  Accessible.role: Accessible.Button
                  Accessible.name: "Edit contact " + crow.modelData.name
                  foreground: root.barForeground
                  bordered: true
                  onClicked: root.openEdit(crow.modelData)
                }
                Kit.ActionButton {
                  text: "Call"
                  focusable: true
                  Accessible.role: Accessible.Button
                  Accessible.name: "Call " + crow.modelData.name
                  foreground: root.barForeground
                  bordered: true
                  enabled: !root.onCall
                  onClicked: if (root.hostWidget) root.hostWidget.startCall(crow.modelData.id)
                }
              }
            }
          }

          Kit.ActionButton {
            text: "New contact"
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: text
            foreground: root.barForeground
            bordered: true
            onClicked: root.openNew()
          }

          PanelSeparator {}
          PanelSectionHeader { text: "INCOMING CALLS"; foreground: root.barForeground }

          Toggle {
            width: listCol.width
            activeFocusOnTab: true
            label: "Let contacts call me"
            description: root.config.incomingEnabled
              ? "On — contacts marked \"may call\" ring you at their set frequency"
              : "Off — you place every call"
            checked: root.config.incomingEnabled === true
            foreground: root.barForeground
            onClicked: if (root.hostWidget) root.hostWidget.updateConfig({ incomingEnabled: !root.config.incomingEnabled })
          }

          Toggle {
            width: listCol.width
            activeFocusOnTab: true
            label: "Do not disturb"
            description: (root.hostWidget && root.hostWidget.dnd) ? "No incoming calls right now" : "Incoming calls allowed"
            checked: root.hostWidget && root.hostWidget.dnd
            foreground: root.barForeground
            enabled: root.config.incomingEnabled === true
            onClicked: if (root.hostWidget) root.hostWidget.toggleDnd()
          }

          RowLayout {
            width: listCol.width
            spacing: Style.space(8)
            enabled: root.config.incomingEnabled === true

            ColumnLayout {
              spacing: 2
              Text { text: "Quiet from"; color: _webPalette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              TextField {
                id: quietFrom
                text: root.config.quietHours ? root.config.quietHours.start : "22:00"
                foreground: root.barForeground
                Layout.preferredWidth: Style.space(70)
                onEditingFinished: if (root.hostWidget) root.hostWidget.updateConfig({ quietHours: { start: text } })
              }
            }
            ColumnLayout {
              spacing: 2
              Text { text: "to"; color: _webPalette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              TextField {
                id: quietTo
                text: root.config.quietHours ? root.config.quietHours.end : "08:00"
                foreground: root.barForeground
                Layout.preferredWidth: Style.space(70)
                onEditingFinished: if (root.hostWidget) root.hostWidget.updateConfig({ quietHours: { end: text } })
              }
            }
            NumberField {
              label: "Max / day"
              value: root.config.maxIncomingPerDay || 3
              from: 1
              to: 20
              foreground: root.barForeground
              onModified: function (v) { if (root.hostWidget) root.hostWidget.updateConfig({ maxIncomingPerDay: v }) }
            }
          }

          Text {
            width: listCol.width
            text: "Click a contact to call  ·  Esc: close"
            color: _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ─────────────────────────────────────────────── EDIT ──
      Kit.PanelScroll {
        id: editScroll
        anchors.fill: parent
        visible: root.view === "edit"
        contentHeight: editCol.implicitHeight
        handleColor: root.barForeground

        Column {
          id: editCol
          width: editScroll.width
          spacing: Style.space(10)

          Kit.PanelHead {
            glyph: ""
            title: root.editing ? ("Edit " + root.editing.name) : "New contact"
            meta: root.editing ? root.editing.id : "voice · persona · memory"
            foreground: root.barForeground
          }
          Text {
            id: phoneEditActionFeedback
            width: editCol.width
            visible: root.view === "edit" && !!(root.hostWidget && root.hostWidget.actionStatus)
            text: root.hostWidget ? root.hostWidget.actionStatus : ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.hostWidget && root.hostWidget.actionFailed ? _webPalette.negative : _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            Accessible.role: Accessible.StaticText
            Accessible.name: text
            Connections {
              target: root.hostWidget
              ignoreUnknownSignals: true
              function onActionFeedback(message) {
                if (root.opened && phoneEditActionFeedback.visible) phoneEditActionFeedback.Accessible.announce(message)
              }
            }
          }

          Text { text: "NAME"; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
          TextField {
            id: fName
            width: editCol.width
            placeholderText: "Amanda"
            foreground: root.barForeground
          }

          RowLayout {
            width: editCol.width
            spacing: Style.space(8)
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2
              Text { text: "VOICE"; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
              Dropdown {
                id: voiceDropdown
                Layout.fillWidth: true
                showLabel: false
                activeFocusOnTab: false
                options: root.voices
                value: fVoice.value
                foreground: root.barForeground
                onChanged: function (v) { fVoice.value = v }
              }
              QtObject { id: fVoice; property string value: "en_US-amy-medium" }
            }
            ColumnLayout {
              spacing: 2
              Text { text: "PACE"; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
              TextField {
                id: fLength
                text: "1.0"
                foreground: root.barForeground
                Layout.preferredWidth: Style.space(64)
              }
            }
          }

          Text { text: "MODEL — optional NanoGPT id, blank uses the default"; color: _webPalette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          TextField {
            id: fModel
            width: editCol.width
            placeholderText: root.config.nanogptModel || "deepseek-v3-0324"
            foreground: root.barForeground
          }

          RowLayout {
            width: editCol.width
            spacing: Style.space(6)
            Text {
              text: "MAY CALL YOU"
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              Layout.alignment: Qt.AlignVCenter
            }
            Dropdown {
              id: freqDropdown
              Layout.fillWidth: true
              showLabel: false
              activeFocusOnTab: false
              options: root.frequencies
              value: fFreq.value
              foreground: root.barForeground
              onChanged: function (v) { fFreq.value = v; fCanInitiate.checked = (v !== "off") }
            }
            QtObject { id: fFreq; property string value: "off" }
          }

          Toggle {
            id: fCanInitiate
            width: editCol.width
            activeFocusOnTab: true
            label: "Allow this contact to start calls"
            description: "Needs \"Let contacts call me\" on, and a frequency above"
            checked: false
            foreground: root.barForeground
          }
          Toggle {
            id: fSpeaksFirst
            width: editCol.width
            activeFocusOnTab: true
            label: "Speaks first"
            description: "Opens the call with a greeting instead of waiting for you"
            checked: true
            foreground: root.barForeground
          }
          Toggle {
            id: fLooseGuard
            width: editCol.width
            activeFocusOnTab: true
            label: "Unfiltered persona"
            description: "Drops the stay-in-character guard: can break the fourth wall, refuse for fun, mislead. Content limits are the model's."
            checked: false
            foreground: root.barForeground
          }

          PanelSeparator {}
          PanelSectionHeader { text: "PERSONA"; foreground: root.barForeground }

          PersonaField { id: fBackstory;    heading: "Backstory (treated as true about them)"; placeholder: "You are Amanda, 34, a friend of the caller's…" }
          PersonaField { id: fPersonality;  heading: "Personality"; placeholder: "Warm, quick, dry humour. Says so when something's a bad idea." }
          PersonaField { id: fSpeech;       heading: "Speech style"; placeholder: "Relaxed, medium sentences, no corporate words." }
          PersonaField { id: fRules;        heading: "Rules — one per line, re-asserted every turn"; placeholder: "Ask how the thing they were worried about turned out.\nNever give hollow reassurance." }

          RowLayout {
            width: editCol.width
            spacing: Style.space(8)
            Kit.ActionButton {
              text: root.editing ? "Save changes" : "Create contact"
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: text
              foreground: root.barForeground
              bordered: true
              onClicked: root.saveForm()
            }
            Kit.ActionButton {
              text: "Cancel"
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: text
              foreground: root.barForeground
              bordered: true
              onClicked: root.backToList()
            }
            Item { Layout.fillWidth: true }
            Kit.ActionButton {
              visible: root.editing !== null
              text: "Delete"
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: root.editing ? "Delete contact " + root.editing.name : "Delete contact"
              foreground: _webPalette.negative
              bordered: true
              onClicked: { if (root.hostWidget && root.editing) root.hostWidget.deleteContact(root.editing.id); root.backToList() }
            }
          }

          // ---- memory (existing contacts only) ----
          Column {
            width: editCol.width
            spacing: Style.space(6)
            visible: root.editing !== null

            PanelSeparator {}
            PanelSectionHeader { text: "WHAT THEY REMEMBER"; foreground: root.barForeground }
            Text {
              width: editCol.width
              visible: root.memoryError.length > 0
              text: root.memoryError
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              color: _webPalette.warning
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              Accessible.role: Accessible.StaticText
              Accessible.name: text
            }
            Text {
              width: editCol.width
              text: (root.memoryText && root.memoryText.length)
                ? root.memoryText
                : "Nothing yet — memory is written after your first call."
              color: (root.memoryText && root.memoryText.length) ? _webPalette.foreground : _webPalette.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
            }
            Kit.ActionButton {
              text: "Forget everything"
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: root.editing ? "Forget everything remembered about " + root.editing.name : text
              foreground: _webPalette.negative
              bordered: true
              visible: !!(root.memoryText && root.memoryText.length)
              onClicked: {
                if (root.hostWidget && root.editing) root.hostWidget.forgetMemory(root.editing.id)
                root.memoryText = ""
              }
            }
          }
        }
      }
    }
  }

  // A labelled multi-line text box for the persona blocks.
  component PersonaField: Column {
    id: pf
    property string heading: ""
    property string placeholder: ""
    property alias text: area.text
    property alias focused: area.activeFocus
    width: parent ? parent.width : 200
    spacing: 3

    Text {
      text: pf.heading
      color: _webPalette.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Rectangle {
      width: pf.width
      implicitHeight: Math.max(Style.space(64), area.implicitHeight + Style.space(14))
      radius: Style.cornerRadius
      color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
      border.width: 1
      border.color: area.activeFocus
        ? _webPalette.accent
        : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.18)

      QQC.TextArea {
        id: area
        anchors.fill: parent
        anchors.margins: Style.space(7)
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        placeholderText: pf.placeholder
        color: _webPalette.foreground
        placeholderTextColor: _webPalette.muted
        selectionColor: Style.selectionFillFor(_webPalette.foreground, _webPalette.accent)
        selectedTextColor: _webPalette.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        background: null
      }
    }
  }
}
