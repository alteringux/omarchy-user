import QtQuick
import qs.Commons
import qs.Ui as ShellUi
import "." as Kit

// Keep the shell's theme and click/keyboard behavior, with one native action
// contract for plugin controls. Icon-only callers supply a descriptive name.
ShellUi.Button {
  id: root
  Kit.Palette { id: _webPalette }
  foreground: _webPalette.foreground
  accent: _webPalette.accent
  tooltipBackground: _webPalette.webSafeColor(Color.tooltip.background)
  tooltipForeground: _webPalette.contrastColorFor(Color.tooltip.text, tooltipBackground)
  tooltipBorder: _webPalette.contrastColorFor(Color.tooltip.border, tooltipBackground, 3)
  focusable: true
  Accessible.role: Accessible.Button
  Accessible.name: tooltipText || text || iconText
  Accessible.onPressAction: if (root.enabled && root.visible) root.clicked()
}
