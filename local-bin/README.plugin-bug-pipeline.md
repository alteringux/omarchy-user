# Plugin bug pipeline

Automatic bug capture for the `alteringux.*` Omarchy shell plugins. A caught
bug is recorded and handed to a headless `claude` agent that runs Matt Pocock's
`diagnosing-bugs` method and, when the fix is clear and low-risk, applies it in
the working tree (never committed).

## Parts

| File | Role |
|---|---|
| `omarchy-plugin-bug-report` | Dispatcher. Dedupe (signature + 30-min cooldown), kill-switch check, writes a bug bundle to `~/.local/state/omarchy/plugin-bugs/`, then launches `claude -p --agent plugin-bug-fixer --dangerously-skip-permissions` detached, one at a time (flock). |
| `plugin-bin-guard.sh` | Sourced by a plugin's `bin/` scripts. Traps a non-zero exit and calls the dispatcher with `--source script`. Chains, does not clobber, the script's own traps. |
| `omarchy-plugin-bug-watch` | Follows the `omarchy-shell` journal; feeds WARN/ERROR lines that name an `alteringux.*` plugin and carry a JS/QML error signature to the dispatcher with `--source qml-log`. |
| `omarchy-plugin-bug-watch.service` | User unit for the watcher (`~/.config/systemd/user/`). Mirrors `omarchy-crash-watch`: graphical-session scoped, `Restart=always`, disabled by the kill switch. |
| `omarchy-plugin-bug-report-toggle` | `on` / `off` / `status`. `off` writes the kill switch and stops the watcher. |
| `~/.claude/agents/plugin-bug-fixer.md` | The constrained agent the dispatcher launches. |
| `BugGuard.js` (in each plugin dir) | `.pragma library` helper. `configure(id, execFn)` once; `run(ctx, fn)` / `call(ctx, fn, fallback)` wrap risky handler bodies — a throw is logged, dispatched with `--source guard`, and swallowed so the widget keeps running. |

## Three bug sources

1. **guard** — a JS exception thrown inside a `BugGuard.run` / `BugGuard.call`
   block in plugin QML.
2. **script** — a `bin/` helper script exits non-zero.
3. **qml-log** — the shell logs a QML/JS error naming an `alteringux.*` plugin.

## Kill switch

`~/.local/state/omarchy/toggles/plugin-bug-report-off` (any existence).
The dispatcher exits early if present; the watcher unit refuses to start.
Toggle with `omarchy-plugin-bug-report-toggle off|on`.

## Safety properties

- One agent at a time (flock on `~/.local/state/omarchy/plugin-bugs/agent.lock`).
- 30-min per-signature cooldown (`PLUGIN_BUG_COOLDOWN` env to override); a crash
  loop produces one report, not one per tick.
- The agent runs with `cwd = ~/.config/omarchy` (a git repo) and is instructed
  never to `git add` / `commit` / `stash` / `reset` — review its edits with
  `git -C ~/.config/omarchy diff` and revert with checkout if unwanted.
- Every run leaves a bundle + `*.agent.log` in `~/.local/state/omarchy/plugin-bugs/`.
- Desktop notifications on start, on completion (with `git diff --stat`), and on
  failure.

## Enabling

```
omarchy-plugin-bug-report-toggle on     # clears kill switch, enables + starts the watcher
omarchy-plugin-bug-report-toggle status
```

The `guard` and `script` sources work as soon as the kill switch is clear —
they do not need the watcher service.
