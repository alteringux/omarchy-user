import QtQuick
import qs.Commons

// Kit.MetaText — the dim, tracked caption sub-line that sits under a title or
// section header: the "DRAINING WATTS" line beneath the battery overlay's
// "Battery". Identical treatment to qs.Ui.PanelHero's `meta` slot, pulled out
// for panels that show a status line without a full hero.
//
//   Kit.MetaText {
//     content: root.running ? (root.count + " running") : "idle"
//     foreground: root.barForeground
//   }
//
// `uppercase` (default true) + the 1.2 letter-spacing make it a glanceable
// status tag. Set `uppercase: false` for a short lowercase detail fragment;
// for a full explanatory sentence use Style.font.caption + Kit.Palette.faint
// at regular weight instead (see ../../docs/adr/0005-panel-text-hierarchy.md).
Text {
  id: root

  property string content: ""
  property color foreground: Color.foreground
  property bool uppercase: true

  textFormat: Text.PlainText
  text: root.uppercase ? root.content.toUpperCase() : root.content
  visible: root.content.length > 0
  color: Qt.darker(root.foreground, 1.4)
  font.family: Style.font.family
  font.pixelSize: Style.font.caption
  font.bold: true
  font.letterSpacing: 1.2
  elide: Text.ElideRight
  width: parent ? parent.width : implicitWidth

  // Nerd-font outlines run ~10-15% of the em past the box Text reserves; a
  // sub-line at the top of a clipping list loses that sliver. Reserve it here,
  // same as PanelSectionHeader / Kit.SectionHeading.
  topPadding: Math.ceil(Style.font.caption * 0.15)
}
