import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Desk Pet's settings + stats panel: pick a pet, feed/play/pet it, see its
// mood bars, and tune how chatty it is. Everything here acts on hostWidget,
// which owns the state and does the actual Model.js math.
Panel {
  id: root
  moduleName: "alteringux.deskpet"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var st: hostWidget ? hostWidget.liveState : Model.defaultState()
  readonly property var pet: hostWidget ? hostWidget.pet : Model.petById("cat")
  readonly property string mood: hostWidget ? hostWidget.mood : "content"
  readonly property var speechPresets: [1.5, 3, 6, 15]
  readonly property var level: hostWidget ? hostWidget.levelInfo : Model.levelInfo(Model.defaultState())
  readonly property var unlockedIds: hostWidget ? hostWidget.unlockedIds : []
  readonly property var seasonalEvent: hostWidget ? Model.seasonalEvent(hostWidget.monthValue, hostWidget.dayValue) : null

  function moodDescription(m) {
    if (m === "asleep") return "Dozing off"
    if (m === "hungry") return "Could use a snack"
    if (m === "grumpy") return "In a mood"
    if (m === "ecstatic") return "Having the best day"
    if (m === "meh") return "Doing okay"
    return "Content"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(560)))

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: content.implicitHeight

        Column {
          id: content
          width: parent.width
          spacing: Style.space(14)

          Kit.PanelHead {
            glyph: (hostWidget && hostWidget.state.shiny ? "✨" : "") + root.pet.glyph
            title: root.pet.name + (hostWidget && hostWidget.state.shiny ? " ✨ (Shiny!)" : "")
            meta: (root.seasonalEvent ? root.seasonalEvent.glyph + " " + root.seasonalEvent.name.toUpperCase() + "  ·  " : "")
              + root.moodDescription(root.mood).toUpperCase() + "  ·  LVL " + root.level.level + " " + root.level.title.toUpperCase()
            foreground: root.barForeground
          }

          Text {
            width: content.width
            text: root.pet.tagline + "  ·  " + root.level.total + "/" + root.level.nextAt + " to next level"
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {}

          // ---- mood bars ---------------------------------------------------
          Column {
            width: content.width
            spacing: Style.space(8)

            Repeater {
              model: [
                { label: "Happiness", value: root.st.happiness, tone: "positive" },
                { label: "Fullness", value: root.st.fullness, tone: "warning" },
                { label: "Energy", value: root.st.energy, tone: "info" }
              ]

              Column {
                required property var modelData
                width: content.width
                spacing: Style.space(3)

                Item {
                  width: parent.width
                  height: Math.max(labelText.implicitHeight, pctText.implicitHeight)

                  Text {
                    id: labelText
                    anchors.left: parent.left
                    text: modelData.label
                    color: root.barForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    id: pctText
                    anchors.right: parent.right
                    text: Math.round(modelData.value) + "%"
                    color: Kit.Palette.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Rectangle {
                  width: parent.width
                  height: Style.space(6)
                  radius: height / 2
                  color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.15)

                  Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: Math.max(parent.height, parent.width * Model.clamp(modelData.value, 0, 100) / 100)
                    color: modelData.tone === "positive" ? Kit.Palette.positive
                      : modelData.tone === "warning" ? Kit.Palette.warning
                      : Kit.Palette.info
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                  }
                }
              }
            }
          }

          PanelSeparator {}

          // ---- actions -------------------------------------------------
          Row {
            spacing: Style.space(8)

            Button {
              text: "Feed"
              foreground: root.barForeground
              bordered: true
              onClicked: if (hostWidget) hostWidget.feedPet()
            }
            Button {
              text: "Play"
              foreground: root.barForeground
              bordered: true
              onClicked: if (hostWidget) hostWidget.playWithPet()
            }
            Button {
              text: "Pet"
              foreground: root.barForeground
              bordered: true
              onClicked: if (hostWidget) hostWidget.pokePet()
            }
            Button {
              text: root.st.asleep ? "Wake" : "Sleep"
              foreground: root.barForeground
              bordered: true
              onClicked: if (hostWidget) hostWidget.toggleSleep()
            }
          }

          PanelSeparator {}

          // ---- pet picker ------------------------------------------------
          Text {
            width: content.width
            text: "Pick a pet"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Flow {
            width: content.width
            spacing: Style.space(6)

            Repeater {
              model: Model.allPets()
              Button {
                required property var modelData
                text: modelData.glyph + " " + modelData.name
                foreground: root.barForeground
                bordered: hostWidget && hostWidget.state.petId === modelData.id
                onClicked: if (hostWidget) hostWidget.selectPet(modelData.id)
              }
            }
          }

          PanelSeparator {}

          // ---- wardrobe ---------------------------------------------------
          Text {
            width: content.width
            text: "Wardrobe"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Flow {
            width: content.width
            spacing: Style.space(6)

            Button {
              text: "None"
              foreground: root.barForeground
              bordered: hostWidget && hostWidget.state.accessoryId === null
              onClicked: if (hostWidget) hostWidget.equipAccessory(null)
            }

            Repeater {
              model: Model.ACCESSORIES
              Button {
                required property var modelData
                readonly property bool unlocked: root.unlockedIds.indexOf(modelData.unlockedBy) >= 0
                text: (unlocked ? modelData.glyph : "🔒") + " " + modelData.name
                foreground: unlocked ? root.barForeground : Kit.Palette.faint
                bordered: hostWidget && hostWidget.state.accessoryId === modelData.id
                enabled: unlocked
                onClicked: if (hostWidget) hostWidget.equipAccessory(modelData.id)
              }
            }
          }

          PanelSeparator {}

          // ---- movement ---------------------------------------------------
          Text {
            width: content.width
            text: "Movement"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Row {
            spacing: Style.space(6)

            Repeater {
              model: Model.ROAM_MODES
              Button {
                required property var modelData
                text: modelData === "off" ? "Still" : (modelData === "walk" ? "Walk" : "Gallop")
                foreground: root.barForeground
                bordered: hostWidget && hostWidget.state.roamMode === modelData
                onClicked: if (hostWidget) hostWidget.setRoamMode(modelData)
              }
            }
          }

          PanelSeparator {}

          // ---- chatter --------------------------------------------------
          Text {
            width: content.width
            text: "How chatty"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Row {
            spacing: Style.space(6)

            Repeater {
              model: root.speechPresets
              Button {
                required property var modelData
                text: modelData <= 1.5 ? "Very Chatty" : (modelData <= 3 ? "Chatty" : (modelData <= 6 ? "Normal" : "Quiet"))
                foreground: root.barForeground
                bordered: hostWidget && hostWidget.state.speechFreqMin === modelData
                onClicked: if (hostWidget) hostWidget.setSpeechFreq(modelData)
              }
            }
          }

          PanelSeparator {}

          Toggle {
            width: content.width
            activeFocusOnTab: false
            label: "Show on desktop"
            description: (hostWidget && hostWidget.state.enabled) ? "Floating on top of everything" : "Hidden"
            checked: hostWidget && hostWidget.state.enabled
            foreground: root.barForeground
            onClicked: if (hostWidget) hostWidget.setEnabled(!hostWidget.state.enabled)
          }

          Toggle {
            width: content.width
            activeFocusOnTab: false
            label: "Mute chatter"
            description: (hostWidget && hostWidget.state.muted) ? "Speech bubble silenced" : "Speaks up sometimes"
            checked: hostWidget && hostWidget.state.muted
            foreground: root.barForeground
            onClicked: if (hostWidget) hostWidget.setMuted(!hostWidget.state.muted)
          }

          PanelSeparator {}

          // ---- screen watch ------------------------------------------------
          Toggle {
            width: content.width
            activeFocusOnTab: false
            label: "Let it look at your screen"
            description: (hostWidget && hostWidget.state.screenWatchEnabled)
              ? "Sends a screenshot to NanoGPT (external AI) every so often for a comment"
              : "Off — comments are canned lines only, nothing leaves this machine"
            checked: hostWidget && hostWidget.state.screenWatchEnabled
            foreground: root.barForeground
            onClicked: if (hostWidget) hostWidget.setScreenWatchEnabled(!hostWidget.state.screenWatchEnabled)
          }

          Row {
            visible: hostWidget && hostWidget.state.screenWatchEnabled
            spacing: Style.space(6)

            Repeater {
              model: [15, 30, 60]
              Button {
                required property var modelData
                text: modelData <= 15 ? "Often" : (modelData <= 30 ? "Normal" : "Rare")
                foreground: root.barForeground
                bordered: hostWidget && hostWidget.state.screenLookFreqMin === modelData
                onClicked: if (hostWidget) hostWidget.setScreenLookFreq(modelData)
              }
            }
          }

          PanelSeparator {}

          // ---- trophy case --------------------------------------------------
          Text {
            width: content.width
            text: "Trophy case (" + root.unlockedIds.length + "/" + Model.ACHIEVEMENTS.length + ")"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Flow {
            width: content.width
            spacing: Style.space(6)

            Repeater {
              model: Model.ACHIEVEMENTS
              Row {
                required property var modelData
                readonly property bool unlocked: root.unlockedIds.indexOf(modelData.id) >= 0
                spacing: Style.space(4)

                Text {
                  text: unlocked ? "🏆" : "🔒"
                  font.pixelSize: Style.font.bodySmall
                  opacity: unlocked ? 1 : 0.5
                }
                Text {
                  text: modelData.name
                  color: unlocked ? root.barForeground : Kit.Palette.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          PanelSeparator {}

          Text {
            width: content.width
            visible: hostWidget !== null
            text: hostWidget
              ? ("Adopted " + hostWidget.ageDaysValue + " day" + (hostWidget.ageDaysValue === 1 ? "" : "s") + " ago  ·  "
                + Math.round(root.st.totalPokes || 0) + " pets  ·  " + Math.round(root.st.totalFeeds || 0) + " snacks")
              : ""
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // Explanatory sentence, not a status tag -- ADR-0005's hint role
          // (Kit.Palette.faint at caption size), not the meta treatment.
          Text {
            text: "Right-click the pet on your desktop to open this panel too. Esc: close"
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: content.width
          }
        }
      }
    }
  }
}
