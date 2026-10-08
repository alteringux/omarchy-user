import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../alteringux.sysmon/Model.js" as Model
import "../alteringux.sysmon" as Sysmon
import "../alteringux.kit" as Kit
import "../shared"

// Detail popup for memory: RAM gauge with used/total/available, swap gauge, a
// 10-minute trend sparkline with min/avg/max, and the top processes by memory
// (`omarchy-sysmon top`). Binds to the host widget's watched store; never writes.
Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.memmon"
  ipcTarget: "alteringux.memmon"
  manageIpc: false

  readonly property var guard: Kit.BugGuard.create("alteringux.memmon", function (argv) { Quickshell.execDetached(argv) })

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property double nowMs: hostWidget && hostWidget.nowMs !== undefined ? hostWidget.nowMs : Date.now()

  readonly property var stat: (hostWidget && hostWidget.stat) ? hostWidget.stat : Model.defaultState()
  readonly property var history: stat && Array.isArray(stat.history) ? stat.history : []
  readonly property int trendWindowMs: 10 * 60 * 1000
  readonly property var spark: Model.sparkline(root.history, "mem", 0, 100, root.nowMs, root.trendWindowMs)
  readonly property var stats: Model.historyStats(root.history, "mem", root.nowMs, root.trendWindowMs)

  property var topRows: []
  property string topError: ""
  property bool topFeedbackSent: false
  signal topFeedback(string message)
  function reportTopError(message) {
    if (root.topFeedbackSent) return
    root.topFeedbackSent = true
    root.topError = message
    root.topFeedback(message)
  }

  function levelColor(level) {
    if (level === "critical") return _webPalette.negative
    if (level === "warning") return _webPalette.warning
    return _webPalette.positive
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
      root.topError = ""
      root.topFeedbackSent = false
      topProc.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-sysmon", "top", "--json"]
      topProc.running = true
    })
  }

  Process {
    id: topProc
    property bool started: false
    property bool attempted: false
    running: false
    onStarted: started = true
    onRunningChanged: {
      if (running) { started = false; attempted = true }
      else if (attempted && !started) {
        attempted = false
        root.reportTopError("Memory process list unavailable. Check ~/.local/bin/omarchy-sysmon.")
      }
    }
    onExited: function(code, status) {
      started = false
      attempted = false
      if (code !== 0 || status !== 0) root.reportTopError("Memory process list failed (exit " + code + ").")
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        guard.run("topProc.onStreamFinished", function () {
          try {
            var d = JSON.parse(text || "{}")
            if (!d || !Array.isArray(d.byMem)) throw new Error("missing byMem")
            root.topRows = d.byMem
          } catch (e) {
            root.topRows = []
            root.reportTopError("Memory process list could not be read.")
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
      sectionNavigation: true
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onActivateRequested: { if (root.hostWidget) root.hostWidget.sampleNow(); root.refreshTop() }
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Refresh memory metrics", context: "Memory monitor · shortcut focus" }
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
            visible: !!(root.topError || (root.hostWidget && root.hostWidget.sampleError))
            text: (root.hostWidget && root.hostWidget.sampleError ? root.hostWidget.sampleError : "")
              + (root.hostWidget && root.hostWidget.sampleError && root.topError ? "\n" : "") + root.topError
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
              function onTopFeedback(message) {
                if (root.opened && asyncStatusText.visible) asyncStatusText.Accessible.announce(message)
              }
            }
          }

          Kit.PanelHead {
            width: parent.width
            glyph: "󰍛"
            title: "Memory"
            meta: root.stat.updatedAt > 0
              ? "UPDATED " + Math.max(0, Math.round((root.nowMs - root.stat.updatedAt) / 1000)) + "S AGO"
              : "NO DATA YET"
            foreground: root.barForeground
          }

          // ── RAM ──────────────────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width
              Kit.SectionHeading { text: "RAM"; foreground: root.barForeground }
              Item { width: parent.width - x - ramText.width; height: 1 }
              Text {
                id: ramText
                text: Model.formatGb(root.stat.memory.usedKb) + " / " + Model.formatGb(root.stat.memory.totalKb)
                  + "  ·  " + Model.formatPct(root.stat.memory.pct)
                color: root.barForeground
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
                width: parent.width * (root.stat.memory.pct / 100)
                color: root.levelColor(Model.pctLevel(root.stat.memory.pct))
              }
            }

            Row {
              width: parent.width
              Kit.MetaText { width: implicitWidth; content: "AVAILABLE"; foreground: root.barForeground }
              Item { width: parent.width - x - availText.width; height: 1 }
              Text {
                id: availText
                text: Model.formatGb(root.stat.memory.availableKb)
                color: _webPalette.contrastColorFor(Qt.darker(root.barForeground, 1.4), _webPalette.barBackground)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          // ── swap ─────────────────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.stat.swap.totalKb > 0

            Row {
              width: parent.width
              Kit.SectionHeading { text: "SWAP"; foreground: root.barForeground }
              Item { width: parent.width - x - swapText.width; height: 1 }
              Text {
                id: swapText
                text: Model.formatGb(root.stat.swap.usedKb) + " / " + Model.formatGb(root.stat.swap.totalKb)
                  + "  ·  " + Model.formatPct(root.stat.swap.pct)
                color: root.barForeground
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
                width: parent.width * (root.stat.swap.pct / 100)
                color: root.levelColor(Model.pctLevel(root.stat.swap.pct))
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.barForeground
            opacity: 0.12
            visible: root.stat.swap.totalKb > 0
          }

          // ── trend ────────────────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(8)

            Sysmon.TrendChart {
              width: parent.width
              series: root.spark
              stroke: root.levelColor(Model.pctLevel(root.stat.memory.pct))
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

          // ── top processes by memory ──────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(6)

            Kit.SectionHeading { text: "TOP BY MEMORY"; foreground: root.barForeground }

            Repeater {
              model: root.topRows
              delegate: Row {
                required property var modelData
                width: parent.width
                spacing: Style.space(8)
                MarqueeText {
                  text: modelData.name
                  color: root.barForeground
                  textFont.family: Style.font.family
                  textFont.pixelSize: Style.font.bodySmall
                  requestedElide: Text.ElideRight
                  width: Style.space(150)
                }
                Item { width: parent.width - x - memv.width; height: 1 }
                Text {
                  id: memv
                  text: (modelData.mem != null ? modelData.mem.toFixed(1) : "0.0") + "%"
                  color: _webPalette.contrastColorFor(Qt.darker(root.barForeground, 1.3), _webPalette.barBackground)
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
