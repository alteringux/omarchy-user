import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Detail view for sysmon: per-core CPU breakdown, memory + swap gauges,
// temperature, load average, and uptime. Binds straight to the host widget's
// watched store (docs/adr/0006) — this panel never writes anything.
Panel {
  id: root
  moduleName: "alteringux.sysmon"
  ipcTarget: "alteringux.sysmon"
  manageIpc: false

  readonly property var guard: Kit.BugGuard.create("alteringux.sysmon", function(argv) { Quickshell.execDetached(argv) })

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var stat: (hostWidget && hostWidget.stat) ? hostWidget.stat : Model.defaultState()
  // Keep the age label reactive while the popup is open; Date.now() alone is
  // not a QML dependency and would otherwise remain frozen.
  property double clockMs: Date.now()

  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.clockMs = Date.now()
  }

  function levelColor(level) {
    if (level === "critical") return Kit.Palette.negative
    if (level === "warning") return Kit.Palette.warning
    return Kit.Palette.positive
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onActivateRequested: { if (root.hostWidget) root.hostWidget.sampleNow() }

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: body.implicitHeight

        Column {
          id: body
          width: parent.width
          spacing: Style.space(16)

          Kit.PanelHead {
            width: parent.width
            glyph: "󰘚" // nf-fae-chip
            title: "System"
            meta: root.stat.updatedAt > 0
              ? "UPDATED " + Math.max(0, Math.round((root.clockMs - root.stat.updatedAt) / 1000)) + "S AGO"
              : "NO DATA YET"
            foreground: root.barForeground
          }

          // ── CPU ──────────────────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width
              Kit.SectionHeading { text: "CPU"; foreground: root.barForeground }
              Item { width: parent.width - x - cpuPctText.width; height: 1 }
              Text {
                id: cpuPctText
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

          // ── Memory + swap ────────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width
              Kit.SectionHeading { text: "MEMORY"; foreground: root.barForeground }
              Item { width: parent.width - x - memText.width; height: 1 }
              Text {
                id: memText
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
              visible: root.stat.swap.totalKb > 0
              Kit.MetaText {
                width: implicitWidth
                content: "SWAP"
                foreground: root.barForeground
              }
              Item { width: parent.width - x - swapText.width; height: 1 }
              Text {
                id: swapText
                text: Model.formatGb(root.stat.swap.usedKb) + " / " + Model.formatGb(root.stat.swap.totalKb)
                color: Qt.darker(root.barForeground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          // ── Temperature ──────────────────────────────────────────────
          Row {
            width: parent.width
            visible: root.stat.temp !== null && root.stat.temp !== undefined
            Kit.SectionHeading { text: "TEMPERATURE"; foreground: root.barForeground }
            Item { width: parent.width - x - tempText.width; height: 1 }
            Text {
              id: tempText
              text: Model.formatTemp(root.stat.temp)
              color: root.levelColor(Model.tempLevel(root.stat.temp))
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.barForeground
            opacity: 0.12
            visible: root.stat.temp !== null && root.stat.temp !== undefined
          }

          // ── Load average + uptime ────────────────────────────────────
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

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }
}
