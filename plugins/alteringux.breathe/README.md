# alteringux.breathe

Guided breathing on the bar: twelve techniques, a fullscreen animated breath
guide, a compact guide in the panel, a custom pattern builder, and metrics that
are worth opening. Sessions can loop, and a long hold can be cut short without
ending the session.

```
 󰡾  Inhale 4  1/8        ← the bar, mid-session
```

## Shape

| File | What it is |
|---|---|
| `techniques.json` | **Canonical** technique catalogue. Edit here first. |
| `Model.js` | All pure logic: catalogue, phase resolution, the orb envelope, metrics reducers. No QML. |
| `BarWidget.qml` | The host — owns the stores, the CLI bridge, IPC, and both surfaces. |
| `Guide.qml` | The fullscreen layer-shell breath guide. |
| `Panel.qml` | Technique picker, compact guide, settings. |
| `Metrics.qml` | The numbers block inside the panel. |
| `TechniqueEditor.qml` | The custom pattern builder. |
| `~/.local/bin/omarchy-breathe` | The engine + `systemd --user` daemon. **Sole writer** of session/stats/history. |
| `~/.local/bin/omarchy-breathe-nudge` | The optional "you have not breathed in a while" reminder. |

State lives in `~/.local/state/omarchy/breathe-{session,stats,history,config}.json`.
`breathe-config.json` is widget-owned; the CLI reads and seeds it but never
writes it ([ADR-0006](../../docs/adr/0006-cli-first-plugins.md) rule 4).

## Techniques

**Core** — Box 4-4-4-4 · 4-7-8 Relaxing · Coherent 5-5 · Physiological Sigh ·
Extended Exhale 4-8
**Energising** — Wim Hof · Bellows · Triangle · Vortex 13-8-5-3-2-1
**Clinical** — Buteyko · Alternate Nostril · Pursed Lip

Vortex is a descending Fibonacci run — each number is one full breath, split
evenly inhale/exhale, no holds — that repeats every cycle. Its 0.5s tail is the
fastest phase in the catalogue; the CLI↔Model resolver cross-check covers it.

A technique is data. Adding one means adding an entry to `techniques.json` (and
its two embedded copies — see below); no animation code is involved, because
the orb envelope falls out of the phase list.

Wim Hof and Bellows carry a `warning`, shown before the first cycle and in the
picker. Buteyko and Bellows carry an `amplitude` below 1 so they visibly swell
less — Buteyko's whole premise is breathing *less* than feels natural.

## The catalogue exists three times

`techniques.json` is canonical. `Model.js` embeds it as a JS literal (QML's JS
import cannot read a file) and `omarchy-breathe` embeds it in a heredoc (so the
CLI runs standalone). `test/catalogue.test.sh` asserts all three agree after
`jq -S`, and proves the comparison can fail before trusting it. **Change
`techniques.json`, then propagate to both copies and run that test.**

## Two guides, one number

The fullscreen guide and the compact panel guide both read `orbScale` off the
single `Model.resolve(...)` the bar widget computes. Neither eases locally.
That is [ADR-0007](../../docs/adr/0007-one-easing-source-for-breath-animation.md),
and it is what stops them drifting and what makes the physiological sigh's
second sip and Wim Hof's between-round exhale land without a visible snap.

The overlay covers the screen and takes keyboard focus, so **every key it binds
is reversible**: Space pauses, Escape hides it without ending the session.
Finishing early lives on a panel button. An early version bound bare `S` to
finish and a stray keystroke ended a live session.

## Driving it

```bash
omarchy-breathe start box --cycles 8    # or: toggle | pause | resume | stop | reset
omarchy-breathe start box --loop        # restart the pattern until stopped
omarchy-breathe skip                    # during a hold, jump to the next phase
omarchy-breathe status                  # live JSON
omarchy-breathe techniques              # catalogue incl. the user's customs
omarchy-breathe stats | history
```

