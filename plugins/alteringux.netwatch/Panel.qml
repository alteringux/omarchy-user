import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Analytics overlay for netwatch: live rate + sparkline, a today/week/month
// rollup with a mini bar chart, the monthly-quota gauge, and a live connection
// breakdown from `omarchy-netwatch top`.
Panel {
  id: root
  moduleName: "alteringux.netwatch"
  ipcTarget: "alteringux.netwatch"
  manageIpc: false

  readonly property var guard: Kit.BugGuard.create("alteringux.netwatch", function(argv) { Quickshell.execDetached(argv) })

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Bind straight to the host widget's watched store (docs/adr/0006).
  readonly property var state: (hostWidget && hostWidget.state) ? hostWidget.state : null
  readonly property var stat: (hostWidget && hostWidget.stat) ? hostWidget.stat : null
  readonly property var config: (hostWidget && hostWidget.config) ? hostWidget.config : ({})

  property string range: "today"
  readonly property var report: root.state
    ? Model.report(root.state, root.range, Date.now())
    : { range: root.range, total: { rx: 0, tx: 0, total: 0 }, peak: { rx: 0, tx: 0, label: "" }, series: [] }
  readonly property var spark: root.state
    ? Model.sparkline(root.state, 48)
    : { rx: [], tx: [], max: 1, n: 0 }

  property var topData: ({ total: 0, byState: {}, byProc: [], byPeer: [] })

  function fmt(n) { return Model.formatBytes(n) }
  function fmtRate(n) { return Model.formatRate(n) }

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
      topProc.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-netwatch", "top", "--json"]
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
            root.topData = {
              total: d.total || 0,
              byState: d.byState || {},
              byProc: Array.isArray(d.byProc) ? d.byProc : [],
              byPeer: Array.isArray(d.byPeer) ? d.byPeer : []
            }
          } catch (e) {
            root.topData = { total: 0, byState: {}, byProc: [], byPeer: [] }
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
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
            glyph: "" // nf-fa-exchange
            title: "Network"
            meta: root.stat
              ? (root.stat.iface || "—")
                + (root.stat.isVpn ? "  ·  VPN" : "")
                + (root.stat.up ? "" : "  ·  LINK DOWN")
                + (root.stat.stale ? "  ·  STALE" : "")
              : "NO DATA YET"
            foreground: root.barForeground
            trailingControl: Rectangle {
              width: Style.space(30); height: Style.space(24)
              radius: Style.cornerRadius
              color: refreshArea.containsMouse
                ? Style.hoverFillFor(root.barForeground, Color.accent)
                : Util.alpha(root.barForeground, 0.1)
              Text {
                anchors.centerIn: parent
                text: "" // nf-fa-refresh
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea {
                id: refreshArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { if (root.hostWidget) root.hostWidget.sampleNow(); root.refreshTop() }
              }
            }
          }

          // ── live rate + sparkline ──────────────────────────────────────
          Row {
            width: parent.width
            spacing: Style.space(20)

            Repeater {
              model: [
                { k: "↓", label: "DOWN", rate: root.stat ? root.stat.rxRate : 0, c: Kit.Palette.info },
                { k: "↑", label: "UP",   rate: root.stat ? root.stat.txRate : 0, c: Kit.Palette.positive }
              ]
              delegate: Column {
                required property var modelData
                spacing: Style.space(2)
                Kit.MetaText {
                  width: implicitWidth
                  content: modelData.k + " " + modelData.label
                  foreground: root.barForeground
                }
                Text {
                  text: root.fmtRate(modelData.rate)
                  color: modelData.c
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
              }
            }
          }

          Canvas {
            id: sparkCanvas
            width: parent.width
            height: Style.space(46)
            property var s: root.spark
            onSChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var w = width, h = height
              var s = root.spark
              var n = s.n
              if (!n || n < 2) {
                ctx.fillStyle = Util.alpha(root.barForeground, 0.35)
                ctx.font = "11px " + Style.font.family
                ctx.fillText("collecting samples…", 0, h / 2)
                return
              }
              var max = Math.max(s.max, 1)
              function drawSeries(arr, color, fill) {
                ctx.beginPath()
                for (var i = 0; i < arr.length; i++) {
                  var x = (i / (arr.length - 1)) * w
                  var y = h - (arr[i] / max) * (h - 2) - 1
                  if (i === 0) ctx.moveTo(x, y)
                  else ctx.lineTo(x, y)
                }
                ctx.strokeStyle = color
                ctx.lineWidth = 1.5
                ctx.stroke()
                if (fill) {
                  ctx.lineTo(w, h); ctx.lineTo(0, h); ctx.closePath()
                  ctx.fillStyle = Util.alpha(color, 0.12)
                  ctx.fill()
                }
              }
              drawSeries(s.rx, Kit.Palette.info, true)
              drawSeries(s.tx, Kit.Palette.positive, false)
            }
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          // ── range toggle ──────────────────────────────────────────────
          Row {
            width: parent.width
            spacing: Style.space(8)
            Repeater {
              model: [ { k: "today", t: "Today" }, { k: "week", t: "Week" }, { k: "month", t: "Month" } ]
              delegate: Rectangle {
                required property var modelData
                width: (parent.width - Style.space(16)) / 3
                height: Style.space(30)
                radius: Style.cornerRadius
                readonly property bool sel: root.range === modelData.k
                color: sel
                  ? Util.alpha(Color.accent, 0.25)
                  : (rangeArea.containsMouse ? Util.alpha(root.barForeground, 0.12) : Util.alpha(root.barForeground, 0.06))
                Text {
                  anchors.centerIn: parent
                  text: modelData.t
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: parent.sel
                }
                MouseArea {
                  id: rangeArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.range = modelData.k
                }
              }
            }
          }

          // ── rollup totals ─────────────────────────────────────────────
          Grid {
            width: parent.width
            columns: 4
            columnSpacing: Style.space(10)
            rowSpacing: Style.space(4)
            Repeater {
              model: [
                { l: "DOWN",  v: root.fmt(root.report.total.rx) },
                { l: "UP",    v: root.fmt(root.report.total.tx) },
                { l: "TOTAL", v: root.fmt(root.report.total.total) },
                { l: "PEAK",  v: root.fmt(root.report.peak.rx + root.report.peak.tx) + (root.report.peak.label ? (" @" + root.report.peak.label) : "") }
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

          // ── mini bar chart of the series (stacked rx+tx) ──────────────
          Item {
            width: parent.width
            height: Style.space(60)
            readonly property real maxCol: {
              var m = 1
              for (var i = 0; i < root.report.series.length; i++) {
                var t = root.report.series[i].rx + root.report.series[i].tx
                if (t > m) m = t
              }
              return m
            }
            Row {
              anchors.fill: parent
              spacing: root.report.series.length > 12 ? 1 : 3
              Repeater {
                model: root.report.series
                delegate: Item {
                  required property var modelData
                  width: (parent.width - (parent.spacing * (root.report.series.length - 1))) / root.report.series.length
                  height: parent.height
                  readonly property real frac: (modelData.rx + modelData.tx) / parent.parent.maxCol
                  readonly property real colH: Math.max(0, frac * parent.height)
                  Column {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    Rectangle {
                      width: parent.width
                      height: parent.parent.colH * (modelData.tx / Math.max(1, modelData.rx + modelData.tx))
                      color: Kit.Palette.positive
                      opacity: 0.85
                    }
                    Rectangle {
                      width: parent.width
                      height: parent.parent.colH * (modelData.rx / Math.max(1, modelData.rx + modelData.tx))
                      color: Kit.Palette.info
                      opacity: 0.85
                    }
                  }
                }
              }
            }
          }

          // ── quota gauge ───────────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: !!(root.stat && root.stat.quota && root.stat.quota.enabled)

            Row {
              width: parent.width
              Kit.MetaText { width: implicitWidth; content: "MONTHLY QUOTA"; foreground: root.barForeground }
              Item { width: parent.width - x - usedText.width; height: 1 }
              Text {
                id: usedText
                text: root.stat
                  ? (root.fmt(root.stat.quota.usedBytes) + " / " + root.stat.quota.limitGB + " GB  ·  " + Math.round(root.stat.quota.pct) + "%")
                  : ""
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
                width: parent.width * Math.max(0, Math.min(1, (root.stat ? root.stat.quota.pct : 0) / 100))
                color: {
                  var p = root.stat ? root.stat.quota.pct : 0
                  if (p >= 100) return Kit.Palette.negative
                  if (p >= 80) return Kit.Palette.warning
                  return Kit.Palette.positive
                }
              }
            }
          }

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.barForeground; opacity: 0.12 }

          // ── live connections (ss) ────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width
              Kit.SectionHeading {
                text: "CONNECTIONS · " + (root.topData.total || 0)
                foreground: root.barForeground
              }
            }

            Text {
              width: parent.width
              text: {
                var e = []
                for (var k in root.topData.byState) e.push({ k: k, n: root.topData.byState[k] })
                e.sort(function (a, b) { return b.n - a.n })
                return e.map(function (x) { return x.k + " " + x.n }).join("   ")
              }
              visible: text.length > 0
              color: Qt.darker(root.barForeground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Kit.MetaText { width: implicitWidth; content: "BY PROCESS"; foreground: root.barForeground }
            Repeater {
              model: root.topData.byProc.slice(0, 6)
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
                Text {
                  text: modelData.conns + " conn"
                  color: Qt.darker(root.barForeground, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Item { width: parent.width - x - qtext.width; height: 1 }
                Text {
                  id: qtext
                  text: "q " + (modelData.queued || "0/0")
                  color: Qt.darker(root.barForeground, 1.6)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Kit.MetaText { width: implicitWidth; content: "TOP PEERS"; foreground: root.barForeground }
            Repeater {
              model: root.topData.byPeer.slice(0, 6)
              delegate: Row {
                required property var modelData
                width: parent.width
                spacing: Style.space(8)
                Text {
                  text: modelData.addr
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  width: Style.space(200)
                }
                Item { width: parent.width - x - pc.width; height: 1 }
                Text {
                  id: pc
                  text: modelData.conns + ""
                  color: Qt.darker(root.barForeground, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Kit.EmptyState {
              visible: (root.topData.byProc.length === 0)
              text: "No sockets visible"
              hint: "`ss` only shows your own processes without root."
              foreground: root.barForeground
            }
          }
        }
      }
    }
  }
}
