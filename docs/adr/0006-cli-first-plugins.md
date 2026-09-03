# CLI-first plugins: the state-mutating logic lives in a `~/.local/bin` tool

## Status

Accepted 2026-09-03. Rollout in progress.

## Context

The `alteringux.*` bar widgets split into two camps:

- **CLI-first** — `stopwatch`, `vpnrotate`, `ttsplayer`, `stocks`, `dictionary`,
  `newsbar`, `agenda`. A `~/.local/bin` tool owns the mechanism *and* every write
  to the plugin's JSON state file. The QML is a thin view: `Kit.Store { watch: true }`
  to render, `Process` / `execDetached` to run verbs.
- **Logic-in-QML** — `score`, `timers`, `countdown`, `pomodoro`. The reducers ran
  *inside* `BarWidget.qml` (`Model.increment(...)` etc.), and `Kit.Store` in owned
  mode wrote the result back on a debounce.

The logic-in-QML camp can only be driven from the running shell. A Hyprland
keybind, a cron job, `omarchy-voice`, or `bin/flow` cannot add a timer, bump the
score, or start a pomodoro without poking IPC at a live Quickshell. Testing the
reducers needs the Node harness to import a QML-flavoured JS file. And "who writes
this file" is ambiguous — the `Kit.Store` header spends three paragraphs on the
races that ambiguity creates.

## Decision

Every state-mutating plugin gets a **`~/.local/bin/omarchy-<plugin>` CLI that is
the sole writer of its state file(s).** The plugin becomes watch + exec, matching
the camp that already worked this way.

| Plugin | CLI | Owns |
|---|---|---|
| `score` | `omarchy-score` | `score-state.json` |
| `timers` | `omarchy-timers` | `timers.json`, `timers-history.json` |
| `countdown` | `omarchy-countdowns` | `countdowns.json`, `countdown-history.json` |
| `pomodoro` | `omarchy-pomodoro` (+ `systemd --user` daemon) | `pomodoro-session.json`, `pomodoro-stats.json`, `pomodoro-history.json` — see below |

`omarchy-countdowns` is plural: `omarchy-countdown` is already the unrelated
spoken days-until tool.

### Rules

1. **Language: Bash + `jq`.** Matches every existing `omarchy-*` CLI
   (`omarchy-stopwatch`, `omarchy-dictionary-*`, `omarchy-stocks-*`).
2. **State dir override.** The CLI honours `OMARCHY_STATE_DIR` (default
   `~/.local/state/omarchy`) so `test/cli.test.sh` drives it against a temp dir.
3. **Atomic writes**, history capped at write time — the CLI reproduces what the
   plugin's `Kit.Store.serialize` did.
4. **Config files stay widget-territory when they are policy the widget owns**
   (`vpnrotate-config.json`, `ttsplayer.json`, `pomodoro-config.json`). Hand-edited
   settings, never touched by an action. The CLI *reads* config and *seeds* it if
   missing, so it runs standalone; the widget may still keep `seedOnCreate`.
5. **Panels bind to the widget's watched store** (`hostWidget.state.*`), no manual
   `syncFromWidget()` copy-on-click — the watch re-read is the update path.
6. **Verb surface**: `get` (print state JSON), `status` (richer JSON for the IPC
   handler), then one verb per former reducer. IPC handlers and panel buttons both
   call the same verb via one serialising `Process`.

### `Model.js`

Keeps the **pure parse + format + predicate** helpers the QML still needs to
render (`parseState`, `formatElapsed`, `isPaused`, `rankLabels`, …). The
**reducer** exports (`increment`, `addEntry`, `pauseEntry`, …) are now
reimplemented in the CLI and left in `Model.js` as vestigial, still-tested
reference — a later pass may prune them and fold their `model.test.js` cases into
`cli.test.sh`.

### Pomodoro is different — it got the daemon

`score` / `timers` / `countdown` are CRUD on a list: a verb writes the file and
returns. `pomodoro` runs a **1-second countdown that must reach zero and fire a
transition (sound, notification, streak credit) with the panel closed**, so
`omarchy-pomodoro` also has a `__run` mode launched as a transient
`systemd --user` unit (`omarchy-pomodoro.service`), exactly like
`omarchy-stopwatch`. That loop owns the tick, phase transitions, transition
sounds, ready-reminders and streak/stats/history writes.

- Verbs: `toggle` / `start` / `pause` / `resume` / `skip` / `complete` / `reset`
  / `restore` / `get` / `status`. `toggle` and `resume` `ensure_daemon`; `reset`
  stops it; `restore` (called once by the widget on load) reconciles a session
  persisted across a reboot — crediting a WORK block that ran out offline — and
  respawns the daemon if a phase is still live.
- The widget keeps a 1-second **display** clock that reconstructs the mm:ss
  readout from `savedAtMs` between the daemon's ~5-second heartbeat writes. It
  never transitions anything.
- `pomodoro-config.json` stays widget-owned (rule 4) — durations and sound paths,
  edited from the settings panel and by hand. The daemon only reads it.
- `OMARCHY_POMODORO_NO_DAEMON=1` / `OMARCHY_POMODORO_QUIET=1` let `cli.test.sh`
  exercise every transition (including the offline-restore and streak maths)
  without spawning a unit or firing notifications.

## Consequences

- **Good:** every plugin action is now a shell one-liner — bindable, cron-able,
  callable by other agents; headless-testable; one writer, no race.
- **Cost:** the reducer logic exists twice (JS + bash) until the prune pass. The
  bash reimplementations are covered by `cli.test.sh` to catch drift.
- **Latency:** live-ticking widgets (`timers`, `countdown`, `pomodoro`) still
  compute the tick locally in QML from the stored epochs — the CLI owns
  *transitions*, never *frames*. No per-second subprocess.
- **Usage analytics:** `Kit.Usage` still records in QML, so a keybind-invoked verb
  is not counted. Acceptable; revisit if keybind use becomes common.
