pragma Singleton
import QtQuick
import qs.Commons

// Kit.Palette — semantic status colors for the alteringux.* plugins.
//
// The shell palette (Color) carries foreground / background / accent /
// urgent and nothing for "this number went up" green or "past its estimate"
// amber, so every plugin grew its own hardcoded hex (timers' #d29922,
// score's #4CAF50 / #F44336 / #FF9800, stocks' up/down greens). This
// singleton is the one place those live, so a restyle is one edit.
//
//   import "../alteringux.kit" as Kit
//   color: rising ? Kit.Palette.positive : Kit.Palette.negative
//
// `info` / `urgent` track the active theme; `positive` / `negative` /
// `warning` are fixed values chosen to stay legible on both light and dark
// omarchy themes (the theme system has no role for them).
QtObject {
  readonly property color positive: "#3fb950"
  readonly property color negative: "#f85149"
  readonly property color warning:  "#d29922"
  readonly property color info:     Color.accent
  readonly property color urgent:   Color.urgent

  // Pre-dimmed foreground for secondary text / hairline borders. Callers
  // that need a different alpha should still use Util.alpha on Color.foreground.
  readonly property color faint: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.55)
}
