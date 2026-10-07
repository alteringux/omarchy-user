import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.sysmon" as Sysmon
import "../alteringux.kit" as Kit

// Detail popup for disk usage: the watched mount's gauge, every real mount's
// usage, a 10-minute trend sparkline with min/avg/max (borrowing the
// cpumon/memmon/tempmon family's Sysmon.TrendChart / Sysmon.StatGrid — those
// components take a plain { values, max, n } / { min, avg, max, cur, n }, no
// sysmon-specific coupling), and the largest subdirectories under the
// configured `largestPath` (`omarchy-diskmon largest`). Binds to the host
// widget's watched store; never writes except the on-demand sample/largest
// calls a user action triggers.
Panel {
  id: root
  moduleName: "alteringux.diskmon"
  ipcTarget: "alteringux.diskmon"
  manageIpc: false

  readonly property var guard: Kit.BugGuard.create("alteringux.diskmon", function (argv) { Quickshell.execDetached(argv) })

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var stat: (hostWidget && hostWidget.stat) ? hostWidget.stat : Model.defaultState()
  readonly property var history: stat.history || []
  readonly property var spark: Model.sparkline(root.history, "pct", 120, 100)
  readonly property var stats: Model.historyStats(root.history, "pct")

  property var largestRows: []

  function levelColor(level) {
    if (level === "critical") return Kit.Palette.negative
    if (level === "warning") return Kit.Palette.warning
    return Kit.Palette.positive
  }

  function open() { root.controller.show(); refreshLargest() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refreshLargest() {
    guard.run("refreshLargest", function () {
      if (largestProc.running) return
      largestProc.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-diskmon", "largest", "--json"]
      largestProc.running = true
    })
  }

  Process {
    id: largestProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        guard.run("largestProc.onStreamFinished", function () {
          try {
            var d = JSON.parse(text || "[]")
            root.largestRows = Array.isArray(d) ? d : []
          } catch (e) {
            root.largestRows = []
          }
        })
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onActivateRequested: { if (root.hostWidget) root.hostWidget.sampleNow(); root.refreshLargest() }

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: body.implicitHeight

        Column {
          id: body
          width: parent.width
          spacing: Style.space(16)

          Kit.PanelHead {
            width: parent.width
            glyph: ""
            title: "Disk"
            meta: root.stat.updatedAt > 0
              ? "UPDATED " + Math.max(0, Math.round((Date.now() - root.stat.updatedAt) / 1000)) + "S AGO"
              : "NO DATA YET"
            foreground: root.barForeground
          }

          // ── watched mount ────────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width
              Kit.SectionHeading {
                text: (root.stat.primary.target || "/").toUpperCase()
                foreground: root.barForeground
              }
              Item { width: parent.width - x - totalPct.width; height: 1 }
              Text {
                id: totalPct
                text: Model.formatPct(root.stat.primary.pct)
                color: root.levelColor(root.stat.primary.level)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }

            Rectangle {
              width: parent.width
              height: Style.space(8)
              radius: height / 2
              color: Util.alpha(root.barForeground, 0.12)
              Rectangle {
                height: parent.height
                radius: height / 2
                width: parent.width * (root.stat.primary.pct / 100)
                color: root.levelColor(root.stat.primary.level)
              }
            }

            Text {
              text: Model.formatGb(root.stat.primary.usedKb) + " used of " + Model.formatGb(root.stat.primary.totalKb)
              color: Kit.Palette.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          // ── trend ────────────────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(8)

            Sysmon.TrendChart {
              width: parent.width
              series: root.spark
              stroke: root.levelColor(root.stat.primary.level)
              foreground: root.barForeground
            }

            Sysmon.StatGrid {
              width: parent.width
              stats: root.stats
              foreground: root.barForeground
              format: function (v) { return Model.formatPct(v) }
            }
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          // ── every real mount ─────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(6)

            Kit.SectionHeading { text: "MOUNTS"; foreground: root.barForeground }

            Repeater {
              model: root.stat.mounts
              delegate: Row {
                required property var modelData
                width: parent.width
                spacing: Style.space(8)
                Text {
                  text: modelData.target
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  width: Style.space(150)
                }
                Item { width: parent.width - x - mountPct.width; height: 1 }
                Text {
                  id: mountPct
                  text: Model.formatPct(modelData.pct)
                  color: Qt.darker(root.barForeground, 1.3)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }

            Kit.EmptyState {
              visible: root.stat.mounts.length === 0
              text: "No mount data yet"
              hint: "Press ↵ to refresh."
              foreground: root.barForeground
            }
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          // ── largest subdirectories ───────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(6)

            Kit.SectionHeading { text: "LARGEST"; foreground: root.barForeground }

            Repeater {
              model: root.largestRows
              delegate: Row {
                required property var modelData
                width: parent.width
                spacing: Style.space(8)
                Text {
                  text: modelData.path
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideMiddle
                  width: Style.space(220)
                }
                Item { width: parent.width - x - sizeVal.width; height: 1 }
                Text {
                  id: sizeVal
                  text: Model.formatGb(modelData.kb)
                  color: Qt.darker(root.barForeground, 1.3)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }

            Kit.EmptyState {
              visible: root.largestRows.length === 0
              text: "No scan yet"
              hint: "Press ↵ to scan the configured path."
              foreground: root.barForeground
            }
          }

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }
}
