import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../alteringux.sysmon/Model.js" as Model
import "../alteringux.sysmon" as Sysmon
import "../alteringux.kit" as Kit

// Detail popup for CPU: overall gauge, per-core bars, load average, uptime, a
// 10-minute trend sparkline with min/avg/max, and the top processes by CPU
// (`omarchy-sysmon top`). Binds to the host widget's watched store; never writes.
Panel {
  id: root
  moduleName: "alteringux.cpumon"
  ipcTarget: "alteringux.cpumon"
  manageIpc: false

  readonly property var guard: Kit.BugGuard.create("alteringux.cpumon", function (argv) { Quickshell.execDetached(argv) })

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var stat: (hostWidget && hostWidget.stat) ? hostWidget.stat : Model.defaultState()
  readonly property var history: stat && Array.isArray(stat.history) ? stat.history : []
  readonly property int trendWindowMs: 10 * 60 * 1000
  // Keep the chart and summary statistics on the same timestamp-bounded
  // samples. A count-based slice (120 points) stops meaning "10 MIN" when
  // the sampler cadence changes, and malformed entries must not become zeros.
  readonly property var trendHistory: {
    var input = root.history
    var latest = 0
    for (var i = 0; i < input.length; i++) {
      var candidate = input[i]
      var ts = candidate && typeof candidate === "object" ? Number(candidate.ts) : NaN
      if (isFinite(ts) && ts > latest) latest = ts
    }
    if (latest <= 0) return []
    var cutoff = latest - root.trendWindowMs
    var out = []
    for (var j = 0; j < input.length; j++) {
      var entry = input[j]
      if (!entry || typeof entry !== "object") continue
      var entryTs = Number(entry.ts)
      var cpu = Number(entry.cpu)
      if (!isFinite(entryTs) || entryTs < cutoff || !isFinite(cpu)) continue
      out.push(entry)
    }
    return out
  }
  readonly property var spark: Model.sparkline(root.trendHistory, "cpu", 0, 100)
  readonly property var stats: Model.historyStats(root.trendHistory, "cpu")

  property var topRows: []

  function levelColor(level) {
    if (level === "critical") return Kit.Palette.negative
    if (level === "warning") return Kit.Palette.warning
    return Kit.Palette.positive
  }

  function open() { root.controller.show(); refreshTop() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refreshTop() {
    guard.run("refreshTop", function () {
      if (topProc.running) return
      topProc.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-sysmon", "top", "--json"]
      topProc.running = true
    })
  }

  Process {
    id: topProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        guard.run("topProc.onStreamFinished", function () {
          try {
            var d = JSON.parse(text || "{}")
            root.topRows = Array.isArray(d.byCpu) ? d.byCpu : []
          } catch (e) {
            root.topRows = []
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
      onActivateRequested: { if (root.hostWidget) root.hostWidget.sampleNow(); root.refreshTop() }

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: body.implicitHeight

        Column {
          id: body
          width: parent.width
          spacing: Style.space(16)

          Kit.PanelHead {
            width: parent.width
            glyph: "󰘚"
            title: "Processor"
            meta: root.stat.updatedAt > 0
              ? "UPDATED " + Math.max(0, Math.round((Date.now() - root.stat.updatedAt) / 1000)) + "S AGO"
              : "NO DATA YET"
            foreground: root.barForeground
          }

          // ── overall ──────────────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width
              Kit.SectionHeading { text: "TOTAL"; foreground: root.barForeground }
              Item { width: parent.width - x - totalPct.width; height: 1 }
              Text {
                id: totalPct
                text: Model.formatPct(root.stat.cpu.pct)
                color: root.levelColor(Model.pctLevel(root.stat.cpu.pct))
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
                width: parent.width * (root.stat.cpu.pct / 100)
                color: root.levelColor(Model.pctLevel(root.stat.cpu.pct))
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(4)
              visible: root.stat.cpu.cores.length > 1

              Repeater {
                model: root.stat.cpu.cores
                delegate: Rectangle {
                  required property var modelData
                  required property int index
                  width: (body.width - Style.space(4) * (root.stat.cpu.cores.length - 1)) / root.stat.cpu.cores.length
                  height: Style.space(22)
                  radius: Style.cornerRadius * 0.5
                  color: Util.alpha(root.barForeground, 0.08)

                  Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: parent.height * (modelData / 100)
                    radius: parent.radius
                    color: Util.alpha(root.levelColor(Model.pctLevel(modelData)), 0.85)
                  }

                  Text {
                    anchors.centerIn: parent
                    text: (index + 1)
                    color: root.barForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
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
              stroke: root.levelColor(Model.pctLevel(root.stat.cpu.pct))
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

          // ── load average + uptime ────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(4)

            Kit.SectionHeading { text: "LOAD AVERAGE"; foreground: root.barForeground }

            Grid {
              width: parent.width
              columns: 4
              columnSpacing: Style.space(10)
              rowSpacing: Style.space(4)

              Repeater {
                model: [
                  { l: "1M", v: root.stat.load.one.toFixed(2) },
                  { l: "5M", v: root.stat.load.five.toFixed(2) },
                  { l: "15M", v: root.stat.load.fifteen.toFixed(2) },
                  { l: "UPTIME", v: Model.formatUptime(root.stat.uptimeSec) }
                ]
                delegate: Column {
                  required property var modelData
                  spacing: Style.space(2)
                  Kit.MetaText { width: implicitWidth; content: modelData.l; foreground: root.barForeground }
                  Text {
                    text: modelData.v
                    color: root.barForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }
              }
            }
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          // ── top processes by CPU ─────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(6)

            Kit.SectionHeading { text: "TOP BY CPU"; foreground: root.barForeground }

            Repeater {
              model: root.topRows
              delegate: Row {
                required property var modelData
                width: parent.width
                spacing: Style.space(8)
                Text {
                  text: modelData.name
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  width: Style.space(150)
                }
                Item { width: parent.width - x - cpuv.width; height: 1 }
                Text {
                  id: cpuv
                  text: (modelData.cpu != null ? modelData.cpu.toFixed(1) : "0.0") + "%"
                  color: Qt.darker(root.barForeground, 1.3)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }

            Kit.EmptyState {
              visible: root.topRows.length === 0
              text: "No process sample yet"
              hint: "Press ↵ to refresh."
              foreground: root.barForeground
            }
          }

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }
}
