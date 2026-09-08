import QtQuick
import qs.Commons
import "." as Kit

// Kit.SectionHeading — the louder header that introduces a card or a group of
// rows inside one: an accent, optionally UPPERCASE, bold label with an
// optional hairline rule beneath.
//
// Distinct from the stock PanelSectionHeader, which is the small dim caption
// at the very top of a whole panel ("TIMERS", "DASHBOARD") — keep using that
// for the panel title, and this for sections within.
//
//   Kit.SectionHeading { text: "Top stories" }
//   Kit.SectionHeading { text: "World"; pixelSize: Style.font.heading; rule: true }
//
// For a heading with a trailing badge / buttons, put this in your own RowLayout
// next to them rather than reaching for a slot.
Column {
  id: root

  property string text: ""
  property bool uppercase: true
  property bool bold: true
  property real pixelSize: Style.font.body
  property real letterSpacing: 0.5
  property bool rule: false
  property color foreground: Color.accent

  width: parent ? parent.width : label.implicitWidth
  spacing: Style.space(4)

  Text {
    id: label
    width: parent.width
    text: root.uppercase ? root.text.toUpperCase() : root.text
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: root.pixelSize
    font.bold: root.bold
    font.letterSpacing: root.letterSpacing
    elide: Text.ElideRight
    // reserve the nerd-font ascent overshoot, same as PanelSectionHeader
    topPadding: Math.ceil(root.pixelSize * 0.15)
  }

  Rectangle {
    visible: root.rule
    width: parent.width
    height: 1
    color: Kit.Palette.hairline
  }
}
