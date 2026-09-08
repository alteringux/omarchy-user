import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../alteringux.sysmon/Model.js" as Model
import "../alteringux.sysmon" as Sysmon
import "../alteringux.kit" as Kit

// Detail popup for temperature: current package reading against the warn /
// critical thresholds, a 10-minute trend sparkline with min/avg/max, and a
// per-sensor breakdown (`omarchy-sysmon sensors`). Binds to the host widget's
// watched store; never writes.
Panel {
  id: root
  moduleName: "alteringux.tempmon"
  ipcTarget: "alteringux.tempmon"
  manageIpc: false

  readonly property var guard: Kit.BugGuard.create("alteringux.tempmon", function (argv) { Quickshell.execDetached(argv) })

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var stat: (hostWidget && hostWidget.stat) ? hostWidget.stat : Model.defaultState()
  readonly property bool hasTemp: root.stat.temp !== null && root.stat.temp !== undefined
  readonly property var history: stat.history || []
  readonly property var spark: Model.sparkline(root.history, "temp", 120, 100)
  readonly property var stats: Model.historyStats(root.history, "temp")

  property var sensorRows: []

  function levelColor(level) {
    if (level === "critical") return Kit.Palette.negative
    if (level === "warning") return Kit.Palette.warning
    return Kit.Palette.positive
  }

  function open() { root.controller.show(); refreshSensors() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refreshSensors() {
    guard.run("refreshSensors", function () {
      if (sensorsProc.running) return
      sensorsProc.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-sysmon", "sensors"]
      sensorsProc.running = true
    })
  }

  Process {
    id: sensorsProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        guard.run("sensorsProc.onStreamFinished", function () {
          try {
            var d = JSON.parse(text || "[]")
            root.sensorRows = Array.isArray(d) ? d : []
          } catch (e) {
            root.sensorRows = []
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
      onActivateRequested: { if (root.hostWidget) root.hostWidget.sampleNow(); root.refreshSensors() }

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: body.implicitHeight

        Column {
          id: body
          width: parent.width
          spacing: Style.space(16)

          Kit.PanelHead {
            width: parent.width
            glyph: "󰔏"
            title: "Temperature"
            meta: root.stat.updatedAt > 0
              ? "UPDATED " + Math.max(0, Math.round((Date.now() - root.stat.updatedAt) / 1000)) + "S AGO"
              : "NO DATA YET"
            foreground: root.barForeground
          }

          // ── current reading ─────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: Model.formatTemp(root.stat.temp)
              color: root.levelColor(Model.tempLevel(root.stat.temp))
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: {
                var l = Model.tempLevel(root.stat.temp)
                if (!root.hasTemp) return "No sensor detected"
                if (l === "critical") return "Critical · at or above 90°C"
                if (l === "warning") return "Warm · at or above 75°C"
                return "Normal · below 75°C"
              }
              color: Qt.darker(root.barForeground, 1.3)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          // ── trend ────────────────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.hasTemp

            Sysmon.TrendChart {
              width: parent.width
              series: root.spark
              stroke: root.levelColor(Model.tempLevel(root.stat.temp))
              foreground: root.barForeground
            }

            Sysmon.StatGrid {
              width: parent.width
              stats: root.stats
              foreground: root.barForeground
              format: function (v) { return Model.formatTemp(v) }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.barForeground
            opacity: 0.12
            visible: root.hasTemp
          }

          // ── per-sensor breakdown ────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(6)

            Kit.SectionHeading { text: "SENSORS"; foreground: root.barForeground }

            Repeater {
              model: root.sensorRows.slice(0, 12)
              delegate: Row {
                required property var modelData
                width: parent.width
                spacing: Style.space(8)
                Text {
                  text: modelData.chip + "  " + modelData.label
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  width: Style.space(190)
                }
                Item { width: parent.width - x - sv.width; height: 1 }
                Text {
                  id: sv
                  text: Model.formatTemp(modelData.celsius)
                  color: root.levelColor(Model.tempLevel(modelData.celsius))
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }

            Kit.EmptyState {
              visible: root.sensorRows.length === 0
              text: "No sensors reported"
              hint: "`sensors` found nothing, or lm_sensors is not set up."
              foreground: root.barForeground
            }
          }

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }
}
