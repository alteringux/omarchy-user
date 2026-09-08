import QtQuick
import QtQuick.Layouts
import qs.Commons

// Kit.Bullet — one row of a prose list: a glyph in the margin + a wrapping
// line. Replaces the per-plugin `Column { Text; Text }` list delegates
// (dashboard news / notes, score history, vpnrotate log, flow brief bullets).
//
//   Kit.Bullet { text: "Uber exits Nigeria and Uganda (BBC)"
//                foreground: root.barForeground }
//   Kit.Bullet { styled: true; text: "<b>Hook:</b> detail" }   // caller escapes
//                                                                // via Kit.Str
RowLayout {
  id: root

  property string text: ""
  property string glyph: "▪"
  property bool styled: false
  property color foreground: Color.foreground
  property color glyphColor: Color.accent
  property real pixelSize: Style.font.bodySmall

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(7)

  Text {
    Layout.alignment: Qt.AlignTop
    visible: root.glyph.length > 0
    text: root.glyph
    color: root.glyphColor
    font.pixelSize: root.pixelSize
  }

  Text {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    text: root.text
    textFormat: root.styled ? Text.StyledText : Text.PlainText
    wrapMode: Text.WordWrap
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: root.pixelSize
    lineHeight: 1.15
  }
}
