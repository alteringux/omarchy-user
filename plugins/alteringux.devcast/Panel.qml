import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Devcast overlay: build a replay from the latest Claude Code session, browse
// past devcasts, open their replay.html / exported video.
Panel {
  id: root
  moduleName: "alteringux.devcast"
  ipcTarget: "alteringux.devcast"
  manageIpc: false

  readonly property var guard: Kit.BugGuard.create("alteringux.devcast", function(argv) { Quickshell.execDetached(argv) })

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var index: (hostWidget && hostWidget.index) ? hostWidget.index : null
  readonly property var casts: (root.index && root.index.casts) ? root.index.casts : []
  readonly property var latest: (root.index && root.index.latest) ? root.index.latest : null
  readonly property bool building: !!(hostWidget && hostWidget.building)
  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-devcast"

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function openPath(p) {
    if (p && p.length) Quickshell.execDetached(["xdg-open", p])
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onActivateRequested: { if (root.hostWidget) root.hostWidget.buildLatest(true) }

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: body.implicitHeight

        Column {
          id: body
          width: parent.width
          spacing: Style.space(14)

          Kit.PanelHead {
            width: parent.width
            glyph: "" // nf-fa-film
            title: "Devcast"
            meta: root.building
              ? "BUILDING…"
              : (root.latest ? (root.latest.summary || "") : "NO DEVCASTS YET")
            foreground: root.barForeground
          }

          // ── build from latest session ──────────────────────────────
          Rectangle {
            width: parent.width
            height: Style.space(38)
            radius: Style.cornerRadius
            color: buildArea.containsMouse
              ? Style.hoverFillFor(root.barForeground, Color.accent)
              : Util.alpha(root.barForeground, 0.1)
            opacity: root.building ? 0.5 : 1.0

            Text {
              anchors.centerIn: parent
              text: root.building ? "Building replay…" : "Build replay from latest session"
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
            MouseArea {
              id: buildArea
              anchors.fill: parent
              hoverEnabled: true
              enabled: !root.building
              cursorShape: Qt.PointingHandCursor
              onClicked: { if (root.hostWidget) root.hostWidget.buildLatest(true) }
            }
          }

          Text {
            width: parent.width
            text: "Also: /devcast in Claude Code, or `omarchy-devcast build <session-id>`. "
                + "Secrets are auto-redacted; replays stay under ~/.local/state/omarchy/devcasts/."
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          Kit.MetaText { width: implicitWidth; content: "RECENT"; foreground: root.barForeground }

          Repeater {
            model: root.casts

            delegate: Rectangle {
              required property var modelData
              width: parent.width
              height: rowCol.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: rowArea.containsMouse ? Util.alpha(root.barForeground, 0.08) : Util.alpha(root.barForeground, 0.04)

              MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openPath(modelData.html)
              }

              Column {
                id: rowCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(10)
                spacing: Style.space(3)

                Text {
                  width: parent.width
                  text: modelData.title || "session"
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: modelData.summary || ""
                  color: Qt.darker(root.barForeground, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                Row {
                  spacing: Style.space(8)
                  Repeater {
                    model: [
                      { t: "Watch", p: modelData.html, on: (modelData.html || "").length > 0 },
                      { t: "Video", p: modelData.video, on: (modelData.video || "").length > 0 }
                    ]
                    delegate: Rectangle {
                      required property var modelData
                      visible: modelData.on
                      width: chip.implicitWidth + Style.space(16)
                      height: Style.space(22)
                      radius: height / 2
                      color: chipArea.containsMouse ? Util.alpha(Color.accent, 0.28) : Util.alpha(root.barForeground, 0.1)
                      Text {
                        id: chip
                        anchors.centerIn: parent
                        text: parent.modelData.t
                        color: root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                      }
                      MouseArea {
                        id: chipArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openPath(parent.modelData.p)
                      }
                    }
                  }
                }
              }
            }
          }

          Kit.EmptyState {
            visible: root.casts.length === 0 && !root.building
            text: "No devcasts yet"
            hint: "Build one from your last Claude Code session with the button above."
            foreground: root.barForeground
          }
        }
      }
    }
  }
}