**Loop.** Two separate things: the panel's **Loop** toggle is the *default* new
sessions start with (widget-owned config; the CLI reads it but never writes it —
[ADR-0006](../../docs/adr/0006-cli-first-plugins.md) rule 4), and `--loop` /
`omarchy-breathe loop` / the fullscreen guide's **Loop** control / `L` in the
guide all flip the flag on the *session in flight*. When a looped pass finishes
it is credited like any completed session, then the clock rolls back to cycle 1
— no completion sound, no notification. `stop` ends a looped session normally. A
machine that was off across the end of a loop session credits one pass and
parks, rather than resuming an endless timer.

**Skip a hold** advances `elapsedMs` to the end of the current phase and banks
the jumped time in `session.skipMs`, so a shortened retention counts toward
cycle progress but not toward the seconds credited. It is a no-op outside a
breath-hold and never ends a session. In the fullscreen guide it is the Right
arrow or the **Skip hold** control (shown only during a hold); in the panel it
is a button that appears during a hold.

From the shell, a keybind, or a conductor ritual:

```bash
omarchy-shell -q alteringux.breathe toggle
omarchy-shell -q alteringux.breathe start physiological-sigh
omarchy-shell -q alteringux.breathe skip       # cut a hold short
omarchy-shell -q alteringux.breathe loop       # flip looping on the running session
omarchy-shell -q alteringux.breathe guide      # raise/hide the overlay
omarchy-shell -q alteringux.breathe panel
```

Bound to `SUPER + CTRL + ALT + B` (start/pause), `SUPER + SHIFT + ALT + B`
(panel), and `SUPER + CTRL + ALT + Q` (a quick calming sigh). Wired into the
Focus and Wind-down conductor rituals.

## Reminders

Off by default. Turn on "Remind me to breathe" in the panel, then:

```bash
omarchy-breathe-nudge sync      # install or remove the timer to match the config
omarchy-breathe-nudge check     # print the decision and why, change nothing
```

The interval decision lives in the script, keyed off the last real session, so
the timer is a dumb five-minute heartbeat and a missed tick or a suspend
resolves correctly instead of drifting.

## Tests

```bash
node plugins/alteringux.breathe/test/model.test.js       # pure logic
bash plugins/alteringux.breathe/test/cli.test.sh         # the CLI + crediting + streaks
bash plugins/alteringux.breathe/test/catalogue.test.sh   # the three copies agree
```

The CLI tests drive the real script against a temp `OMARCHY_STATE_DIR` with
`OMARCHY_BREATHE_NO_DAEMON=1 OMARCHY_BREATHE_QUIET=1`, so transitions,
crediting and streak maths run without spawning a unit or firing notifications.

## Watch out for

- **The daemon's cost.** It resolves the phase in pure bash from an array read
  once per session. Reintroducing a `jq` fork into the tick loop costs ~10× the
  CPU (measured: 22% of a core versus 2%). Vortex's 0.5s tail is the worst case
  (Bellows' one-second phases were, before it), and the tick wait floors at
  40ms, so it never busy-spins.
- **The phase cue is fire-and-forget and single-flight.** `play_file` backgrounds
  the whole thing — the `omarchy-audio-lib` mute probe (three `pactl` forks) and
  the player — so the tick never blocks on it, and prefers the thin
  PipeWire/Pulse clients over `mpv`. `run_loop` also kills the previous blip
  before starting the next, so a slow player or a short phase can't stack cues
  into a stutter or starve one out. Running the probe or `mpv` synchronously per
  boundary is what made cues double up and drop.
- **`reset` credits nothing; `stop` credits if a whole cycle ran.** That
  asymmetry is deliberate and tested. A `--loop` pass credits on every roll;
  time jumped past with `skip` is subtracted from the seconds credited but not
  from cycle progress.
- **Restarting the shell** races itself: `omarchy restart shell` can report
  "did not become ready" when the old instance has not released. `omarchy-shell`
  is the IPC *client*; `omarchy-launch-shell` is what starts one.
