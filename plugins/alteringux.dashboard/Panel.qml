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
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.dashboard"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var state: hostWidget ? hostWidget.state : Model.defaultState()
  readonly property bool refreshing: hostWidget ? hostWidget.refreshing : false

  readonly property color cardBackground: _webPalette.cardBackgroundFor(root.barForeground)
  readonly property color cardBorder: _webPalette.cardBorderFor(root.barForeground)
  property string clearStatus: ""
  property string clearErrorOutput: ""
  onClearStatusChanged: {
    var message = root.clearStatus
    if (!root.opened || !message) return
    Qt.callLater(function() {
      if (root.opened && clearStatusText.visible && root.clearStatus === message)
        clearStatusText.Accessible.announce(message)
    })
  }

  readonly property var guard: Kit.BugGuard.create("alteringux.dashboard", function(argv) { Quickshell.execDetached(argv) })

  function clearNotes() {
    if (!hostWidget || notesClearProc.running) return
    guard.run("clearNotes", function() {
      root.clearStatus = "Clearing notes…"
      root.clearErrorOutput = ""
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
    stderr: StdioCollector { onStreamFinished: root.clearErrorOutput = this.text }
    onExited: function (code) {
      if (code === 0) {
        root.clearStatus = "Notes cleared."
        if (hostWidget && typeof hostWidget.reloadState === "function") hostWidget.reloadState()
      } else {
        var detail = String(root.clearErrorOutput || "").trim().split(/\r?\n/)[0].slice(0, 180)
        root.clearStatus = "Could not clear notes: " + (detail || ("process exited with code " + code))
      }
    }
  }

  Process {
    id: trackProc
    running: false
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(620))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(480)))

    Kit.PanelKeys {
      anchors.fill: parent

      onCloseRequested: root.close()
      onActivateRequested: if (hostWidget) hostWidget.runRefresh()
      onDeleteRequested: if (root.state.notes.items.length > 0) root.clearNotes()
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Refresh the dashboard", context: "Dashboard · shortcut focus" },
        { keys: "X", description: "Clear dashboard notes", context: "Dashboard · shortcut focus" }
      ]

    Kit.PanelScroll {
      anchors.fill: parent
      contentHeight: content.implicitHeight

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.panelGap

        Kit.PanelHead {
          glyph: "\uf1ea"   // nf-fa-newspaper_o, matches the bar widget
          title: "Dashboard"
          meta: root.refreshing ? "refreshing…" : ""
          foreground: root.barForeground
          trailingControl: Component {
            Kit.ActionButton {
              text: "Refresh"
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: "Refresh dashboard"
              foreground: root.barForeground
              bordered: true
              onClicked: if (hostWidget) hostWidget.runRefresh()
            }
          }
        }

        // Keep the panel's keyboard help at the top of the scroll region so
        // long dashboards do not bury the only shortcut hint below the fold.
        Text {
          width: parent.width
          text: "Enter: refresh  ·  X: clear notes  ·  Esc: close"
          color: _webPalette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---- Digest: a periodic one-line AI summary of the dashboard,
        // generated via llm-blurb (hermes -> NanoGPT, see bin/omarchy-dashboard-refresh).
        Text {
          visible: !!root.state.digest.text
          width: parent.width
          text: "󰫨 " + root.state.digest.text
          wrapMode: Text.WordWrap
          color: _webPalette.faint
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
                text: "󰎕 Top Stories"
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                Layout.fillWidth: true
              }
              Text {
                text: Model.formatRelative(root.state.news.updatedAt)
                color: _webPalette.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              visible: root.state.news.items.length === 0
              text: root.refreshing ? "Fetching headlines…" : "No headlines yet — click Refresh."
              color: _webPalette.faint
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
                  id: headline
                  width: parent.width
                  text: modelData.title || ""
                  wrapMode: Text.WordWrap
                  color: activeFocus || headlineMouse.containsMouse
                    ? Style.hoverStateColor(root.barForeground, _webPalette.accent)
                    : root.barForeground
                  font.underline: activeFocus
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  activeFocusOnTab: !!modelData.url
                  Accessible.role: Accessible.Link
                  Accessible.ignored: !modelData.url
                  Accessible.name: modelData.title || "Open headline"
                  Accessible.onPressAction: openHeadline()

                  function openHeadline() {
                    guard.run("news.onClicked", function() {
                      root.trackNewsClick(modelData.title)
                      if (modelData.url) Quickshell.execDetached(["xdg-open", modelData.url])
                    })
                  }
                  Keys.onReturnPressed: openHeadline()
                  Keys.onEnterPressed: openHeadline()

                  MouseArea {
                    id: headlineMouse
                    anchors.fill: parent
                    cursorShape: modelData.url ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: { headline.forceActiveFocus(); headline.openHeadline() }
                  }
                }
                Text {
                  visible: !!modelData.meta
                  text: modelData.meta || ""
                  color: _webPalette.faint
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

              RowLayout {
                width: parent.width
                Text {
                  text: "󰍹 System"
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  Layout.fillWidth: true
                }
                Text {
                  text: Model.formatRelative(root.state.system.updatedAt)
                  color: _webPalette.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                visible: root.state.system.items.length === 0
                text: root.refreshing ? "Refreshing…" : "No system summary yet."
                color: _webPalette.faint
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
                  text: "󰎞 Notes"
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  Layout.fillWidth: true
                }
                Kit.ActionButton {
                  visible: root.state.notes.items.length > 0 || notesClearProc.running
                  text: notesClearProc.running ? "Clearing…" : "Clear"
                  focusable: true
                  Accessible.role: Accessible.Button
                  Accessible.name: notesClearProc.running ? "Clearing dashboard notes" : "Clear dashboard notes"
                  foreground: root.barForeground
                  bordered: true
                  enabled: !notesClearProc.running
                  onClicked: root.clearNotes()
                }
              }

              Text {
                id: clearStatusText
                visible: root.clearStatus !== ""
                text: root.clearStatus
                Accessible.role: Accessible.StaticText
                width: parent.width
                wrapMode: Text.WordWrap
                color: root.clearStatus.indexOf("Could not") === 0 ? _webPalette.negative : _webPalette.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                visible: root.state.notes.items.length === 0
                text: "Empty. Push a line via:\nomarchy-dashboard-note \"text\""
                wrapMode: Text.WordWrap
                color: _webPalette.faint
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
                    color: _webPalette.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }

        PanelSeparator {}

      }
    }
    }
  }
}
