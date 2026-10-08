import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// Detail popup for reposwatch: one row per watched repo — branch, dirty
// breakdown, ahead/behind, and how long ago its last commit landed. Binds to
// the host widget's watched store; never writes except the on-demand
// scan a user action triggers.
Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.reposwatch"
  ipcTarget: "alteringux.reposwatch"
  manageIpc: false

  readonly property var guard: Kit.BugGuard.create("alteringux.reposwatch", function (argv) { Quickshell.execDetached(argv) })

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var stat: (hostWidget && hostWidget.stat) ? hostWidget.stat : Model.defaultState()

  function levelColor(level) {
    if (level === "critical") return _webPalette.negative
    if (level === "warning") return _webPalette.warning
    return _webPalette.positive
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function relativeAge(ts) {
    if (!ts) return "no commits"
    var s = Math.max(0, Math.round(Date.now() / 1000) - ts)
    if (s < 60) return "just now"
    if (s < 3600) return Math.floor(s / 60) + "m ago"
    if (s < 86400) return Math.floor(s / 3600) + "h ago"
    return Math.floor(s / 86400) + "d ago"
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    Kit.PanelKeys {
      id: keyCatcher
      anchors.fill: parent
      sectionNavigation: true
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onActivateRequested: { if (root.hostWidget) root.hostWidget.scanNow() }
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Scan repositories for changes", context: "Repository monitor · shortcut focus" }
      ]

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: body.implicitHeight

        Column {
          id: body
          width: parent.width
          spacing: Style.space(12)

          Kit.PanelHead {
            width: parent.width
            glyph: ""
            title: "Repos"
            meta: root.stat.updatedAt > 0
              ? "UPDATED " + Math.max(0, Math.round((Date.now() - root.stat.updatedAt) / 1000)) + "S AGO"
              : "NO DATA YET"
            foreground: root.barForeground
          }

          Row {
            width: parent.width
            spacing: Style.space(14)
            visible: root.stat.repos.length > 0

            Column {
              spacing: Style.space(2)
              Kit.MetaText { content: "DIRTY"; foreground: root.barForeground }
              Text {
                text: root.stat.totals.dirtyRepos
                color: root.stat.totals.dirtyRepos > 0 ? _webPalette.warning : root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
            Column {
              spacing: Style.space(2)
              Kit.MetaText { content: "AHEAD"; foreground: root.barForeground }
              Text {
                text: root.stat.totals.totalAhead
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
            Column {
              spacing: Style.space(2)
              Kit.MetaText { content: "BEHIND"; foreground: root.barForeground }
              Text {
                text: root.stat.totals.totalBehind
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
            Column {
              spacing: Style.space(2)
              Kit.MetaText { content: "ERRORS"; foreground: root.barForeground }
              Text {
                text: root.stat.totals.errorRepos
                color: root.stat.totals.errorRepos > 0 ? _webPalette.negative : root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.barForeground
            opacity: 0.12
            visible: root.stat.repos.length > 0
          }

          Column {
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.stat.repos
              delegate: Column {
                required property var modelData
                width: parent.width
                spacing: Style.space(2)

                Row {
                  width: parent.width
                  spacing: Style.space(6)
                  MarqueeText {
                    text: modelData.name
                    color: root.barForeground
                    textFont.family: Style.font.family
                    textFont.pixelSize: Style.font.bodySmall
                    textFont.bold: true
                    requestedElide: Text.ElideRight
                    width: Style.space(140)
                  }
                  MarqueeText {
                    visible: modelData.ok
                    text: modelData.branch
                    color: _webPalette.contrastColorFor(Qt.darker(root.barForeground, 1.3), _webPalette.barBackground)
                    textFont.family: Style.font.family
                    textFont.pixelSize: Style.font.caption
                    requestedElide: Text.ElideRight
                    width: Style.space(90)
                  }
                  Item { width: parent.width - x - trailing.width; height: 1 }
                  Text {
                    id: trailing
                    text: modelData.ok ? Model.formatAheadBehind(modelData) : "!"
                    color: root.levelColor(Model.repoLevel(modelData))
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                MarqueeText {
                  width: parent.width
                  text: modelData.ok
                    ? (modelData.dirty.total > 0
                        ? modelData.dirty.staged + " staged · " + modelData.dirty.unstaged + " unstaged · " +
                          modelData.dirty.untracked + " untracked · " + root.relativeAge(modelData.lastCommitTs)
                        : "clean · " + root.relativeAge(modelData.lastCommitTs))
                    : modelData.error
                  color: modelData.ok ? _webPalette.faint : _webPalette.negative
                  textFont.family: Style.font.family
                  textFont.pixelSize: Style.font.caption
                  requestedElide: Text.ElideRight
                }
              }
            }

            Kit.EmptyState {
              visible: root.stat.repos.length === 0
              text: "No repos watched yet"
              hint: "omarchy-reposwatch add ~/path/to/repo"
              foreground: root.barForeground
            }
          }

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }
}
