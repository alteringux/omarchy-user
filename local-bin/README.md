# local-bin/ — helper-script snapshot

User-authored scripts that normally live in `~/.local/bin/` and are invoked by
the plugins, hooks, and Hyprland keybindings in this repo. Copied here so the
setup is self-contained; the live copies stay in `~/.local/bin/`.

Nothing packaged by Omarchy is included — these are all custom.

| Script(s) | Used by |
|-----------|---------|
| `omarchy-dictionary-*` | `alteringux.dictionary` plugin |
| `omarchy-countdown` | `alteringux.countdown` plugin |
| `omarchy-stopwatch` | `alteringux.stopwatch` plugin |
| `omarchy-speak-*`, `piper-tts` | Piper TTS briefings/recaps, `alteringux.ttsplayer` |
| `omarchy-narrate*` | Screenshot / selection narration |
| `omarchy-plugin-bug-*`, `plugin-bin-guard.sh` | Plugin bug-report pipeline (see `README.plugin-bug-pipeline.md`) |
| `omarchy-hide-window` | Scratchpad-style window hide/restore (bound in `hypr/bindings.lua`) |
| `omarchy-executive` | AI "executive" helper (reads its key from an env file, never hard-coded) |
| `bg-noise-toggle`, `lid-suspend-toggle`, `omarchy-toggle-clock` | Hyprland keybinding toggles |

Install: `cp local-bin/* ~/.local/bin/ && chmod +x ~/.local/bin/omarchy-* ~/.local/bin/*.sh`
