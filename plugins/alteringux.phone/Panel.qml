import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

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

  readonly property var frequencies: ["off", "rare", "occasional", "often"]

  readonly property bool anyFieldFocused:
    fName.activeFocus || fLength.activeFocus || fModel.activeFocus ||
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
    loadForm(c)
    root.view = "edit"
    if (root.hostWidget) { memoryProc.command = [root.hostWidget.scriptPath, "memory", c.id]; memoryProc.running = true }
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
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.memoryText = String(text || "").trim()
    }
  }

  onOpenedChanged: {
    if (opened) {
      root.view = "list"
      if (root.hostWidget) { root.hostWidget.refreshContacts(); root.hostWidget.refreshVoices() }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(Math.min(
      root.view === "edit" ? editCol.implicitHeight : listCol.implicitHeight, Style.space(520)))

    PanelKeyCatcher {
      anchors.fill: parent
      blocked: voiceDropdown.popupOpen || freqDropdown.popupOpen || root.anyFieldFocused
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
              width: listCol.width
              implicitHeight: crowLayout.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: crowArea.containsMouse
                ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
                : "transparent"

              MouseArea {
                id: crowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.onCall ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: if (!root.onCall && root.hostWidget) root.hostWidget.startCall(crow.modelData.id)
              }

              RowLayout {
                id: crowLayout
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(8)

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2
                  Text {
                    text: crow.modelData.name + (crow.modelData.looseGuard ? "  ·  unfiltered" : "")
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                  Text {
                    text: crow.modelData.voice
                      + (crow.modelData.canInitiate && crow.modelData.frequency !== "off"
                         ? "  ·  may call you (" + crow.modelData.frequency + ")" : "")
                    color: Kit.Palette.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                }

                Button {
                  text: "Edit"
                  foreground: root.barForeground
                  bordered: true
                  onClicked: root.openEdit(crow.modelData)
                }
                Button {
                  text: "Call"
                  foreground: root.barForeground
                  bordered: true
                  enabled: !root.onCall
                  onClicked: if (root.hostWidget) root.hostWidget.startCall(crow.modelData.id)
                }
              }
            }
          }

          Button {
            text: "New contact"
            foreground: root.barForeground
            bordered: true
            onClicked: root.openNew()
          }

          PanelSeparator {}
          PanelSectionHeader { text: "INCOMING CALLS"; foreground: root.barForeground }

          Toggle {
            width: listCol.width
            activeFocusOnTab: false
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
            activeFocusOnTab: false
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
              Text { text: "Quiet from"; color: Kit.Palette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption }
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
              Text { text: "to"; color: Kit.Palette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption }
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
            color: Kit.Palette.faint
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

          Text { text: "MODEL — optional NanoGPT id, blank uses the default"; color: Kit.Palette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption }
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
            activeFocusOnTab: false
            label: "Allow this contact to start calls"
            description: "Needs \"Let contacts call me\" on, and a frequency above"
            checked: false
            foreground: root.barForeground
          }
          Toggle {
            id: fSpeaksFirst
            width: editCol.width
            activeFocusOnTab: false
            label: "Speaks first"
            description: "Opens the call with a greeting instead of waiting for you"
            checked: true
            foreground: root.barForeground
          }
          Toggle {
            id: fLooseGuard
            width: editCol.width
            activeFocusOnTab: false
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
            Button {
              text: root.editing ? "Save changes" : "Create contact"
              foreground: root.barForeground
              bordered: true
              onClicked: root.saveForm()
            }
            Button {
              text: "Cancel"
              foreground: root.barForeground
              bordered: true
              onClicked: root.backToList()
            }
            Item { Layout.fillWidth: true }
            Button {
              visible: root.editing !== null
              text: "Delete"
              foreground: Kit.Palette.negative
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
              text: (root.memoryText && root.memoryText.length)
                ? root.memoryText
                : "Nothing yet — memory is written after your first call."
              color: (root.memoryText && root.memoryText.length) ? Color.foreground : Kit.Palette.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
            }
            Button {
              text: "Forget everything"
              foreground: Kit.Palette.negative
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
      color: Kit.Palette.faint
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
        ? Color.accent
        : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.18)

      QQC.TextArea {
        id: area
        anchors.fill: parent
        anchors.margins: Style.space(7)
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        placeholderText: pf.placeholder
        color: Color.foreground
        placeholderTextColor: Qt.darker(Color.foreground, 1.7)
        selectionColor: Style.selectionFillFor(Color.foreground, Color.accent)
        selectedTextColor: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        background: null
      }
    }
  }
}
