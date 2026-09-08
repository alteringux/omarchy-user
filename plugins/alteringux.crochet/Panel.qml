import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Croche-Loom overlay: run a pattern through the sim, check the test suite,
// jump to the design docs or the published visual preview.
Panel {
  id: root
  moduleName: "alteringux.crochet"
  ipcTarget: "alteringux.crochet"
  manageIpc: false

  readonly property var guard: Kit.BugGuard.create("alteringux.crochet", function(argv) { Quickshell.execDetached(argv) })

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var lastRun: (hostWidget && hostWidget.lastRun) ? hostWidget.lastRun : null
  readonly property var tests: (hostWidget && hostWidget.tests) ? hostWidget.tests : null
  readonly property var patterns: (hostWidget && hostWidget.patterns) ? hostWidget.patterns : []
  readonly property bool running: !!(hostWidget && hostWidget.running)
  readonly property bool testing: !!(hostWidget && hostWidget.testing)
  readonly property bool scanning: !!(hostWidget && hostWidget.scanning)

  function open() {
    root.controller.show()
    if (root.hostWidget) root.hostWidget.refreshPatterns()
  }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  readonly property string headMeta: {
    if (root.testing) return "RUNNING TESTS…"
    if (root.tests && root.tests.total !== null) {
      return root.tests.ok
        ? (root.tests.passed + "/" + root.tests.total + " TESTS PASS")
        : (root.tests.failed + " TEST(S) FAILING")
    }
    return "NO TESTS RUN YET"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: body.implicitHeight

        Column {
          id: body
          width: parent.width
          spacing: Style.space(14)

          Kit.PanelHead {
            width: parent.width
            glyph: "🧶"
            title: "Croche-Loom"
            meta: root.headMeta
            foreground: root.barForeground
          }

          // ── last run ────────────────────────────────────────────────
          Rectangle {
            visible: root.lastRun !== null
            width: parent.width
            height: lastRunCol.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: root.lastRun && root.lastRun.ok === false
              ? Util.alpha(Kit.Palette.negative, 0.12)
              : Util.alpha(root.barForeground, 0.06)

            Column {
              id: lastRunCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              spacing: Style.space(4)

              Row {
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: (root.lastRun && root.lastRun.ok === false) ? "✗" : "✓"
                  color: (root.lastRun && root.lastRun.ok === false) ? Kit.Palette.negative : Kit.Palette.positive
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  text: root.lastRun ? root.lastRun.pattern : ""
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }

              Text {
                // All three fields are independently nullable in the index
                // (parseIndex nulls each on its own) — checking only
                // `stitches` let a partial record through and rendered the
                // literal string "null" for whichever field was missing.
                visible: !!(root.lastRun && root.lastRun.ok
                  && root.lastRun.stitches !== null
                  && root.lastRun.rows !== null
                  && root.lastRun.finalRowWidth !== null)
                width: parent.width
                text: root.lastRun
                  ? (root.lastRun.stitches + " stitches · " + root.lastRun.rows + " rows · final row width " + root.lastRun.finalRowWidth)
                  : ""
                color: Kit.Palette.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                visible: !!(root.lastRun && root.lastRun.error)
                width: parent.width
                text: root.lastRun ? (root.lastRun.error || "") : ""
                color: Kit.Palette.negative
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          Kit.EmptyState {
            visible: root.lastRun === null
            text: "No pattern run yet"
            hint: "Pick one below to compile it and render its loop graph."
            foreground: root.barForeground
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          // ── patterns ────────────────────────────────────────────────
          Row {
            width: parent.width
            spacing: Style.space(8)
            Kit.MetaText { width: implicitWidth; content: "PATTERNS"; foreground: root.barForeground }
            Item { width: parent.width - x - scanLabel.width; height: 1 }
            Text {
              id: scanLabel
              text: root.scanning ? "scanning…" : ""
              color: Kit.Palette.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Repeater {
            model: root.patterns

            delegate: Rectangle {
              required property var modelData
              width: parent.width
              height: Style.space(32)
              radius: Style.cornerRadius
              opacity: root.running ? 0.5 : 1.0
              color: patArea.containsMouse && !root.running
                ? Style.hoverFillFor(root.barForeground, Color.accent)
                : Util.alpha(root.barForeground, (root.lastRun && root.lastRun.pattern === modelData) ? 0.1 : 0.04)

              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                spacing: Style.space(6)
                Text {
                  text: (root.lastRun && root.lastRun.pattern === modelData) ? "▶" : "·"
                  color: (root.lastRun && root.lastRun.pattern === modelData) ? Kit.Palette.info : Qt.darker(root.barForeground, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  text: modelData
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }

              MouseArea {
                id: patArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.running
                cursorShape: Qt.PointingHandCursor
                onClicked: { if (root.hostWidget) root.hostWidget.runPattern(modelData) }
              }
            }
          }

          Kit.EmptyState {
            visible: root.patterns.length === 0 && !root.scanning
            text: "No .pattern files found"
            hint: "Add one under sim/patterns/ in the project."
            foreground: root.barForeground
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          // ── actions ─────────────────────────────────────────────────
          Row {
            width: parent.width
            spacing: Style.space(8)
            Repeater {
              model: [
                { t: root.testing ? "Testing…" : "Run tests", act: "test", on: !root.testing },
                { t: "Open last result", act: "last", on: !!(root.lastRun && root.lastRun.svgPath) }
              ]
              delegate: Rectangle {
                required property var modelData
                width: (parent.width - Style.space(8)) / 2
                height: Style.space(30)
                radius: Style.cornerRadius
                opacity: modelData.on ? 1.0 : 0.5
                color: rowA.containsMouse && modelData.on
                  ? Style.hoverFillFor(root.barForeground, Color.accent)
                  : Util.alpha(root.barForeground, 0.08)
                Text {
                  anchors.centerIn: parent
                  text: modelData.t
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                MouseArea {
                  id: rowA
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: modelData.on
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.hostWidget) return
                    if (modelData.act === "test") root.hostWidget.runTests()
                    else root.hostWidget.openLast()
                  }
                }
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            Repeater {
              model: [
                { t: "Open docs", act: "doc" },
                { t: "Open preview", act: "preview" },
                { t: "Open project", act: "project" }
              ]
              delegate: Rectangle {
                required property var modelData
                width: (parent.width - Style.space(16)) / 3
                height: Style.space(30)
                radius: Style.cornerRadius
                color: rowB.containsMouse
                  ? Style.hoverFillFor(root.barForeground, Color.accent)
                  : Util.alpha(root.barForeground, 0.08)
                Text {
                  anchors.centerIn: parent
                  text: modelData.t
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: rowB
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.hostWidget) return
                    if (modelData.act === "doc") root.hostWidget.openDoc()
                    else if (modelData.act === "preview") root.hostWidget.openPreview()
                    else root.hostWidget.openProject()
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "Also: `omarchy-crochet run <pattern>` / `test` / `open {project|preview|doc|last}`. "
                + "~/Work/crochet-machine"
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
