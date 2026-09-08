import QtQuick
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit

// Shared min / avg / max / now readout under each panel's sparkline. `stats`
// is a { min, avg, max, cur, n } from Model.historyStats; `format` turns a
// number into its display string (e.g. "42%" or "68°C").
Column {
  id: root

  property var stats: ({ min: 0, avg: 0, max: 0, cur: 0, n: 0 })
  property var format: function (v) { return Math.round(v) + "" }
  property string foreground: "white"
  property string windowLabel: "10 MIN"

  spacing: Style.space(4)

  Kit.SectionHeading { text: "TREND · LAST " + root.windowLabel; foreground: root.foreground }

  Grid {
    width: parent.width
    columns: 4
    columnSpacing: Style.space(10)
    rowSpacing: Style.space(4)

    Repeater {
      model: [
        { l: "MIN", v: root.stats.n > 0 ? root.format(root.stats.min) : "—" },
        { l: "AVG", v: root.stats.n > 0 ? root.format(root.stats.avg) : "—" },
        { l: "MAX", v: root.stats.n > 0 ? root.format(root.stats.max) : "—" },
        { l: "NOW", v: root.stats.n > 0 ? root.format(root.stats.cur) : "—" }
      ]
      delegate: Column {
        required property var modelData
        spacing: Style.space(2)
        Kit.MetaText { width: implicitWidth; content: modelData.l; foreground: root.foreground }
        Text {
          text: modelData.v
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }
    }
  }
}
