import QtQuick
import qs.Commons
import "PaletteLogic.js" as Logic

// Kit.Palette — web-safe, contrast-aware semantic colors for alteringux.*.
//
// The shell palette carries the theme roles; this component normalizes those
// and supplies shared semantic status colors to each plugin component.
//
//   Kit.Palette { id: palette }
//   color: rising ? palette.positive : palette.negative
//   color: palette.signColor(delta)        // +ve green / -ve red / 0 faint
//   color: palette.toneColor(card.tone)    // "accent"|"positive"|…
//
// Theme colors are snapped to the classic 216 RGB values. Text roles choose
// the nearest safe color that keeps 4.5:1 contrast against their surface.
// Alpha remains available for overlays; the underlying RGB channels stay safe.
//
// The `card*` / `hairline` tokens are the translucent-card look every panel
// hand-copied as `Util.alpha(fg, 0.05)` / `0.14`; they back Kit.Card.
QtObject {
  id: pal

  readonly property color background: webSafeColor(Color.background)
  readonly property color foreground: contrastColorFor(Color.foreground, background)
  readonly property color accent: contrastColorFor(Color.accent, background)
  readonly property color urgent: contrastColorFor(Color.urgent, background)
  readonly property color muted: contrastColorFor(Color.muted, background)
  readonly property color faint: muted

  readonly property color barBackground: webSafeColor(Color.bar.background)
  readonly property color barForeground: contrastColorFor(Color.bar.text, barBackground)
  readonly property color barActive: contrastColorFor(Color.bar.active, barBackground, 3)
  readonly property color barMuted: contrastColorFor(Color.muted, barBackground)
  readonly property color barAccent: contrastColorFor(Color.accent, barBackground)
  readonly property color barUrgent: contrastColorFor(Color.urgent, barBackground)

  readonly property color menuBackground: webSafeColor(Color.menu.background)
  readonly property color menuText: contrastColorFor(Color.menu.text, menuBackground)
  readonly property color menuBorder: contrastColorFor(Color.menu.border, menuBackground, 3)
  readonly property color menuScrim: webSafeColor(Color.menu.scrim)
  readonly property color menuSelectedBackground: webSafeColor(Color.menu.selectedBackground)
  readonly property color menuSelectedText: contrastColorFor(Color.menu.selectedText, menuSelectedBackground, undefined, menuBackground)

  readonly property color popupBackground: webSafeColor(Color.popups.background)
  readonly property color popupText: contrastColorFor(Color.popups.text, popupBackground)
  readonly property color popupBorder: contrastColorFor(Color.popups.border, popupBackground, 3)

  readonly property color notificationBackground: webSafeColor(Color.notifications.background)
  readonly property color notificationText: contrastColorFor(Color.notifications.text, notificationBackground)
  readonly property color notificationBorder: contrastColorFor(Color.notifications.border, notificationBackground, 3)
  readonly property color notificationCountdown: contrastColorFor(Color.notifications.countdown, notificationBackground)

  readonly property color positive: statusColorFor("positive", background)
  readonly property color negative: statusColorFor("negative", background)
  readonly property color warning: statusColorFor("warning", background)
  readonly property color barPositive: statusColorFor("positive", barBackground)
  readonly property color barNegative: statusColorFor("negative", barBackground)
  readonly property color barWarning: statusColorFor("warning", barBackground)
  readonly property color info: accent

  // ---- shared card surface (see Kit.Card) ---------------------------------
  readonly property color cardBg:     cardBackgroundFor(foreground)
  readonly property color cardBorder: cardBorderFor(foreground)
  readonly property color hairline:   Logic.alphaColor(Qt.color(webSafeColor(foreground)), 0.16)

  function cardBackgroundFor(foreground) { return Logic.alphaColor(Qt.color(pal.webSafeColor(foreground)), 0.05) }
  function cardBorderFor(foreground) { return Logic.alphaColor(Qt.color(pal.webSafeColor(foreground)), 0.14) }

  function webSafeColor(color) {
    var value = typeof color === "string" ? Qt.color(color) : color
    return Logic.webSafeColor(value)
  }

  function contrastRatio(foreground, surface, backdrop) {
    var first = typeof foreground === "string" ? Qt.color(foreground) : foreground
    var second = typeof surface === "string" ? Qt.color(surface) : surface
    var base = backdrop === undefined ? Color.background : (typeof backdrop === "string" ? Qt.color(backdrop) : backdrop)
    return Logic.contrastRatio(first, second, base)
  }

  function contrastColorFor(preferred, surface, minimum, backdrop) {
    var target = typeof preferred === "string" ? Qt.color(preferred) : preferred
    var face = typeof surface === "string" ? Qt.color(surface) : surface
    var base = backdrop === undefined ? Color.background : (typeof backdrop === "string" ? Qt.color(backdrop) : backdrop)
    return Logic.contrastColorFor(target, face, minimum, base)
  }

  function statusColorFor(tone, surface, minimum, backdrop) {
    var preferred = tone === "positive" ? "#00ff00"
      : tone === "negative" ? "#ff0000"
      : tone === "warning" ? "#cc9900"
      : "#ffffff"
    var face = surface === undefined ? background : surface
    return contrastColorFor(preferred, face, minimum, backdrop)
  }

  function barTextColorFor(preferred) { return contrastColorFor(preferred, barBackground) }

  // ---- semantic helpers --------------------------------------------------
  // A card / heading "tone" -> its accent color. "neutral" == no emphasis.
  function toneColor(tone, surface, minimum, backdrop) {
    var face = surface === undefined ? pal.background : surface
    if (tone === "positive" || tone === "negative" || tone === "warning")
      return pal.statusColorFor(tone, face, minimum, backdrop)
    if (tone === "accent") return pal.contrastColorFor(Color.accent, face, minimum, backdrop)
    return pal.contrastColorFor(Color.muted, face, minimum, backdrop)
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
