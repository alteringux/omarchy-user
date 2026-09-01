# omarchy-user

Personal customization layer for an [Omarchy](https://omarchy.org/) Linux desktop
(Arch + Hyprland + the Quickshell-based Omarchy shell). This is the contents of
`~/.config/omarchy/` plus snapshots of the Hyprland config and the helper scripts
those pieces depend on.

Built and maintained on top of the stock `omarchy` package (currently 4.x). Nothing
here modifies `/usr/share/omarchy/` — it all layers on top via the shell's plugin
system, the hooks directories, and user config files.

## Layout

| Path | What |
|------|------|
| `plugins/alteringux.*/` | Custom Omarchy shell plugins — bar widgets, panels, and services (see below) |
| `plugins/alteringux.kit/` | Shared QML/JS library the plugins import: `Store` (persistence), `BugGuard` (error capture), `InlineEdit`, `Usage`, `EmptyState`, `Palette` |
| `hooks/` | Automation hooks that run on system events (`post-update.d`, `theme-set.d`, `font-set.d`, `post-boot.d`, …) |
| `extensions/` | `omarchy-menu.jsonc` — launcher/menu customization |
| `themes/` | Custom themes (`drain-and-win`, `generative-art`, `gta-vi`, `siren-ink`, `aether`) with their colour files, wallpapers, and generation scripts |
| `themed/` | Theme-templated config fragments |
| `motivator/` | Affirmation/quote rotator (`motivate.sh`, `motivator.py`) |
| `ai-briefing/` | `briefing.sh` — a boot-time AI briefing notification (reads its key from `ai-briefing/env`, not committed) |
| `tests/` | Shell test harness for `omarchy-hide-window` |
| `hypr/` | **Snapshot** of the custom `~/.config/hypr/` Lua config (live files stay in `~/.config/hypr/`) |
| `local-bin/` | **Snapshot** of the user-authored `~/.local/bin/omarchy-*` helper scripts the plugins/hooks call |
| `docs/adr/`, `CONTEXT.md` | Design notes / glossary for the plugin ecosystem |

## Plugins

| Plugin | Kind | Purpose |
|--------|------|---------|
| `alteringux.agenda` | service | Calendar agenda feed |
| `alteringux.countdown` | widget + panel | Countdowns to dated events |
| `alteringux.dashboard` | widget + panel | News / update / notes cards under one bar icon |
| `alteringux.dictionary` | overlay | Word lookup: type or highlight a word, get an overview |
| `alteringux.newsbar` | service | A second bottom bar: marquee of world-news RSS/Atom headlines |
| `alteringux.notifications` | service | Notification centre (auto-expiring critical toasts) |
| `alteringux.pomodoro` | widget + panel | Pomodoro timer |
| `alteringux.score` | widget + panel | Daily score / streak tracker |
| `alteringux.stocks` | widget + panel | Personal watchlist + market trending |
| `alteringux.stopwatch` | widget + panel | Stopwatch |
| `alteringux.timers` | widget + panel | Named countdown timers with history |
| `alteringux.ttsplayer` | widget + panel | Playback control for the Piper TTS helpers |

## Running the tests

Plugin logic is pure JS with Node's built-in test runner (no install):

```bash
for t in plugins/*/test/*.test.js; do node --test "$t"; done
```

The `omarchy-hide-window` shell test:

```bash
tests/omarchy-hide-window.test.sh
```

## Installing on a fresh machine

This is a personal config, not a distributable package. Rough steps:

1. Install Omarchy, then copy `plugins/`, `hooks/`, `extensions/`, `themes/`,
   `themed/`, `motivator/`, `ai-briefing/`, `CONTEXT.md`, `docs/` into
   `~/.config/omarchy/`.
2. Copy `local-bin/*` into `~/.local/bin/` (`chmod +x`).
3. Merge `hypr/*` into `~/.config/hypr/`.
4. Copy `newsbar-feeds.example.json` → `newsbar-feeds.json` and edit.
5. Create `ai-briefing/env` with the required key if you use the briefing hook.
6. `omarchy restart shell`.

Some helpers depend on `piper-tts` + Piper voices, `jq`, and a `claude` CLI on PATH.

## License

MIT — see [LICENSE](LICENSE).
