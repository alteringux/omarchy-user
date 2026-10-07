pragma Singleton
import QtQuick
import qs.Commons

// Kit.Palette — semantic status colors + shared surface tokens for the
// alteringux.* plugins.
//
// The shell palette (Color) carries foreground / background / accent /
// urgent and nothing for "this number went up" green or "past its estimate"
// amber, so every plugin grew its own hardcoded hex (timers' #d29922,
// score's #4CAF50 / #F44336 / #FF9800, stocks' up/down greens). This
// singleton is the one place those live, so a restyle is one edit.
//
//   import "../alteringux.kit" as Kit
//   color: rising ? Kit.Palette.positive : Kit.Palette.negative
//   color: Kit.Palette.signColor(delta)        // +ve green / -ve red / 0 faint
//   color: Kit.Palette.toneColor(card.tone)    // "accent"|"positive"|…
//
// `info` / `urgent` track the active theme; `positive` / `negative` /
// `warning` are fixed values chosen to stay legible on both light and dark
// omarchy themes (the theme system has no role for them).
//
// The `card*` / `hairline` tokens are the translucent-card look every panel
// hand-copied as `Util.alpha(fg, 0.05)` / `0.14`; they back Kit.Card.
QtObject {
  id: pal

  readonly property color positive: "#3fb950"
  readonly property color negative: "#f85149"
  readonly property color warning:  "#d29922"
  readonly property color info:     Color.accent
  readonly property color urgent:   Color.urgent

  // Pre-dimmed foreground for secondary text / hairline borders. Callers
  // that need a different alpha should still use Util.alpha on Color.foreground.
  readonly property color faint: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.55)
  // Tertiary text (source citations, timestamps) — the theme's own muted role.
  readonly property color muted: Color.muted

  // ---- shared card surface (see Kit.Card) ---------------------------------
  readonly property color cardBg:     Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
  readonly property color cardBorder: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14)
  readonly property color hairline:   Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)

  // ---- semantic helpers --------------------------------------------------
  // A card / heading "tone" -> its accent color. "neutral" == no emphasis.
  function toneColor(tone) {
    if (tone === "positive") return pal.positive
    if (tone === "negative") return pal.negative
    if (tone === "warning")  return pal.warning
    if (tone === "accent")   return Color.accent
    return pal.faint
  }

  // A signed number -> green above 0, red below, faint at (near) 0.
  function signColor(n) {
    var v = Number(n)
    if (!isFinite(v) || Math.abs(v) < 1e-9) return pal.faint
    return v > 0 ? pal.positive : pal.negative
  }

  // Same, from a display string: "+2" / "-3" / "2" -> tinted; "—" / "n/a" /
  // "" / non-numeric -> faint.
  function signColorForText(s) {
    var t = String(s == null ? "" : s).trim()
    if (!/^[+-]?[0-9]/.test(t)) return pal.faint
    return pal.signColor(parseFloat(t.replace("+", "")))
  }
}
