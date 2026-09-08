import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// The conductor's cockpit: pick a ritual to run (Focus / Morning / Wind-down
// or your own), watch the active ritual march through its steps, and read the
// combined live state of every other alteringux plugin in one place.
Panel {
  id: root
  moduleName: "alteringux.conductor"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var guard: Kit.BugGuard.create("alteringux.conductor", function (argv) { Quickshell.execDetached(argv) })

  readonly property var state: hostWidget ? hostWidget.state : Model.defaultState()
  readonly property var snapshot: hostWidget ? hostWidget.snapshot : ({})
  readonly property var rituals: hostWidget ? hostWidget.rituals : []
  readonly property bool active: hostWidget ? hostWidget.active : false
  readonly property var counts: Model.stepCounts(root.state)
  readonly property var cockpit: Model.snapshotLines(root.snapshot)

  property bool inputFocused: false

  // Ticks while a ritual is running so the "Running Xm" readout stays live
  // without a per-frame binding; cheap since it only runs while active.
  property double nowMs: Date.now()
  Timer {
    interval: 30000
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  function runRitual(id) {
    guard.run("runRitual", function () {
      if (!hostWidget) return
      hostWidget.runRitual(id, taskField.text)
      taskField.text = ""
    })
  }

  onOpenedChanged: {
    if (opened && hostWidget) {
      hostWidget.refreshRituals()
      hostWidget.refreshSnapshot()
    }
  }

  Timer {
    interval: 8000
    repeat: true
    running: root.opened
    onTriggered: if (hostWidget) hostWidget.refreshSnapshot()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(560)))
    focusTarget: taskField

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
            glyph: ""
            title: "Conductor"
            meta: root.active
              ? (Model.ritualName(root.state) + "  ·  " + Model.phaseLabel(root.state))
              : "idle"
            foreground: root.barForeground
          }

          // ---- optional label carried into the next ritual you run -----
          TextField {
            id: taskField
            width: content.width
            placeholderText: "Label for this session (optional)…"
            foreground: root.barForeground
            onActiveFocusChanged: root.inputFocused = activeFocus
            onAccepted: {
              // Only auto-launch when there's exactly one ritual to mean —
              // with two or more, Enter used to fire rituals[0] regardless
              // of which card the label was meant for.
              if (root.rituals.length === 1 && !root.active) root.runRitual(root.rituals[0].id)
            }
          }

          // ---- ritual catalogue --------------------------------------
          Kit.SectionHeading {
            width: content.width
            text: "Rituals"
            uppercase: true
            rule: true
            foreground: root.barForeground
          }

          Kit.EmptyState {
            visible: root.rituals.length === 0
            text: "No rituals found."
            hint: "Add one at ~/.config/omarchy/conductor/rituals/<id>.json"
            foreground: root.barForeground
          }

          Repeater {
            model: root.rituals
            delegate: Kit.Card {
              id: rcard
              required property var modelData

              width: content.width
              color: rmouse.containsMouse && !root.active
                ? Util.alpha(root.barForeground, 0.10)
                : Kit.Palette.cardBg
              opacity: root.active ? 0.5 : 1.0
              foreground: root.barForeground
              body: rcol

              Column {
                id: rcol
                width: rcard.bodyWidth
                spacing: Style.space(3)

                Text {
                  text: rcard.modelData.label
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  width: rcol.width
                  text: Model.ritualSubtitle(rcard.modelData)
                  color: Kit.Palette.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                Text {
                  visible: !!rcard.modelData.description
                  width: rcol.width
                  wrapMode: Text.WordWrap
                  text: rcard.modelData.description
                  // Explanatory sentence, not a status tag: hint role per
                  // docs/adr/0005-panel-text-hierarchy.md, not a darkened
                  // foreground.
                  color: Kit.Palette.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }

              MouseArea {
                id: rmouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.active
                cursorShape: root.active ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: root.runRitual(rcard.modelData.id)
              }
            }
          }

          // ---- active ritual progress ------------------------------
          Kit.SectionHeading {
            visible: root.active
            width: content.width
            text: "In flight"
            uppercase: true
            rule: true
            foreground: root.barForeground
          }

          Text {
            visible: root.active
            width: content.width
            text: Model.progressText(root.state)
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            visible: root.active && root.state.startedAt > 0
            width: content.width
            text: "Running " + Model.fmtMs(Math.max(0, root.nowMs - root.state.startedAt))
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Column {
            visible: root.active
            width: content.width
            spacing: Style.space(2)

            Repeater {
              model: root.active ? root.state.steps : []
              delegate: Row {
                required property var modelData
                width: content.width
                spacing: Style.space(8)

                Text {
                  text: Model.stepGlyph(modelData.status)
                  color: modelData.status === "ok" ? Kit.Palette.positive
                    : modelData.status === "failed" ? Kit.Palette.negative
                    : modelData.status === "skipped" ? Kit.Palette.warning
                    : Kit.Palette.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  width: Style.space(14)
                  horizontalAlignment: Text.AlignHCenter
                }
                Text {
                  width: parent.width - Style.space(14) - parent.spacing * 2 - whenTag.implicitWidth
                  elide: Text.ElideRight
                  text: Model.stepText(modelData)
                  color: modelData.status === "pending" ? Qt.darker(root.barForeground, 1.4) : root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  id: whenTag
                  text: modelData.when
                  color: Kit.Palette.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Row {
            visible: root.active
            width: content.width
            spacing: Style.space(8)

            Button {
              text: "Advance"
              foreground: root.barForeground
              bordered: true
              enabled: root.counts.pending > 0
              onClicked: if (hostWidget) hostWidget.advance()
            }
            Button {
              text: "Stop"
              foreground: root.barForeground
              bordered: true
              onClicked: if (hostWidget) hostWidget.stopRitual()
            }
            Button {
              text: "Abort"
              foreground: root.barForeground
              bordered: true
              onClicked: if (hostWidget) hostWidget.abortRitual()
            }
          }

          Text {
            visible: !root.active && root.state.lastSummary && root.state.lastSummary.length > 0
            width: content.width
            text: "Last run: " + root.state.lastSummary
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          // ---- cockpit: every plugin at a glance -------------------
          Kit.SectionHeading {
            width: content.width
            text: "Cockpit"
            uppercase: true
            rule: true
            foreground: root.barForeground
          }

          Kit.EmptyState {
            visible: root.cockpit.length === 0
            text: "No plugin state yet."
            hint: "Nothing running to report."
            foreground: root.barForeground
          }

          Column {
            width: content.width
            spacing: Style.space(4)

            Repeater {
              model: root.cockpit
              delegate: Row {
                required property var modelData
                width: content.width
                spacing: Style.space(10)

                Text {
                  text: modelData.label
                  color: Kit.Palette.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  width: Style.space(84)
                }
                Text {
                  width: parent.width - Style.space(84) - parent.spacing
                  wrapMode: Text.WordWrap
                  text: modelData.value
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          PanelSeparator {}

          Row {
            width: content.width
            spacing: Style.space(12)

            Text {
              text: "↻ Refresh cockpit"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: if (hostWidget) hostWidget.refreshSnapshot()
              }
            }
            Text {
              text: "Right-click widget: advance  ·  middle-click: stop  ·  Esc: close"
              color: Qt.darker(root.barForeground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
