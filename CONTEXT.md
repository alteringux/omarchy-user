# Omarchy Customization

User-owned customization of an Omarchy Linux desktop: the Omarchy shell (status bar, popups, plugins) and related Hyprland/theme config layered on top of the stock `omarchy` package.

## Language

**Plugin**:
A user-owned shell extension living under `plugins/<id>/`, declared by a `manifest.json`. A plugin is built from a bar widget and (usually) a panel.
_Avoid_: App, extension

**Bar widget**:
The always-visible icon/label a plugin puts in the status bar (`BarWidget.qml`). Clicking or hotkeying it opens the plugin's panel.

**Panel**:
The popup a bar widget opens (`Panel.qml`), anchored under its bar icon. Holds the plugin's controls, stats, and settings.

**Dashboard**:
The specific existing plugin (`alteringux.dashboard`) showing news, system-update, and notes cards under one bar icon. Not a generic name for card/overview-style panels — each hobby domain gets its own plugin rather than a card in this one ([[0002]]).
