# hypr/ — Hyprland config snapshot

A point-in-time copy of the customized files under `~/.config/hypr/`. The live
files remain there; these are checked in so the whole desktop setup travels in
one repo.

| File | What changed from stock |
|------|-------------------------|
| `bindings.lua` | The bulk of the customization — keybindings for the custom plugins, TTS overlays, window-hide, background noise, lid-suspend toggle, etc. |
| `input.lua` | Keyboard/pointer tweaks |
| `looknfeel.lua` | Gaps, borders, blur, animations |
| `monitors.lua` | Display layout |
| `autostart.lua` | Extra `exec-once` entries |
| `hyprland.lua`, `hyprsunset.conf`, `xdph.conf`, `.luarc.json` | Minor overrides |

To apply on another machine, merge these into `~/.config/hypr/` and run
`hyprctl reload` (check `hyprctl configerrors`).
