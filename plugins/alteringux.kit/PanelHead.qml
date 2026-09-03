import QtQuick
import qs.Commons
import qs.Ui

// Kit.PanelHead — the standard opener for an alteringux.* status panel: an
// optional glyph, a Title-Case title, and an UPPERCASE tracked meta sub-line —
// the exact shape of the battery overlay's hero. Thin wrapper over
// qs.Ui.PanelHero that takes the glyph as a plain string and leaves the
// foreground for the caller to bind to its bar text colour.
//
//   Kit.PanelHead {
//     title: "Stopwatch"
//     meta: hostWidget && hostWidget.active ? "Running" : "Ready"
//     foreground: root.barForeground
//   }
//
// `meta` hides itself when empty, so a panel with no glanceable status is just
// the promoted title. `glyph` is a nerd-font code point; omit it for a
// text-only head. `detail` (a bordered pill) and `trailingControl` pass
// straight through to PanelHero. See ../../docs/adr/0005-panel-text-hierarchy.md.
PanelHero {
  id: root

  property string glyph: ""

  fontFamily: Style.font.family
  iconComponent: root.glyph.length > 0 ? glyphIcon : null

  Component {
    id: glyphIcon
    Text {
      text: root.glyph
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
    }
  }
}
