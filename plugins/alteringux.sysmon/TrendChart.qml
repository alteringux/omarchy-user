import QtQuick
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit

// Shared trend sparkline for the cpumon / memmon / tempmon panels. Feed it a
// { values, max, n } from Model.sparkline. Draws a filled line; shows a
// "collecting samples…" hint until there are at least two points.
Item {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  property var series: ({ values: [], max: 1, n: 0 })
  property color stroke: _webPalette.info
  property color foreground: "white"
  property real fillAlpha: 0.13

  implicitHeight: Style.space(46)

  Canvas {
    id: canvas
    anchors.fill: parent

    Connections {
      target: root
      function onSeriesChanged() { canvas.requestPaint() }
      function onStrokeChanged() { canvas.requestPaint() }
    }
    onWidthChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width, h = height
      var s = root.series || { values: [], max: 1, n: 0 }
      var vals = s.values || []

      if (vals.length < 2) {
        ctx.fillStyle = Util.alpha(root.foreground, 0.35)
        ctx.font = "11px " + Style.font.family
        ctx.fillText("collecting samples…", 0, h / 2)
        return
      }

      var max = Math.max(s.max || 1, 1)
      ctx.beginPath()
      for (var i = 0; i < vals.length; i++) {
        var x = (i / (vals.length - 1)) * w
        var y = h - (vals[i] / max) * (h - 2) - 1
        if (i === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      ctx.strokeStyle = root.stroke
      ctx.lineWidth = 1.5
      ctx.stroke()

      ctx.lineTo(w, h)
      ctx.lineTo(0, h)
      ctx.closePath()
      ctx.fillStyle = Util.alpha(root.stroke, root.fillAlpha)
      ctx.fill()
    }
  }
}
