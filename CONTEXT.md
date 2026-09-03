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

**Edit in place**:
The interaction for any user-authored label on a card or panel title: click it, it becomes a text field; Enter or focus-out applies and persists instantly, Esc cancels. No edit button, no dialog. Shared from the kit as `Kit.InlineEdit` ([[0003]]).

**Scrollable panel body**:
A panel body that can be taller than the panel. Always a `Kit.PanelScroll` (a `Flickable` subclass with `clip`, bounds, a resting-visible vertical scrollbar, and an amplified wheel/touchpad step baked in), never a bare `Flickable`. A scrollable `ListView` — which can't be wrapped — takes an inline `ScrollBar` plus `Kit.WheelBoost` ([[0004]]).
