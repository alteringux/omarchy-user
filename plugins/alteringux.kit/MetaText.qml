import QtQuick
import "." as Kit
import qs.Commons
import "../shared"

// Kit.MetaText — the dim, tracked caption sub-line that sits under a title or
// section header: the "DRAINING WATTS" line beneath the battery overlay's
// "Battery". Same treatment as qs.Ui.PanelHero's `meta` slot (plus the
// nerd-font top-padding the other kit labels carry), pulled out for panels
// that show a status line without a full hero.
//
//   Kit.MetaText {
//     content: root.running ? (root.count + " running") : "idle"
//     foreground: root.barForeground
//   }
//
// `uppercase` (default true) + the 1.2 letter-spacing make it a glanceable
// status tag. It elides on one line by default (like PanelHero's meta); a
// caller that needs a fragment to wrap can set `wrapMode: Text.WordWrap`.
// For a full explanatory sentence, don't use this at all — Style.font.caption
// + Kit.Palette.faint at regular weight is the hint role
// (see ../../docs/adr/0005-panel-text-hierarchy.md).
MarqueeText {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  property string content: ""
  property color foreground: _webPalette.foreground
  property bool uppercase: true

  requestedTextFormat: Text.PlainText
  text: root.uppercase ? root.content.toUpperCase() : root.content
  visible: root.content.length > 0
  color: _webPalette.muted
  textFont.family: Style.font.family
  textFont.pixelSize: Style.font.caption
  textFont.bold: true
  textFont.letterSpacing: 1.2
  requestedElide: Text.ElideRight
  width: parent ? parent.width : implicitWidth

  // Nerd-font outlines run ~10-15% of the em past the box Text reserves; a
  // sub-line at the top of a clipping list loses that sliver. Reserve it here,
  // same as PanelSectionHeader / Kit.SectionHeading.
  topPadding: Math.ceil(Style.font.caption * 0.15)
}
