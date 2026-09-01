import QtQuick
import qs.Commons

// Kit.EmptyState — the "nothing here yet" line every plugin panel hand-rolls
// (timers' "No active timers.", score's "No history yet", …). One place for
// the styling so they all read the same.
//
//   Kit.EmptyState {
//     visible: list.count === 0
//     text: "No active timers."
//     hint: "Add one above."          // optional second line
//     foreground: root.barForeground  // match the host panel's text color
//   }
Column {
  id: root

  property string text: ""
  property string hint: ""
  property color foreground: Color.foreground

  spacing: Style.space(2)
  width: parent ? parent.width : implicitWidth

  Text {
    width: parent.width
    text: root.text
    color: root.foreground
    opacity: 0.55
    wrapMode: Text.WordWrap
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    visible: root.hint.length > 0
    width: parent.width
    text: root.hint
    color: root.foreground
    opacity: 0.35
    wrapMode: Text.WordWrap
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
