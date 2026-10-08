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
| `themes/` | Custom themes (`drain-and-win`, `generative-art`, `gta-iv`, `siren-ink`, `aether`) with their colour files, wallpapers, and generation scripts |
| `themed/` | Theme-templated config fragments |
| `motivator/` | Affirmation/quote rotator (`motivate.sh`, `motivator.py`) |
| `ai-briefing/` | `briefing.sh` — a boot-time AI briefing notification (reads its key from `ai-briefing/env`, not committed) |
| `tests/` | Shell test harness for `omarchy-hide-window` |
| `hypr/` | **Snapshot** of the custom `~/.config/hypr/` Lua config (live files stay in `~/.config/hypr/`) |
| `local-bin/` | **Snapshot** of the user-authored `~/.local/bin/omarchy-*` helper scripts the plugins/hooks call |
| `docs/adr/`, `CONTEXT.md` | Design notes / glossary for the plugin ecosystem |

## Plugins

The catalog below covers the 42 first-party product plugins. The shared `alteringux.kit` library is documented above as infrastructure; third-party plugins are excluded. Names, kinds, and purposes come from each plugin manifest.

| Plugin | Kind | Purpose |
|------|------|---------|
| `alteringux.agenda` | service | Headless service that watches local .ics calendars and notifies before the next event |
| `alteringux.agentglass` | bar widget | All local agent workflows and the full cockpit |
| `alteringux.ask` | overlay | Type a question, get a NanoGPT answer, and hear it through Piper TTS |
| `alteringux.bottombar` | service | A second bar along the bottom edge of every monitor that hosts overflow bar widgets the top bar has no room for. It instantiates the real… |
| `alteringux.breathe` | bar widget | Live phase and countdown on the bar; click for techniques, metrics and settings, or breathe along with the fullscreen guide |
| `alteringux.calendar` | bar widget | Today's birthdays/holidays on the bar; click for a month grid — click any date to block time — plus an Ask AI box that can add, move or free up… |
| `alteringux.cliamp` | bar widget | cliamp transport controls + spectrum visualiser |
| `alteringux.clock` | bar widget | Date/time label with a calendar popup |
| `alteringux.conductor` | bar widget | One click runs a whole ritual (Focus / Morning / Wind-down) across pomodoro, timers, score, stopwatch, reminders, news, stocks, dictionary, VPN… |
| `alteringux.countdown` | bar widget | Scrolling marquee of your event countdowns; click for an add/list overlay |
| `alteringux.cpumon` | bar widget | CPU % with a per-core and trend breakdown |
| `alteringux.cursortrail` | bar widget | Fading pointer trail overlay. |
| `alteringux.dashboard` | bar widget | News/status dashboard with a card overlay |
| `alteringux.deskpet` | bar widget | Mood/hunger indicator for your floating desktop pet; click for the settings panel (pick a pet, feed, play, mute). |
| `alteringux.devcast` | bar widget | Interactive replays of Claude Code build sessions |
| `alteringux.dictionary` | overlay | Look up a word: type or highlight it, get suggestions, pick one for a full overview |
| `alteringux.diskmon` | bar widget | Disk usage % with a per-mount and trend breakdown |
| `alteringux.flow` | bar widget | Latest output of a flow (~/Work/bin/flow) plus a draggable node canvas in the popup |
| `alteringux.glimpse` | bar widget | Scene-memory trainer: shows a streak / due count, reddens when a scheduled review is due; click for the panel. SUPER+SHIFT+ALT+G starts a drill round. |
| `alteringux.grip` | bar widget | Open/overdue task count that reddens with age; click for quick triage. A daemon raises check-ins on an adaptive cadence and a fullscreen takeover… |
| `alteringux.memmon` | bar widget | RAM % with swap and trend breakdown |
| `alteringux.nanogpt` | bar widget | Weekly quota gauge plus token and cost analytics for nano-gpt.com |
| `alteringux.netwatch` | bar widget | Network in/out rate, totals, and analytics |
| `alteringux.newsbar` | service | A second bar along the bottom of every monitor, split in two: world/general-news headlines from configurable RSS/Atom sources on the right (click… |
| `alteringux.notifications` | service | Notification daemon, popups, DND, and history |
| `alteringux.phone` | bar widget | Phone icon for the bar; click for the contact picker and to start a call. Shows a live pill while a call is connected. Contacts have fixed… |
| `alteringux.pomodoro` | bar widget | Work/break timer with daily focus progress, stats, and settings |
| `alteringux.pulse` | bar widget | Bell with an unread badge that reddens when a plugin needs action; click for the activity feed and the next-action pick. |
| `alteringux.recall` | bar widget | Due-review counter that reddens with backlog; click for the deck panel. A daemon teaches a short technique lesson full-screen when one is ready,… |
| `alteringux.reminders` | overlay | Interactive reminder setup flow |
| `alteringux.reposwatch` | bar widget | Dirty / ahead-behind counts across your git repos |
| `alteringux.score` | bar widget | Track and display a score counter |
| `alteringux.skilldashboard` | bar widget | Skill usage and lifecycle dashboard |
| `alteringux.sports` | bar widget | Live scores and next fixtures on the bar; click for the full dashboard — fixtures, results, players, standings, and predictions |
| `alteringux.stocks` | bar widget | Worldwide top gainers/losers, trending searches, and a 52-week filter |
| `alteringux.stopwatch` | bar widget | Shows elapsed time on a running stopwatch, with start/cancel controls and a configurable spoken interval |
| `alteringux.sysmon` | bar widget | CPU %, RAM %, and temperature at a glance |
| `alteringux.tempmon` | bar widget | CPU temperature with per-sensor and trend breakdown |
| `alteringux.timers` | bar widget | Labelled count-up timers shown as a card list in a popup overlay |
| `alteringux.ttsplayer` | bar widget | Shows a speaker icon only while Piper TTS is talking; click for pause / stop / speed / loop / mute and a progress bar |
| `alteringux.vpnrotate` | bar widget | Shield icon showing Proton VPN state + exit country; click for connect / disconnect, rotate-now, and auto-rotate on a configurable interval;… |
| `alteringux.wordstep` | overlay | Read selected text with optional Piper speech, paced syllable highlighting, code-aware reading, and saved statistics |

## Running the tests

Run the repository checks from this checkout:

```bash
bash tests/run-all.sh
```

This runs the repository shell suites, a Quickshell compile probe for every
plugin QML component, the plugin catalog contract, and each plugin's
JavaScript, shell, and Python tests. Pass a
substring to run matching suite names only:

```bash
bash tests/run-all.sh sports
```

CI runs the same discovered logic and CLI suites with Bash, Node.js 26.7.0,
Python 3, and `jq`, using an explicit portable profile:

```bash
bash tests/run-all.sh --portable
```

This profile prints the three deferred desktop release gates: live bar
geometry/popup IPC, QML component loading, and the Omarchy manifest schema
validator. Run the default command on the target Omarchy desktop before a
release; a green portable CI run does not verify these native gates.

## Updating and rollback

This repository is the live user configuration on this machine. Keep changes
in Git so a known-good version can be restored without replacing ignored local
settings or credentials. Before applying a committed update, require a clean
worktree, run `bash tests/run-all.sh`, then restart the shell with
`omarchy restart shell`. To back out a bad commit, use `git revert <commit>` so
later work is preserved, rerun the checks, and restart the shell. On a fresh
machine, follow the copy steps below and keep its local secrets and feed files
out of Git.

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

Some helpers depend on `piper-tts` + Piper voices, `jq`, and `hermes` on PATH.

## License

MIT — see [LICENSE](LICENSE).
