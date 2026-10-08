import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// The breathe popup: pick a technique, run a session without dimming the
// desktop, read the metrics, and set the plugin up.
//
// Every control here calls the same hostWidget function the IPC handler and
// the fullscreen guide call, so a session started from a keybinding, a
// conductor ritual, the overlay or this panel is one implementation.
Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.breathe"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var guard: Kit.BugGuard.create("alteringux.breathe", function (argv) { Quickshell.execDetached(argv) })

  readonly property var config: hostWidget ? hostWidget.config : Model.defaultConfig()
  readonly property var live: hostWidget ? hostWidget.live : null
  readonly property var technique: hostWidget ? hostWidget.technique : null
  readonly property bool running: hostWidget ? hostWidget.running : false
  readonly property bool paused: hostWidget ? hostWidget.paused : false
  readonly property bool idle: hostWidget ? hostWidget.idle : true
  readonly property bool active: !root.idle
  readonly property color barForeground: root.bar ? _webPalette.barForeground : _webPalette.foreground

  // Which technique's detail is open. One at a time keeps the list scannable;
  // eleven expanded cards would be a wall.
  property string expandedId: ""
  // The pattern builder takes over the panel body rather than opening a second
  // surface — a popup on top of a popup is where panels go to die.
  property bool editorOpen: false
  property string editingId: ""

  readonly property var allTechniques: Model.allTechniques(root.config)

  function techniquesOf(family) {
    var out = []
    for (var i = 0; i < root.allTechniques.length; i++) {
      if (root.allTechniques[i].family === family) out.push(root.allTechniques[i])
    }
    return out
  }

  // The handful you actually reach for, floated above the families. Ranking
  // comes from Kit.Usage, so the list reorders itself with no code change.
  readonly property var frequent: {
    if (!hostWidget || !hostWidget.usage) return []
    var subset = []
    for (var i = 0; i < root.allTechniques.length; i++) subset.push("start:" + root.allTechniques[i].id)
    var ranked = hostWidget.usage.rankActions(subset)
    var out = []
    for (var j = 0; j < ranked.length && out.length < 3; j++) {
      var id = String(ranked[j]).replace("start:", "")
      if (hostWidget.usage.count("start:" + id) <= 0) continue
      var t = Model.techniqueById(id, root.config)
      if (t) out.push(t)
    }
    return out
  }

  function toneColor(tone) {
    if (tone === "positive") return _webPalette.positive
    if (tone === "negative") return _webPalette.negative
    if (tone === "warning") return _webPalette.warning
    if (tone === "info") return _webPalette.info
    return root.barForeground
  }

  function updateConfig(patch) { if (hostWidget) hostWidget.updateConfig(patch) }

  // True while any text or number input holds focus, so a keystroke meant for
  // that field is not swallowed as a panel-level shortcut.
  property int inlineEditors: 0
  function anyFieldFocused() {
    if (root.inlineEditors > 0) return true
    if (phaseSoundField.activeFocus || endSoundField.activeFocus) return true
    if (cycleField.field && cycleField.field.activeFocus) return true
    if (nudgeField.field && nudgeField.field.activeFocus) return true
    if (editorLoader.item && editorLoader.item.anyFieldFocused && editorLoader.item.anyFieldFocused()) return true
    return false
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(Math.min(body.implicitHeight, Style.space(640)))

    Kit.PanelKeys {
      anchors.fill: parent
      blocked: root.anyFieldFocused()
      escapeShortcutDescription: root.editorOpen
        ? "Cancel inline text editing, or close the pattern editor"
        : "Close the panel"
      escapeShortcutContext: root.editorOpen ? "Breathe · pattern editor" : "Breathe · shortcut focus"
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Toggle the breathing session", context: "Breathe · shortcut focus" },
        { keys: "G", description: "Show or hide the breathing guide", context: "Breathe · shortcut focus" },
        { keys: "S", description: "Stop the active breathing session", context: "Breathe · shortcut focus" },
        { keys: "Enter / Return / Space", description: "Show or hide details for the focused technique", context: "Breathe · technique controls" },
        { keys: "Space", description: "Pause or resume the breathing session", context: "Breathe · fullscreen guide" },
        { keys: "Right Arrow", description: "Skip the active breath hold", context: "Breathe · fullscreen guide" },
        { keys: "L", description: "Toggle looping for this session", context: "Breathe · fullscreen guide" },
        { keys: "Escape", description: "Hide the fullscreen guide", context: "Breathe · fullscreen guide" }
      ]

      onCloseRequested: {
        if (root.editorOpen) { root.editorOpen = false; return }
        root.close()
      }
      onActivateRequested: if (root.hostWidget) root.hostWidget.toggleSession()
      onTextKey: function (t) {
        if ((t === "g" || t === "G") && root.hostWidget) root.hostWidget.toggleGuide()
        else if ((t === "s" || t === "S") && root.hostWidget && root.active) root.hostWidget.stopSession()
      }

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: body.implicitHeight
        handleColor: root.barForeground

        Column {
          id: body
          width: parent.width
          spacing: Style.spacing.panelGap

          Kit.PanelHead {
            width: parent.width
            glyph: Model.PLUGIN_GLYPH
            title: "Breathe"
            meta: {
              if (root.editorOpen) return "Custom pattern"
              if (root.paused) return "Paused"
              if (root.running && root.live) return root.live.phaseLabel
              if (root.hostWidget && root.hostWidget.done) return "Complete"
              var s = root.hostWidget ? Model.streakOf(root.hostWidget.stats).current : 0
              return s > 0 ? s + " day streak" : "Ready"
            }
            foreground: root.barForeground
          }

          Text {
            width: parent.width
            visible: !root.editorOpen
            text: "Panel shortcuts · Enter / Space: toggle session  ·  G: show/hide guide  ·  S: stop active session"
            color: _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // ================= the pattern builder =========================
          Loader {
            id: editorLoader
            width: parent.width
            active: root.editorOpen
            visible: active
            source: Qt.resolvedUrl("TechniqueEditor.qml")
            onLoaded: {
              item.hostWidget = root.hostWidget
              item.foreground = root.barForeground
              item.editingId = root.editingId
              item.closed.connect(function () { root.editorOpen = false; root.editingId = "" })
            }
          }

          // ================= live session ===============================
          Rectangle {
            width: parent.width
            visible: !root.editorOpen && root.active
            height: liveCol.implicitHeight + Style.space(22)
            radius: Style.cornerRadius
            color: _webPalette.cardBg
            border.width: 1
            border.color: _webPalette.cardBorder

            Column {
              id: liveCol
              anchors.centerIn: parent
              width: parent.width - Style.space(22)
              spacing: Style.space(10)

              // The compact guide. Same Model.orbScale as the fullscreen one,
              // so the two breathe in exact lockstep when both are visible.
              Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(96)
                height: width

                Rectangle {
                  anchors.centerIn: parent
                  visible: !root.config.reduceMotion
                  width: parent.width * (root.live ? root.live.orbScale : Model.SCALE_MIN) * 1.25
                  height: width
                  radius: width / 2
                  color: root.hostWidget ? root.hostWidget.toneColor : _webPalette.info
                  opacity: 0.12
                  Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                  anchors.centerIn: parent
                  width: parent.width * (root.live ? root.live.orbScale : Model.SCALE_MIN)
                  height: width
                  radius: width / 2
                  color: {
                    var c = root.hostWidget ? root.hostWidget.toneColor : _webPalette.info
                    return Qt.rgba(c.r, c.g, c.b, root.paused ? 0.10 : 0.24)
                  }
                  border.width: 1.5
                  border.color: root.paused
                    ? _webPalette.faint
                    : (root.hostWidget ? root.hostWidget.toneColor : _webPalette.info)
                }

                Text {
                  anchors.centerIn: parent
                  text: root.live
                    ? Model.formatClock(root.live.isHold ? root.live.phaseElapsedMs : Model.breathRemainingMs(root.technique, root.live))
                    : ""
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.live ? root.live.phaseLabel : ""
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              MarqueeText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: {
                  if (!root.live || !root.technique) return ""
                  var where = root.live.breathCount
                    ? "breath " + (root.live.breathIndex + 1) + "/" + root.live.breathCount
                    : "cycle " + (root.live.cycleIndex + 1) + "/" + root.live.cycleCount
                  return root.technique.name + " · " + where
                }
                color: _webPalette.faint
                textFont.family: Style.font.family
                textFont.pixelSize: Style.font.caption
                requestedElide: Text.ElideRight
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(8)

                Kit.ActionButton {
                  focusable: true
                  Accessible.role: Accessible.Button
                  Accessible.name: text
                  text: root.paused ? "Resume" : "Pause"
                  bordered: true
                  foreground: root.barForeground
                  visible: root.running || root.paused
                  onClicked: if (root.hostWidget) root.hostWidget.toggleSession()
                }
                Kit.ActionButton {
                  focusable: true
                  Accessible.role: Accessible.Button
                  Accessible.name: text
                  text: "Skip hold"
                  bordered: true
                  foreground: root.barForeground
                  visible: root.running && root.live && root.live.isHold
                  onClicked: if (root.hostWidget) root.hostWidget.skipHold()
                }
                Kit.ActionButton {
                  focusable: true
                  Accessible.role: Accessible.Button
                  Accessible.name: text
                  text: "Finish"
                  bordered: true
                  foreground: root.barForeground
                  visible: root.running || root.paused
                  onClicked: if (root.hostWidget) root.hostWidget.stopSession()
                }
                Kit.ActionButton {
                  focusable: true
                  Accessible.role: Accessible.Button
                  Accessible.name: text
                  text: root.hostWidget && root.hostWidget.guideVisible ? "Hide guide" : "Full screen"
                  bordered: true
                  foreground: root.barForeground
                  onClicked: if (root.hostWidget) root.hostWidget.toggleGuide()
                }
                Kit.ActionButton {
                  focusable: true
                  Accessible.role: Accessible.Button
                  Accessible.name: text
                  text: "Clear"
                  bordered: true
                  foreground: root.barForeground
                  visible: root.hostWidget && root.hostWidget.done
                  onClicked: if (root.hostWidget) root.hostWidget.resetSession()
                }
              }
            }
          }

          // ================= techniques =================================
          Column {
            width: parent.width
            visible: !root.editorOpen
            spacing: Style.space(8)

            Repeater {
              model: [
                { key: "frequent",   title: "Most used",  list: root.frequent },
                { key: "core",       title: "Core",       list: root.techniquesOf("core") },
                { key: "energising", title: "Energising", list: root.techniquesOf("energising") },
                { key: "clinical",   title: "Clinical",   list: root.techniquesOf("clinical") },
                { key: "custom",     title: "Yours",      list: root.techniquesOf("custom") }
              ]

              Column {
                id: group
                required property var modelData
                width: parent.width
                spacing: Style.space(4)
                visible: modelData.list.length > 0

                Kit.SectionHeading {
                  width: parent.width
                  text: group.modelData.title
                }

                Repeater {
                  model: group.modelData.list

                  Rectangle {
                    id: card
                    required property var modelData
                    readonly property bool expanded: root.expandedId === (group.modelData.key + ":" + modelData.id)
                    readonly property bool isCurrent: root.active && root.technique && root.technique.id === modelData.id

                    width: parent.width
                    height: cardCol.implicitHeight + Style.space(16)
                    radius: Style.cornerRadius
                    color: card.isCurrent
                      ? Qt.rgba(root.toneColor(modelData.tone).r, root.toneColor(modelData.tone).g,
                                root.toneColor(modelData.tone).b, 0.10)
                      : _webPalette.cardBg
                    border.width: 1
                    border.color: cardMouse.activeFocus ? _webPalette.accent
                      : (card.isCurrent ? root.toneColor(modelData.tone) : _webPalette.cardBorder)

                    Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    function toggleDetails() {
                      var key = group.modelData.key + ":" + card.modelData.id
                      root.expandedId = (root.expandedId === key) ? "" : key
                    }

                    // The tone spine, so a technique keeps one identifying
                    // colour across the picker, the metrics bars and the orb.
                    Rectangle {
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      anchors.margins: 1
                      width: Style.space(3)
                      radius: width / 2
                      color: root.toneColor(card.modelData.tone)
                    }

                    MouseArea {
                      id: cardMouse
                      anchors.fill: parent
                      activeFocusOnTab: true
                      Accessible.role: Accessible.Button
                      Accessible.name: (card.expanded ? "Hide" : "Show") + " details for " + card.modelData.name
                      Accessible.onPressAction: card.toggleDetails()
                      Keys.onReturnPressed: card.toggleDetails()
                      Keys.onEnterPressed: card.toggleDetails()
                      Keys.onSpacePressed: card.toggleDetails()
                      onClicked: {
                        cardMouse.forceActiveFocus()
                        card.toggleDetails()
                      }
                    }

                    Column {
                      id: cardCol
                      anchors.centerIn: parent
                      width: parent.width - Style.space(22)
                      spacing: Style.space(5)

                      Item {
                        width: parent.width
                        height: Math.max(nameText.implicitHeight, playButton.implicitHeight)

                        MarqueeText {
                          id: nameText
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          width: parent.width - playButton.implicitWidth - patternText.implicitWidth - Style.space(16)
                          text: card.modelData.name
                          color: root.barForeground
                          textFont.family: Style.font.family
                          textFont.pixelSize: Style.font.bodySmall
                          textFont.bold: true
                          requestedElide: Text.ElideRight
                        }

                        Text {
                          id: patternText
                          anchors.right: playButton.left
                          anchors.rightMargin: Style.space(8)
                          anchors.verticalCenter: parent.verticalCenter
                          text: card.modelData.pattern
                          color: _webPalette.faint
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }

                        Kit.ActionButton {
                          focusable: true
                          Accessible.role: Accessible.Button
                          Accessible.name: card.isCurrent && root.running
                            ? "Pause " + card.modelData.name
                            : (card.isCurrent && root.paused ? "Resume " : "Start ") + card.modelData.name
                          Accessible.description: card.modelData.pattern
                          id: playButton
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          text: card.isCurrent && root.running ? "" : ""   // fa-pause / fa-play
                          bordered: true
                          foreground: root.toneColor(card.modelData.tone)
                          onClicked: {
                            if (!root.hostWidget) return
                            if (card.isCurrent && (root.running || root.paused)) root.hostWidget.toggleSession()
                            else root.hostWidget.startSession(card.modelData.id, card.modelData.defaultCycles, false)
                          }
                        }
                      }

                      // ---- detail, one card at a time --------------------
                      Column {
                        width: parent.width
                        visible: card.expanded
                        spacing: Style.space(6)

                        Text {
                          width: parent.width
                          text: card.modelData.blurb || ""
                          color: _webPalette.faint
                          wrapMode: Text.WordWrap
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          width: parent.width
                          visible: !!card.modelData.use
                          text: "Good for: " + (card.modelData.use || "")
                          color: _webPalette.faint
                          wrapMode: Text.WordWrap
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }

                        // A caution belongs before you start, not after.
                        Rectangle {
                          width: parent.width
                          visible: !!card.modelData.warning
                          height: warnText.implicitHeight + Style.space(12)
                          radius: Style.cornerRadius
                          color: "transparent"
                          border.width: 1
                          border.color: _webPalette.warning

                          Text {
                            id: warnText
                            anchors.centerIn: parent
                            width: parent.width - Style.space(12)
                            text: card.modelData.warning || ""
                            color: _webPalette.warning
                            wrapMode: Text.WordWrap
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                          }
                        }

                        Row {
                          width: parent.width
                          spacing: Style.space(8)

                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Model.formatDuration(Model.sessionSeconds(card.modelData, card.modelData.defaultCycles))
                              + " · " + card.modelData.defaultCycles + " cycles"
                            color: _webPalette.faint
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                          }

                          Item { width: 1; height: 1 }
                        }

                        Row {
                          spacing: Style.space(8)
                          visible: card.modelData.family === "custom"

                          Kit.ActionButton {
                            focusable: true
                            Accessible.role: Accessible.Button
                            Accessible.name: text
                            text: "Edit"
                            bordered: true
                            foreground: root.barForeground
                            onClicked: { root.editingId = card.modelData.id; root.editorOpen = true }
                          }
                          Kit.ActionButton {
                            focusable: true
                            Accessible.role: Accessible.Button
                            Accessible.name: text
                            text: "Delete"
                            bordered: true
                            foreground: _webPalette.negative
                            onClicked: if (root.hostWidget) root.hostWidget.deleteCustomTechnique(card.modelData.id)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            Kit.ActionButton {
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: text
              width: parent.width
              text: "  New pattern"
              bordered: true
              foreground: root.barForeground
              onClicked: { root.editingId = ""; root.editorOpen = true }
            }
          }

          PanelSeparator { width: parent.width; visible: !root.editorOpen; foreground: root.barForeground }

          // ================= metrics ====================================
          Metrics {
            width: parent.width
            visible: !root.editorOpen
            hostWidget: root.hostWidget
            foreground: root.barForeground
          }

          PanelSeparator { width: parent.width; visible: !root.editorOpen; foreground: root.barForeground }

          // ================= settings ===================================
          Column {
            width: parent.width
            visible: !root.editorOpen
            spacing: Style.space(8)

            Kit.SectionHeading { width: parent.width; text: "Settings" }

            Toggle {
              width: parent.width
              Accessible.role: Accessible.CheckBox
              Accessible.name: label
              Accessible.checkable: true
              Accessible.checked: checked
              Accessible.description: description
              Accessible.onPressAction: clicked()
              Accessible.onToggleAction: clicked()
              label: "Full screen guide on start"
              description: "Raise the breath overlay whenever a session begins"
              checked: root.config.overlayOnStart === true
              foreground: root.barForeground
              onClicked: root.updateConfig({ overlayOnStart: !root.config.overlayOnStart })
            }

            Toggle {
              width: parent.width
              Accessible.role: Accessible.CheckBox
              Accessible.name: label
              Accessible.checkable: true
              Accessible.checked: checked
              Accessible.description: description
              Accessible.onPressAction: clicked()
              Accessible.onToggleAction: clicked()
              label: "Silent"
              description: "No phase cues and no completion sound, on every session"
              checked: root.config.silent === true
              foreground: root.barForeground
              onClicked: root.updateConfig({ silent: !root.config.silent })
            }

            Toggle {
              width: parent.width
              Accessible.role: Accessible.CheckBox
              Accessible.name: label
              Accessible.checkable: true
              Accessible.checked: checked
              Accessible.description: description
              Accessible.onPressAction: clicked()
              Accessible.onToggleAction: clicked()
              label: "Loop"
              description: "When a session finishes, start it again until you stop"
              checked: root.config.loop === true
              foreground: root.barForeground
              onClicked: root.updateConfig({ loop: !root.config.loop })
            }

            Toggle {
              width: parent.width
              Accessible.role: Accessible.CheckBox
              Accessible.name: label
              Accessible.checkable: true
              Accessible.checked: checked
              Accessible.description: description
              Accessible.onPressAction: clicked()
              Accessible.onToggleAction: clicked()
              label: "Spoken cues"
              description: "Say \"In\", \"Out\", \"Hold\" at each phase instead of a chime"
              checked: root.config.cueVoice === true
              foreground: root.barForeground
              onClicked: root.updateConfig({ cueVoice: !root.config.cueVoice })
            }

            Toggle {
              width: parent.width
              Accessible.role: Accessible.CheckBox
              Accessible.name: label
              Accessible.checkable: true
              Accessible.checked: checked
              Accessible.onPressAction: clicked()
              Accessible.onToggleAction: clicked()
              label: "Notify when a session finishes"
              checked: root.config.notifyOnEnd === true
              foreground: root.barForeground
              onClicked: root.updateConfig({ notifyOnEnd: !root.config.notifyOnEnd })
            }

            Toggle {
              width: parent.width
              Accessible.role: Accessible.CheckBox
              Accessible.name: label
              Accessible.checkable: true
              Accessible.checked: checked
              Accessible.description: description
              Accessible.onPressAction: clicked()
              Accessible.onToggleAction: clicked()
              label: "Reduce motion"
              description: "Keep the countdown and rings, drop the breathing animation"
              checked: root.config.reduceMotion === true
              foreground: root.barForeground
              onClicked: root.updateConfig({ reduceMotion: !root.config.reduceMotion })
            }

            Toggle {
              width: parent.width
              Accessible.role: Accessible.CheckBox
              Accessible.name: label
              Accessible.checkable: true
              Accessible.checked: checked
              Accessible.onPressAction: clicked()
              Accessible.onToggleAction: clicked()
              label: "Countdown on the bar"
              checked: root.config.showBarCountdown === true
              foreground: root.barForeground
              onClicked: root.updateConfig({ showBarCountdown: !root.config.showBarCountdown })
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(96)
                text: "Overlay dim"
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              PanelSlider {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(150)
                bar: root.bar
                minimum: 0.3
                maximum: 1.0
                step: 0.02
                value: root.config.overlayDim !== undefined ? root.config.overlayDim : 0.82
                onValueChanged: if (Math.abs(value - root.config.overlayDim) > 0.005) root.updateConfig({ overlayDim: value })
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round((root.config.overlayDim || 0.82) * 100) + "%"
                color: _webPalette.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            NumberField {
              id: cycleField
              label: "Default cycles"
              value: root.config.defaultCycles || 8
              from: 1
              to: 60
              foreground: root.barForeground
              onModified: function (v) { root.updateConfig({ defaultCycles: v }) }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                id: phaseSoundLabel
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(84)
                text: "Phase cue"
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              TextField {
                id: phaseSoundField
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - phaseSoundLabel.width - Style.space(16)
                text: root.config.phaseSound || ""
                foreground: root.barForeground
                placeholderText: "default · /path/to/sound.oga"
                onEditingFinished: root.updateConfig({ phaseSound: text })
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                id: endSoundLabel
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(84)
                text: "End cue"
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              TextField {
                id: endSoundField
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - endSoundLabel.width - Style.space(16)
                text: root.config.endSound || ""
                foreground: root.barForeground
                placeholderText: "default · /path/to/sound.oga"
                onEditingFinished: root.updateConfig({ endSound: text })
              }
            }

            // ---- nudges ------------------------------------------------
            PanelSeparator { width: parent.width; foreground: root.barForeground }

            Toggle {
              width: parent.width
              Accessible.role: Accessible.CheckBox
              Accessible.name: label
              Accessible.checkable: true
              Accessible.checked: checked
              Accessible.description: description
              Accessible.onPressAction: clicked()
              Accessible.onToggleAction: clicked()
              label: "Remind me to breathe"
              description: "A quiet nudge when you have not breathed in a while"
              checked: root.config.nudge && root.config.nudge.enabled === true
              foreground: root.barForeground
              onClicked: root.updateConfig({ nudge: { enabled: !(root.config.nudge && root.config.nudge.enabled) } })
            }

            Column {
              width: parent.width
              visible: root.config.nudge && root.config.nudge.enabled === true
              spacing: Style.space(6)

              NumberField {
                id: nudgeField
                label: "Every (minutes)"
                value: root.config.nudge ? (root.config.nudge.everyMinutes || 90) : 90
                from: 5
                to: 600
                stepSize: 5
                foreground: root.barForeground
                onModified: function (v) { root.updateConfig({ nudge: { everyMinutes: v } }) }
              }

              Text {
                width: parent.width
                text: "Quiet between " + (root.config.nudge ? root.config.nudge.quietFrom : "22:00")
                  + " and " + (root.config.nudge ? root.config.nudge.quietTo : "08:00")
                  + ". Edit the hours in breathe-config.json."
                color: _webPalette.faint
                wrapMode: Text.WordWrap
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
