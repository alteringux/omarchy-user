import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Dashboard overlay: a small grid of cards (news, system, notes) anchored
// under the bar icon. Read-only view over BarWidget's state file — all
// writes happen in the bin/ scripts, this just renders whatever is current.
Panel {
  id: root
  moduleName: "alteringux.dashboard"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var state: hostWidget ? hostWidget.state : Model.defaultState()
  readonly property bool refreshing: hostWidget ? hostWidget.refreshing : false

  readonly property color cardBackground: Util.alpha(root.barForeground, 0.05)
  readonly property color cardBorder: Util.alpha(root.barForeground, 0.14)

  readonly property var guard: Kit.BugGuard.create("alteringux.dashboard", function(argv) { Quickshell.execDetached(argv) })

  function clearNotes() {
    guard.run("clearNotes", function() {
      if (!hostWidget) return
      notesClearProc.command = ["bash", hostWidget.pluginDir + "/bin/omarchy-dashboard-note", "--clear"]
      notesClearProc.running = true
    })
  }

  function trackNewsClick(title) {
    guard.run("trackNewsClick", function() {
      if (!hostWidget || !title) return
      trackProc.command = ["bash", hostWidget.pluginDir + "/bin/omarchy-dashboard-track", title]
      trackProc.running = true
    })
  }

  Process {
    id: notesClearProc
    running: false
  }

  Process {
    id: trackProc
    running: false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(620))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(480)))

    PanelKeyCatcher {
      anchors.fill: parent

      onCloseRequested: root.close()
      onActivateRequested: if (hostWidget) hostWidget.runRefresh()
      onDeleteRequested: if (root.state.notes.items.length > 0) root.clearNotes()

    Flickable {
      anchors.fill: parent
      clip: true
      contentHeight: content.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.panelGap

        RowLayout {
          width: parent.width
          spacing: Style.spacing.md

          PanelSectionHeader {
            text: "DASHBOARD"
            foreground: root.barForeground
            Layout.fillWidth: true
          }

          Text {
            visible: root.refreshing
            text: "refreshing…"
            color: root.barForeground
            opacity: 0.55
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Button {
            text: "Refresh"
            foreground: root.barForeground
            bordered: true
            onClicked: if (hostWidget) hostWidget.runRefresh()
          }
        }

        // ---- Digest: a periodic one-line AI summary of the dashboard,
        // generated locally via the `claude` CLI (see bin/omarchy-dashboard-refresh).
        Text {
          visible: !!root.state.digest.text
          width: parent.width
          text: "✨ " + root.state.digest.text
          wrapMode: Text.WordWrap
          color: root.barForeground
          opacity: 0.75
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        // ---- News card (full width)
        Rectangle {
          width: parent.width
          height: newsColumn.implicitHeight + Style.spacing.panelPadding * 2
          radius: Style.cornerRadius
          color: root.cardBackground
          border.width: 1
          border.color: root.cardBorder

          Column {
            id: newsColumn
            anchors.fill: parent
            anchors.margins: Style.spacing.panelPadding
            spacing: Style.spacing.lg

            RowLayout {
              width: parent.width
              Text {
                text: "📰 Top Stories"
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                Layout.fillWidth: true
              }
              Text {
                text: Model.formatRelative(root.state.news.updatedAt)
                color: root.barForeground
                opacity: 0.5
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              visible: root.state.news.items.length === 0
              text: root.refreshing ? "Fetching headlines…" : "No headlines yet — click Refresh."
              color: root.barForeground
              opacity: 0.55
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.state.news.items
              delegate: Column {
                required property var modelData
                width: newsColumn.width
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  text: modelData.title || ""
                  wrapMode: Text.WordWrap
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: guard.run("news.onClicked", function() {
                      root.trackNewsClick(modelData.title)
                      if (modelData.url) Quickshell.execDetached(["xdg-open", modelData.url])
                    })
                  }
                }
                Text {
                  visible: !!modelData.meta
                  text: modelData.meta || ""
                  color: root.barForeground
                  opacity: 0.5
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.spacing.panelGap

          // ---- System card
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            height: systemColumn.implicitHeight + Style.spacing.panelPadding * 2
            radius: Style.cornerRadius
            color: root.cardBackground
            border.width: 1
            border.color: root.cardBorder

            Column {
              id: systemColumn
              anchors.fill: parent
              anchors.margins: Style.spacing.panelPadding
              spacing: Style.spacing.lg

              Text {
                text: "🖥️ System"
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                visible: root.state.system.items.length === 0
                text: root.state.system.updatedAt ? "Up to date" : "Checking…"
                color: root.barForeground
                opacity: 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: root.state.system.items
                delegate: Text {
                  required property var modelData
                  width: systemColumn.width
                  text: modelData.text || ""
                  wrapMode: Text.WordWrap
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          // ---- Notes card
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            height: notesColumn.implicitHeight + Style.spacing.panelPadding * 2
            radius: Style.cornerRadius
            color: root.cardBackground
            border.width: 1
            border.color: root.cardBorder

            Column {
              id: notesColumn
              anchors.fill: parent
              anchors.margins: Style.spacing.panelPadding
              spacing: Style.spacing.lg

              RowLayout {
                width: parent.width
                Text {
                  text: "📝 Notes"
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  Layout.fillWidth: true
                }
                Button {
                  visible: root.state.notes.items.length > 0
                  text: "Clear"
                  foreground: root.barForeground
                  bordered: true
                  onClicked: root.clearNotes()
                }
              }

              Text {
                visible: root.state.notes.items.length === 0
                text: "Empty. Push a line via:\nomarchy-dashboard-note \"text\""
                wrapMode: Text.WordWrap
                color: root.barForeground
                opacity: 0.55
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: root.state.notes.items
                delegate: Column {
                  required property var modelData
                  width: notesColumn.width
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: modelData.text || ""
                    wrapMode: Text.WordWrap
                    color: root.barForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: Model.formatRelative(modelData.at)
                    color: root.barForeground
                    opacity: 0.5
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }

        PanelSeparator {}

        Text {
          text: "Enter: refresh  ·  X: clear notes  ·  Esc: close"
          color: Qt.darker(root.barForeground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
    }
  }
}
