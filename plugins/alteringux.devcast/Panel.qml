import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// Devcast overlay: build a replay from the latest Claude Code session, browse
// past devcasts, open their replay.html / exported video.
Panel {
  property QtObject _webPalette: Kit.Palette {}
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
  readonly property bool scanning: !!(hostWidget && hostWidget.scanning)
  readonly property bool importing: !!(hostWidget && hostWidget.importing)
  readonly property var catalog: (hostWidget && hostWidget.catalog) ? hostWidget.catalog : null
  readonly property var sessions: (root.catalog && root.catalog.recent) ? root.catalog.recent : []
  readonly property string lastError: hostWidget ? hostWidget.lastError : ""

  function open() {
    root.controller.show()
    if (root.hostWidget) root.hostWidget.refreshCatalog()
  }
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

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    Kit.PanelKeys {
      sectionNavigation: true
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onActivateRequested: { if (root.hostWidget) root.hostWidget.buildLatest(true) }
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Build the latest project", context: "Devcast · shortcut focus" }
      ]

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: body.implicitHeight

        Column {
          id: body
          width: parent.width
          spacing: Style.space(14)

          Kit.PanelHead {
            width: parent.width
            glyph: "󰿎" // nf-md-movie_open
            title: "Devcast"
            meta: root.building
              ? "BUILDING…"
              : (root.latest ? (root.latest.summary || "") : "NO DEVCASTS YET")
            foreground: root.barForeground
          }

          // ── build from latest session ──────────────────────────────
          Kit.ActionButton {
            width: parent.width
            height: Style.space(38)
            opacity: root.building ? 0.5 : 1.0
            enabled: !root.building
            focusable: true
            background: Util.alpha(root.barForeground, 0.1)
            foreground: root.barForeground
            Accessible.name: root.building ? "Building replay" : "Build replay from latest session"
            Accessible.description: root.building ? "Replay build in progress" : "Create and open a replay from the latest session"
            onClicked: if (root.hostWidget) root.hostWidget.buildLatest(true)

            MarqueeText {
              anchors { fill: parent; leftMargin: Style.space(10); rightMargin: Style.space(10) }
              text: root.building ? "Building replay…" : "Build replay from latest session"
              color: root.barForeground
              textFont.family: Style.font.family
              textFont.pixelSize: Style.font.body
              textFont.bold: true
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              requestedElide: Text.ElideRight
              focusableOnOverflow: false
              active: parent.activeFocus
              Accessible.ignored: true
            }
          }

          Text {
            width: parent.width
            text: "Also: /devcast in Claude Code, or `omarchy-devcast build <session-id>`. "
                + "Secrets are auto-redacted; replays stay under ~/.local/state/omarchy/devcasts/."
            color: _webPalette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            visible: root.lastError.length > 0
            text: root.lastError
            color: _webPalette.negative
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          Kit.MetaText { width: implicitWidth; content: "RECENT"; foreground: root.barForeground }

          Repeater {
            model: root.casts

            delegate: Rectangle {
              id: castDelegate
              required property var modelData
              width: parent.width
              height: rowCol.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: Util.alpha(root.barForeground, 0.04)

              Column {
                id: rowCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(10)
                spacing: Style.space(3)

                MarqueeText {
                  width: parent.width
                  text: modelData.title || "session"
                  color: root.barForeground
                  textFont.family: Style.font.family
                  textFont.pixelSize: Style.font.body
                  textFont.bold: true
                  requestedElide: Text.ElideRight
                }
                MarqueeText {
                  width: parent.width
                  text: modelData.summary || ""
                  color: _webPalette.faint
                  textFont.family: Style.font.family
                  textFont.pixelSize: Style.font.caption
                  requestedElide: Text.ElideRight
                }
                Row {
                  spacing: Style.space(8)
                  Repeater {
                    model: [
                      { t: "Watch", p: modelData.html, on: (modelData.html || "").length > 0 },
                      { t: "Video", p: modelData.video, on: (modelData.video || "").length > 0 }
                    ]
                    delegate: Kit.ActionButton {
                      required property var modelData
                      visible: modelData.on
                      height: Style.spacing.controlHeight
                      radius: height / 2
                      text: modelData.t
                      fontSize: Style.font.caption
                      foreground: root.barForeground
                      background: Util.alpha(root.barForeground, 0.1)
                      horizontalPadding: Style.space(8)
                      verticalPadding: 0
                      focusable: true
                      Accessible.name: modelData.t === "Watch"
                        ? "Watch replay: " + (castDelegate.modelData.title || "session")
                        : "Open video: " + (castDelegate.modelData.title || "session")
                      onClicked: root.openPath(modelData.p)
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

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          // ── session library ("all sessions + history") ──────────────
          Row {
            width: parent.width
            spacing: Style.space(8)
            Kit.MetaText {
              width: implicitWidth
              content: "LIBRARY"
              foreground: root.barForeground
            }
            Item { width: parent.width - x - libStats.width; height: 1 }
            Text {
              id: libStats
              text: root.catalog
                ? (root.catalog.totalSessions + " sessions · " + root.catalog.built + " replays"
                   + (root.catalog.stale > 0 ? " · " + root.catalog.stale + " stale" : ""))
                : (root.scanning ? "scanning…" : "—")
              color: _webPalette.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            Repeater {
              model: [
                { t: root.importing ? "Importing…" : "Import recent", act: "import", on: !root.importing && !!root.catalog && root.catalog.unbuilt > 0 },
                { t: root.scanning ? "Scanning…" : "Rescan", act: "scan", on: !root.scanning }
              ]
              delegate: Kit.ActionButton {
                required property var modelData
                width: (parent.width - Style.space(8)) / 2
                height: Style.space(30)
                opacity: modelData.on ? 1.0 : 0.5
                text: modelData.t
                fontSize: Style.font.bodySmall
                foreground: root.barForeground
                background: Util.alpha(root.barForeground, 0.08)
                enabled: modelData.on
                focusable: true
                Accessible.name: modelData.t
                Accessible.description: modelData.act === "import"
                  ? "Import recent sessions that do not have a replay yet"
                  : "Rescan the session library"
                onClicked: {
                  if (!root.hostWidget) return
                  if (modelData.act === "import") root.hostWidget.importRecent()
                  else root.hostWidget.refreshCatalog()
                }
              }
            }
          }

          Repeater {
            model: root.sessions

            delegate: Kit.ActionButton {
              id: sessionButton
              required property var modelData
              width: parent.width
              height: sCol.implicitHeight + Style.space(14)
              text: ""
              background: Util.alpha(root.barForeground, 0.03)
              foreground: root.barForeground
              horizontalPadding: Style.space(9)
              verticalPadding: Style.space(6)
              leftAlign: true
              focusable: true
              Accessible.name: (modelData.built ? "Open replay: " : "Build replay: ") + (modelData.title || "session")
              Accessible.description: {
                var project = (modelData.project || "").replace(/^\/home\/[^/]+/, "~")
                var when = modelData.endedAt ? Qt.formatDateTime(new Date(modelData.endedAt), "MMM d") : ""
                return when + " · " + modelData.toolUses + " tools · " + project
                  + (modelData.stale ? " · replay stale" : "")
              }
              onClicked: {
                if (modelData.built) root.openPath(root.castPathFor(modelData.built))
                else if (root.hostWidget) root.hostWidget.buildSession(modelData.sourcePath, true)
              }

              Column {
                id: sCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(9)
                spacing: Style.space(2)

                Row {
                  width: parent.width
                  spacing: Style.space(6)
                  Text {
                    text: modelData.built ? "▶" : (modelData.stale ? "~" : "·")
                    color: modelData.built ? _webPalette.positive
                      : (modelData.stale ? _webPalette.warning : _webPalette.faint)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    width: Style.space(12)
                    Accessible.ignored: true
                  }
                  MarqueeText {
                    width: parent.width - x
                    text: modelData.title || "session"
                    color: root.barForeground
                    textFont.family: Style.font.family
                    textFont.pixelSize: Style.font.bodySmall
                    textFont.bold: !!modelData.built
                    requestedElide: Text.ElideRight
                    focusableOnOverflow: false
                    active: sessionButton.activeFocus
                    Accessible.ignored: true
                  }
                }
                MarqueeText {
                  width: parent.width
                  text: {
                    var proj = (modelData.project || "").replace(/^\/home\/[^/]+/, "~")
                    var when = modelData.endedAt ? Qt.formatDateTime(new Date(modelData.endedAt), "MMM d") : ""
                    return when + "  ·  " + modelData.toolUses + " tools  ·  " + proj
                      + (modelData.stale ? "  ·  replay stale" : "")
                  }
                  color: _webPalette.faint
                  textFont.family: Style.font.family
                  textFont.pixelSize: Style.font.caption
                  requestedElide: Text.ElideRight
                  focusableOnOverflow: false
                  active: sessionButton.activeFocus
                  Accessible.ignored: true
                }
              }
            }
          }
        }
      }
    }
  }

  // catalog.recent carries a built dir NAME; turn it into a replay.html path.
  function castPathFor(dirName) {
    return Quickshell.env("HOME") + "/.local/state/omarchy/devcasts/" + dirName + "/replay.html"
  }
}
