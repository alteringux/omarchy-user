import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../alteringux.sysmon/Model.js" as Model
import "../alteringux.sysmon" as Sysmon
import "../alteringux.kit" as Kit
import "../shared"

// Detail popup for temperature: current package reading against the warn /
// critical thresholds, a 10-minute trend sparkline with min/avg/max, and a
// per-sensor breakdown (`omarchy-sysmon sensors`). Binds to the host widget's
// watched store; never writes.
Panel {
  property QtObject _webPalette: Kit.Palette {}
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
  // Treat the history as untrusted input at the panel boundary. A malformed
  // state file must not make a trend delegate throw or hide the current readout.
  readonly property var history: root.stat && Array.isArray(root.stat.history) ? root.stat.history : []
  readonly property int trendWindowMs: 10 * 60 * 1000
  readonly property var spark: Model.sparkline(
    root.history, "temp", 120, 100, root.nowMs, root.trendWindowMs
  )
  readonly property var stats: Model.historyStats(
    root.history, "temp", root.nowMs, root.trendWindowMs
  )
  readonly property double nowMs: hostWidget && hostWidget.nowMs !== undefined
    ? hostWidget.nowMs
    : root.panelNowMs

  property double panelNowMs: Date.now()
  Timer {
    interval: 1000
    running: root.hostWidget === null
    repeat: true
    triggeredOnStart: true
    onTriggered: root.panelNowMs = Date.now()
  }


  property var sensorRows: []
  property string sensorError: ""
  property bool sensorFeedbackSent: false
  signal sensorFeedback(string message)
  function reportSensorError(message) {
    if (root.sensorFeedbackSent) return
    root.sensorFeedbackSent = true
    root.sensorError = message
    root.sensorFeedback(message)
  }

  function levelColor(level) {
    if (level === "critical") return _webPalette.negative
    if (level === "warning") return _webPalette.warning
    return _webPalette.positive
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
      root.sensorError = ""
      root.sensorFeedbackSent = false
      sensorsProc.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-sysmon", "sensors"]
      sensorsProc.running = true
    })
  }

  Process {
    id: sensorsProc
    property bool started: false
    property bool attempted: false
    running: false
    onStarted: started = true
    onRunningChanged: {
      if (running) { started = false; attempted = true }
      else if (attempted && !started) {
        attempted = false
        root.reportSensorError("Sensor list unavailable. Check ~/.local/bin/omarchy-sysmon.")
      }
    }
    onExited: function(code, status) {
      started = false
      attempted = false
      if (code !== 0 || status !== 0) root.reportSensorError("Sensor list failed (exit " + code + ").")
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        guard.run("sensorsProc.onStreamFinished", function () {
          try {
            var d = JSON.parse(text || "[]")
            if (!Array.isArray(d)) throw new Error("expected array")
            root.sensorRows = d
          } catch (e) {
            root.sensorRows = []
            root.reportSensorError("Sensor list could not be read.")
          }
        })
      }
    }
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    Kit.PanelKeys {
      id: keyCatcher
      anchors.fill: parent
      sectionNavigation: true
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onActivateRequested: { if (root.hostWidget) root.hostWidget.sampleNow(); root.refreshSensors() }
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Refresh temperature sensors", context: "Temperature monitor · shortcut focus" }
      ]

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: body.implicitHeight

        Column {
          id: body
          width: parent.width
          spacing: Style.space(16)

          Text {
            width: body.width
            height: visible ? implicitHeight : 0
            visible: !!(root.sensorError || (root.hostWidget && root.hostWidget.sampleError))
            text: (root.hostWidget && root.hostWidget.sampleError ? root.hostWidget.sampleError : "")
              + (root.hostWidget && root.hostWidget.sampleError && root.sensorError ? "\n" : "") + root.sensorError
            color: _webPalette.negative
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
            Connections {
              target: root.hostWidget
              ignoreUnknownSignals: true
              function onSampleFeedback(message) {
                if (root.opened && asyncStatusText.visible) asyncStatusText.Accessible.announce(message)
              }
            }
            Connections {
              target: root
              function onSensorFeedback(message) {
                if (root.opened && asyncStatusText.visible) asyncStatusText.Accessible.announce(message)
              }
            }
          }

          Kit.PanelHead {
            width: parent.width
            glyph: "󰔏"
            title: "Temperature"
            meta: root.stat.updatedAt > 0
              ? "UPDATED " + Math.max(0, Math.round((root.nowMs - root.stat.updatedAt) / 1000)) + "S AGO"
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
              color: _webPalette.contrastColorFor(Qt.darker(root.barForeground, 1.3), _webPalette.barBackground)
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
                MarqueeText {
                  text: modelData.chip + "  " + modelData.label
                  color: root.barForeground
                  textFont.family: Style.font.family
                  textFont.pixelSize: Style.font.bodySmall
                  requestedElide: Text.ElideRight
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
