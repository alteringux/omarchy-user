# Omarchy plugin sweep — 2026-09-08

Branch: `plugin-sweep/2026-09-08/integrated` (not merged to main, not pushed).
Forked from main ~10:52am AEST, integrated ~3:45pm AEST after a rate-limit pause (2:50-3:04pm).

---

## batch1-monitors

# Plugin sweep 2026-09-08 — batch1-monitors

Worktree: `/home/alteringux/.local/state/omarchy/plugin-sweep-20260908/batch1-monitors`
Branch: `plugin-sweep/2026-09-08/batch1-monitors` (forked from `~/.config/omarchy` main)

Scope: bug/feature/styling pass on the five sysmon-family monitor plugins
(`sysmon`, `cpumon`, `memmon`, `tempmon`, `netwatch`). No shell restarts, no
IPC against the live shell, no push/merge to origin — this worktree only.

## sysmon — commit `20ac2a2`

"sysmon: unstick sampleNow on a hung sampler, surface staleness, color-code alert state"

- **Bug:** `sampleNow()` treated a busy `sampleProc` as a silent no-op. If
  `omarchy-sysmon sample` ever hung or just overran one 2s tick, every later
  timer tick and every middle-click sample request dropped forever — the bar
  froze on whatever it last read, with no signal anything was wrong. Fixed by
  firing a detached one-off (`Quickshell.execDetached`) instead of returning,
  mirroring the pattern netwatch already used (the write to
  `sysmon-state.json` is the point, not this `Process`'s own exit).
- **Feature:** wired `Model.isStale` (already unit-tested in
  `test/model.test.js`, but never actually read by any widget) into a
  `stale` property, using the same "3 missed ticks" threshold netwatch uses
  for its own staleness label. Surfaced in a new tooltip
  (`"CPU 42% · MEM 61% · 68°C · stale"`).
- **Styling:** `WidgetButton` now gets `dimmed: root.stale`,
  `active: anyWarning || anyCritical`, and
  `activeColor: anyCritical ? Kit.Palette.negative : Kit.Palette.warning` —
  color-coded alert state instead of a flat readout.
- Also hardened `IpcHandler.status()`: it used to return `root.stat`
  directly, which is the live `Kit.Store`-held object once loaded; stamping
  `stale` onto it in place would have leaked into the store. Now copies
  fields into a fresh object first.

## cpumon — commit `20d4eac`

"cpumon: unstick sampleNow on a hung sampler, surface staleness, color-code alert state"

Same three fixes as sysmon, scoped to the CPU slice (cpumon/memmon/tempmon
share `sysmon-state.json` and `../alteringux.sysmon/Model.js`, split out from
sysmon in `b165cfd`):

- **Bug:** identical hung-`sampleProc` fix — detached one-off sample instead
  of a dropped tick.
- **Feature:** `stale` property + tooltip: `"CPU 42% · load 1.30 · 8 cores"`,
  with `· stale` appended when the sampler has gone quiet.
- **Styling:** `dimmed`/`active`/`activeColor` on `WidgetButton`, keyed off
  `warn`/`crit` (per-metric, not sysmon's combined `anyWarning`).
- Same `IpcHandler.status()` copy-before-mutate fix, scoped to
  `root.stat.cpu`.

This was mid-flight (WIP commit `1a3abdd`) when the sweep got rate-limited.
The WIP content for cpumon was already complete and matched sysmon's shipped
pattern exactly — folded it back with `git reset --soft` and committed as-is
under a proper message, no further changes needed.

## memmon — commit `04b785d`

"memmon: unstick sampleNow on a hung sampler, surface staleness, color-code alert state"

Same shape as cpumon, scoped to the memory slice:

- **Bug:** same hung-`sampleProc` fix.
- **Feature:** `stale` property + tooltip: `"MEM 6.1 / 16 GB · swap 12%"`,
  `· stale` appended when stale. Swap segment only shown when the machine
  has swap configured (`swap.totalKb > 0`).
- **Styling:** `dimmed`/`active`/`activeColor` on `WidgetButton`.
- Same `IpcHandler.status()` copy-before-mutate fix, scoped to
  `root.stat.memory`.

The WIP snapshot had only *half* finished memmon: `sampleNow()`, the `stale`
property, and the tooltip were in, but `IpcHandler.status()` was untouched
(still returning `root.stat.memory` directly, no `stale` field) and
`WidgetButton` had none of the `tooltipText`/`dimmed`/`active`/`activeColor`
wiring. Completed both to match cpumon/sysmon before committing, so the WIP
commit was folded and replaced rather than committed half-done.

Verification: `node --test plugins/alteringux.sysmon/test/model.test.js`
(the shared `Model.js` all four widgets import — untouched by this pass,
15/15 pass) plus a structural diff of cpumon vs. memmon's `BarWidget.qml`
after normalizing metric-specific names, confirming both now carry the same
shape.

## tempmon — commit `70a0ffe`

"tempmon: unstick sampleNow on a hung sampler, surface staleness, color-code alert state"

tempmon hadn't been touched yet, so all three fixes from the WIP/cpumon/memmon
pattern applied cleanly here too:

- **Bug:** same hung-`sampleProc` fix as the other three (detached one-off
  sample instead of a permanently dropped tick).
- **Feature:** `stale` property (same 3-missed-ticks threshold) + tooltip:
  `"TEMP 68°C"` or `"No sensor detected"` when `hasTemp` is false, with
  `· stale` appended when the sampler has gone quiet. `IpcHandler.status()`
  gained a `stale` field — no copy-before-mutate fix needed here since it
  already built a fresh `{ temp, level }` object literal rather than
  returning a `Kit.Store` sub-object directly.
- **Styling:** `dimmed`/`active`/`activeColor` on `WidgetButton`, same as
  cpumon/memmon.

Verification: shared `Model.js` test suite (unaffected, 15/15) plus a read
of the finished file to confirm structural parity with the other three
widgets.

## netwatch — commit `e117733`

"netwatch: fix month report off-by-one, add stale/quota tooltip + bar styling"

Different plugin shape from the sysmon family (own `Model.js`, own CLI
bridge `netwatch-cli.js`, own tests) so this got its own bug rather than
reusing the hung-sampler one — `sampleNow()` here already had the
detached-one-off fix (it's the widget the sysmon-family pattern was
borrowed from), and its `IpcHandler.status()` already returns a freshly
computed `Model.status()` object each call, so there was no copy-before-
mutate hazard to fix either.

- **Bug:** `report(state, "month", now)` is documented as MTD
  (month-to-date) but the loop ran `for (day = 1; day <= daysInMonth;
  day++)` unconditionally — through the *last calendar day of the month*
  regardless of what day it actually is. Panel.qml's mini bar chart (the
  "Month" tab) padded out with empty columns for days that hadn't happened
  yet, and the reported peak day could tie against one of those all-zero
  future days. Fixed the loop bound to `Math.min(daysInMonth, d.getDate())`.
  Added a regression test: `report(month)` on 2026-06-15 (a 30-day month)
  now returns exactly 15 points, ending at label `"15"`.
- **Feature:** netwatch was the one monitor widget with no hover tooltip —
  `Model.status()` already computes staleness and quota %, but nothing
  surfaced either beyond the `"— "` prefix on the compact bar label. Added
  a `tooltipText` mirroring the other four: interface + link state, live
  down/up rate, quota % when a cap is configured, and a stale marker.
- **Styling:** `WidgetButton` now gets `dimmed: stat.stale` and
  `active`/`activeColor` keyed off the existing `quotaWarn`/`quotaCrit`
  properties, matching the convention now applied consistently across all
  five monitor widgets instead of a flat readout.

Verification: `node --test plugins/alteringux.netwatch/test/model.test.js`
— 16/16 pass (15 previously passing plus the new month-report regression
test).

## Summary across all 5 plugins

| plugin | commit | bug | feature | styling |
|---|---|---|---|---|
| sysmon | `20ac2a2` | hung-sampler sampleNow no-op | staleness (`Model.isStale`) | dimmed/active/activeColor + IPC copy-safety |
| cpumon | `20d4eac` | same hung-sampler fix | staleness + tooltip | dimmed/active/activeColor + IPC copy-safety |
| memmon | `04b785d` | same hung-sampler fix | staleness + tooltip | dimmed/active/activeColor + IPC copy-safety |
| tempmon | `70a0ffe` | same hung-sampler fix | staleness + tooltip | dimmed/active/activeColor |
| netwatch | `e117733` | month-report off-by-one (MTD bar chart) | stale/quota tooltip | dimmed/active/activeColor |

All five widgets now share one consistent hover-tooltip + dimmed-when-stale
+ color-coded-alert convention on `WidgetButton`. Panel.qml in all five
plugins was already `Kit.PanelHead`/`Kit.MetaText` compliant (ADR-0005)
before this sweep — no panel changes were needed, only the bar widgets.

`alteringux.kit` itself was not touched; every fix reused existing
`Kit.Store`, `Kit.BugGuard.create()`, `Kit.PanelHead`, `Kit.MetaText`, and
`WidgetButton` surface (`tooltipText`/`dimmed`/`active`/`activeColor`
already existed as widget properties, just unused by four of the five
plugins).

Worktree is on branch `plugin-sweep/2026-09-08/batch1-monitors`, 5 commits
ahead of the fork point, nothing pushed, no shell restarts or IPC calls
made against the live running shell during this sweep.

---

## batch2-time

# Plugin sweep — batch2-time (2026-09-08)

Worktree: `/home/alteringux/.local/state/omarchy/plugin-sweep-20260908/batch2-time`
Branch: `plugin-sweep/2026-09-08/batch2-time` (forked from `~/.config/omarchy` main)

Scope: `stopwatch`, `countdown`, `clock`, `pomodoro`, `timers`. Never touched
anything outside this worktree; no `omarchy restart shell`, no IPC against the
live shell, no push/merge.

## Overlap risk flag

`~/.config/omarchy/.claude/worktrees/countdown-stopwatch` (branch
`feature/countdown-stopwatch`) is a sibling worktree also touching
`countdown`/`stopwatch`. Not touched by this sweep, but both branches will
need reconciling before either lands — they're editing the same two plugins
independently from the same `main` base.

## alteringux.stopwatch — commit `ec020cf`

`stopwatch: fix history-baseline race on startup, add today summary, promote elapsed readout`

- **Bug:** on a shell restart while a stopwatch was already running,
  `applyState`'s idle->active edge could snapshot `historySnapshot` before
  `historyStore`'s own first read completed. `historyStore`'s guarded
  `onExternallyChanged` handler then ignored that real first read (`root.active`
  was already true), leaving the post-session delta permanently compared
  against an empty baseline. Fixed with a `historySnapshotReady` latch that
  accepts `historyStore`'s first real read even after the edge has already
  fired.
- **Feature:** idle panel now shows "N sessions today, HH:MM total" from the
  existing history log (`Model.historyToday` / `formatTodaySummary`, wired
  into `BarWidget.todaySummary` and `Panel.qml`).
- **Styling:** the live elapsed readout in the panel is now a hero figure
  (`Style.font.heading`, accent/warning colour) instead of flat bold body
  text, matching the countdown/timers hero-number convention.
- Files: `BarWidget.qml`, `Model.js`, `Panel.qml`, `test/model.test.js`.
  Model tests added and passing.

## alteringux.countdown — commit `363a731`

`countdown: lock state/history writes, notify when due, share warning color`

Picked up from a WIP safety-snapshot commit (`cb74abb`) left by the prior
agent when a rate limit cut it off; folded back into the working tree with
`git reset --soft` and finished properly rather than kept as a WIP commit.

- **Bug:** `local-bin/omarchy-countdowns`'s `state_jq` / `record_add` / the
  `forget` verb each did an unlocked read-modify-write of `countdowns.json` /
  `countdown-history.json`. The bar widget's own `runVerb` falls back to
  `Quickshell.execDetached` when a verb is fired while another is still
  running, so two verbs back-to-back could both read the same "before" state
  and the second write would silently clobber the first. Fixed with
  `flock 9 ... 9>"$FILE.lock"` around each read-modify-write.
- **Feature:** the bar widget now fires a one-shot `notify-send` when a
  countdown rolls over to `daysRemaining === 0` ("Today"), tracked per-id in
  an in-memory `_dueNotified` map so it fires once per countdown per day.
  Checked on the existing 30s tick and once on initial state load. This was
  the part the WIP commit had scaffolded (the `_dueNotified` property and a
  comment describing the intent) but never actually wired up — the timer
  handler just updated `nowMs` and nothing read the map. Completed that.
- **Styling:** `Panel.qml`'s `soonColor` now reads `Kit.Palette.warning`
  instead of a re-hardcoded `#d29922` — the same amber `alteringux.timers`
  already centralised there. `Kit.Palette` already existed and was already
  in use, so this was a straight dedupe, not new kit surface.
- Files: `local-bin/omarchy-countdowns`, `BarWidget.qml`, `Panel.qml`.
  `test/model.test.js` (29 assertions) and `test/cli.test.sh` (29 checks)
  both pass unchanged — the flock change is invisible to them since they run
  single-threaded.

## alteringux.clock — NOT DONE, plugin not present in this worktree or on `main`

`plugins/alteringux.clock` exists in the **live** `~/.config/omarchy` checkout
but is untracked there (`git status` shows `?? plugins/alteringux.clock/`) —
it has never been committed on any branch, including `main`, which is what
this worktree was forked from. There is nothing to check out into this
worktree; copying the live untracked files in would mean pulling
uncommitted, unreviewed state from the running shell's working directory into
a clean sweep branch, which is outside "work only inside this worktree path"
in spirit even if not in a literal write sense. Flagging for a decision
instead of guessing: either commit `alteringux.clock` to `main` first (own
commit, own review) and re-run this item as a follow-up, or confirm it's
intentionally out of scope for this sweep. No files touched for this item.

## Landmine: cli.test.sh defaults to the LIVE installed script, not the worktree copy

Every plugin's `test/cli.test.sh` resolves its CLI as
`${OMARCHY_<PLUGIN>_BIN:-$HOME/.local/bin/omarchy-<plugin>}` — i.e. **without
an explicit env override, it tests the real installed `~/.local/bin/`
script, not the copy in this worktree's `local-bin/`.** Running
`bash test/cli.test.sh` straight after editing `local-bin/omarchy-countdowns`
or `local-bin/omarchy-pomodoro` in this worktree gives a green result that
proves nothing about the edit — it silently re-tests the unmodified live
binary. Caught this after the fact for `countdown` (re-ran with
`OMARCHY_COUNTDOWNS_BIN=<worktree>/local-bin/omarchy-countdowns bash
test/cli.test.sh`, still 29/29 green against the actual edited script, so
that commit stands) and built it into the `pomodoro` run from the start
(`OMARCHY_POMODORO_BIN=...`, 44/44 green). Any future sweep work against a
`local-bin/*` script in a worktree needs the matching `OMARCHY_<X>_BIN`
override — otherwise "tests pass" is a false signal.

## alteringux.pomodoro — commit `b84d615`

`pomodoro: fix resume-while-running epoch bug, expose today/streak, hint-line styling`

- **Bug:** `omarchy-pomodoro`'s `cmd_resume` unconditionally re-stamped
  `savedAtMs` to now while leaving `remainingMs` anchored to the OLD
  `savedAtMs` when called on a session that was already running. `resume` is
  a documented standalone verb (an explicit form of `toggle`), reachable
  outside the widget — e.g. a keybinding or a conductor ritual step calling
  it defensively without checking state first. Every such call silently
  gifted the phase however many ms had elapsed since the old anchor: a
  pause/resume epoch-math bug in the same family as the task brief called
  out. Fixed with the same running-guard `cmd_pause` already uses in the
  opposite direction (no-op instead of re-stamping); added a `cli.test.sh`
  regression that sleeps 1.1s and asserts `resume` on a running session
  changes neither `remainingMs` nor `savedAtMs`.
- **Feature:** `BarWidget` now derives `completedToday` / `streak` /
  `todayBucket` from the same stats bucket the panel's STATISTICS section
  already reads, and exposes `completedToday` / `streak` on the widget's IPC
  `status()` — a keybinding or another plugin querying
  `alteringux.pomodoro`'s status IPC no longer needs to shell out to the CLI
  separately for numbers the panel already shows. `Panel.qml` now reuses
  `hostWidget.todayBucket` instead of recomputing the same lookup.
- **Styling:** the panel's keybinding-hint footer line
  ("Enter: start/pause · X: skip · R: reset · Esc: close") was
  `Style.font.bodySmall` + `Qt.darker(fg, 1.4)`. Per `docs/adr/0005`'s text
  hierarchy, a full-sentence hint/tertiary line is `Style.font.caption` +
  `Kit.Palette.faint`, not the meta-tag treatment. Fixed to match the ramp.
  (The panel already used `Kit.PanelHead` correctly elsewhere, so this was
  the one hierarchy violation left in it.)
- Files: `local-bin/omarchy-pomodoro`, `BarWidget.qml`, `Panel.qml`,
  `test/cli.test.sh`. `test/model.test.js` (unaffected, pure-JS) and
  `test/cli.test.sh` (44 checks, run against the worktree binary via
  `OMARCHY_POMODORO_BIN`) both pass.

## alteringux.timers — commit `33df9f3`

`timers: lock state/history writes, badge shows paused vs running, hint-line styling`

- **Bug:** `local-bin/omarchy-timers`'s `state_jq` / `record_completion` / the
  `forget` verb each did an unlocked read-modify-write of `timers.json` /
  `timers-history.json` — the same race class already fixed in
  `omarchy-countdowns` earlier this sweep, and reachable the same way (the
  bar widget's `runVerb` falls back to `Quickshell.execDetached` when a verb
  fires while another is still running). Fixed with `flock 9 ...
  9>"$FILE.lock"` around each read-modify-write, mirroring countdown's fix
  exactly.
- **Feature:** `Model.formatBadge` now distinguishes "some running, some
  paused" from "all running" — the bar badge shows e.g. "⏳ 2/3" instead of
  a bare "⏳ 3" when only 2 of 3 timers are actually ticking. Previously only
  the "every timer paused" case got a visual cue (parenthesised count); a
  genuinely mixed state was invisible without opening the panel. Added unit
  coverage for both the previously-untested all-paused case and the new
  mixed case.
- **Styling:** a card's "usually ~Nm" baseline hint line was hand-rolled
  (`opacity: 0.5` on `barForeground`) instead of the shared hint/tertiary
  treatment (`docs/adr/0005`: `Kit.Palette.faint`) — which this same file's
  own keybinding-hint footer already uses two sections down. Fixed to match;
  the running-long state keeps its full-opacity warning tint since that's a
  state colour, not the neutral hint role.
- Files: `local-bin/omarchy-timers`, `Model.js`, `Panel.qml`,
  `test/model.test.js`. `test/model.test.js` (all cases including the new
  formatBadge ones) and `test/cli.test.sh` (29 checks, run against the
  worktree binary via `OMARCHY_TIMERS_BIN`) both pass. This plugin's
  `Panel.qml` was already `Kit.PanelHead` / `Kit.Palette` / `Kit.EmptyState`
  / `Kit.InlineEdit` / `Kit.PanelScroll` compliant going in — the one hint
  line above was the sole hierarchy gap left.

## alteringux.clock

See the flagged item above (between countdown and pomodoro) — not done, plugin doesn't exist in this worktree or on `main`.

---

## batch3-personal

# Plugin sweep — 2026-09-08, batch3-personal

Worktree: `/home/alteringux/.local/state/omarchy/plugin-sweep-20260908/batch3-personal`
Branch: `plugin-sweep/2026-09-08/batch3-personal` (forked from `~/.config/omarchy` main)

Scope: `calendar`, `agenda`, `reminders`, `dictionary`, `recall`. For each: one real
bug fix, one small fitting feature, one styling/readability pass toward the
alteringux.kit conventions (PanelHead/MetaText, Store, BugGuard.create()).
No `omarchy restart shell`, no IPC against the live shell, nothing pushed.

## calendar — commit `9e871c0`

**Bug:** `loadMonth()` updated `currentMonth` (and thus the title) immediately
on nav, but if `monthProc` was already busy (e.g. the initial
`Component.onCompleted` load racing a quick nav click) the grid fetch for the
new month was silently dropped — the title showed the new month while
`monthCells` stayed on the old one. Fixed by having `monthProc`'s
`onStreamFinished` compare `currentMonth` against the month it just fetched
and re-fetch if a nav click moved on in the meantime.

**Feature:** a "Today" label next to the month-nav arrows jumps back to the
current month and selects today in one click.

**Style:** the day-marker legend now uses small `Kit.Palette`-colored dots
matching the actual day-cell markers instead of fixed-hue emoji, so it reads
correctly in both themes and visually matches what it explains.

Files: `plugins/alteringux.calendar/BarWidget.qml`,
`plugins/alteringux.calendar/Panel.qml`.

## agenda — commit `601cb85`

**Bug:** `ingest()` always persisted `decision.keys` (which already includes
the new notified key) whenever `shouldNotify()` decided to fire — even when
`sendNotification()` actually dropped the alert because `notifyProc` was
still busy from a previous poll. That silently and permanently suppressed
the notification for that event, since `shouldNotify()`'s dedupe would never
retry inside the remaining lead window. `sendNotification()` now reports
whether it actually dispatched, and `ingest()` only persists the new key
when it did.

**Feature:** an `upcoming` IPC verb alongside the existing `next`/`today`,
returning the full not-yet-ended list `Model.computeAgenda` already builds —
for a widget/CLI that wants more than just the single soonest event.

**Style:** `notify-send` now sends `-u critical` for an event inside 2
minutes instead of always `normal`, matching the urgent/critical visual
language the other `alteringux.*` plugins use for "about to happen".

Files: `plugins/alteringux.agenda/Service.qml`.

## dictionary — commit `846aba6`

**Bug:** `resetOverview()` reset every overview field (`overviewWord`,
`overviewSummary`, `overviewRaw`, `overviewLoading`, `overviewData`) except
`overviewStarred`. Selecting a new word left the *previous* word's star
state showing in the header until the fire-and-forget
`trackProcess("lookup")` round trip landed and corrected it (it looks up the
real starred flag for the new word from `omarchy-dictionary-track`'s state
file) — classic stale-state bug: a starred word made whatever you looked up
right after it flash as starred too. `resetOverview()` now clears
`overviewStarred` eagerly with everything else.

**Feature:** Enter in the search step previously did nothing unless a
suggestion row was already highlighted via arrow keys/hover, which stranded
a typed word with no fuzzy matches (or one typed faster than the 120ms
debounce + `omarchy-dictionary-suggest-summaries` round trip). Enter with no
row highlighted now calls `selectWord()` on the typed text directly.

**Style:** the ad-hoc centered "No matches for…" `Text` is now
`Kit.EmptyState` (the shared "nothing here yet" styling already used by
`timers`/`score`/etc.), with a `hint` line pointing at the new
Enter-to-look-up-anyway fallback. `dictionary` stays exempt from
`Kit.PanelHead` per the kit README (it's a launcher-style search surface,
not a status panel) — `Kit.EmptyState` was the fitting kit component here,
not `PanelHead`/`MetaText`.

Files: `plugins/alteringux.dictionary/Dictionary.qml`.

No test suite exists for `dictionary` (no pure-logic `.js` module, nothing to
run).

## reminders — commit `3dfb5c7`

**Bug:** `open()` only ever assigned `root.fontFamily` when the payload
carried a `fontFamily` field, so a font passed on one `open()` call stuck
around on every subsequent open — including opens with no payload at all, or
after a theme switch moved `Style.font.menuFamily` on. Stale state carried
across invocations. `open()` now starts each time from the live default and
overrides it only when the payload actually says to
(`payload.fontFamily || Style.font.menuFamily`).

**Feature:** Escape at the "message" step (once the field was already empty)
used to dismiss the entire flow, forcing a full restart just to fix a
mistyped minutes value. Added `backToMinutes()`: Escape now steps back to
the minutes prompt with the previous value restored into the field, and
only dismisses from the minutes step itself.

**Style:** `reminders` was the one `alteringux.*` plugin with no
`Kit.BugGuard` at all (every other plugin in the catalogue has one).
Imported the kit, added `guard: Kit.BugGuard.create("alteringux.reminders",
...)`, and wrapped `open()`/`submit()` bodies in `guard.run()`, matching the
shared catch-and-report convention instead of leaving these two entry
points unguarded.

Tests: `node --test plugins/alteringux.reminders/test/model.test.js` — 1/1
pass (no logic in `ReminderFlowModel.js` changed, all three fixes are in the
QML).

## recall — commit `dd389c6`

Landmine respected: `decide()` (the daemon's scheduling contract, driven by
`omarchy-recall`'s systemd --user timers) was left untouched. `Model.js` is
the pure logic shared with the bash daemon's own copy; the fix here is
isolated to `formatDue()`, a display-only helper not consumed by `decide()`
at all. Verified with both test suites before committing: the Node
`model.test.js` suite (44/44, incl. 2 new regression tests) and the
black-box `test/cli.test.sh` against the real installed `~/.local/bin/omarchy-recall`
(38/38, run against a `mktemp` state dir via `OMARCHY_STATE_DIR`, daemon
stubbed via `OMARCHY_RECALL_NO_DAEMON=1` — never touches real user state).

**Bug:** `formatDue()` picked its minutes/hours/days bucket from the raw ms
delta and only rounded for display afterwards, so a delta a few ms under an
hour (or a day) still landed in the minutes (or hours) bucket but rounded up
to that bucket's own ceiling: `"60m overdue"` / `"24h overdue"` / `"in 60m"`
/ `"in 24h"` instead of `"1h overdue"` / `"1d overdue"` / `"in 1h"` / `"in
1d"`. This is the off-by-one landmine category, in the display helper both
the bar widget's pause countdown and (now) the panel's due list read from.
Fixed by rounding first and bucketing the rounded value.

**Feature:** each row in the panel's DUE list now shows how overdue/soon it
is (via the just-fixed `formatDue()`), not just its front text and category.

**Style:** the new due-time tag is a `Kit.MetaText` (the dim tracked-caption
"status tag" treatment) rather than another hand-rolled dim `Text`, matching
`Panel.qml`'s existing `Kit.PanelHead`/`Kit.EmptyState` use. `recall` was
already the most kit-idiomatic of the five plugins swept (`Kit.PanelHead`,
`Kit.EmptyState`, `Kit.PanelScroll`, `Kit.Palette`, `Kit.AttentionDot`,
`Kit.Store` watch mode, `Kit.BugGuard` were all already in place going in).

Files: `plugins/alteringux.recall/Model.js`, `plugins/alteringux.recall/Panel.qml`,
`plugins/alteringux.recall/test/model.test.js`.

---

## Summary

All five plugins in scope are done, each in its own commit on
`plugin-sweep/2026-09-08/batch3-personal`:

| Plugin | Commit | Bug | Feature | Style |
|---|---|---|---|---|
| calendar | `9e871c0` | month-grid/title desync on rapid nav | "Today" jump | palette-matched legend dots |
| agenda | `601cb85` | dropped notification marked delivered anyway | `upcoming` IPC verb | urgency-tier `notify-send` |
| dictionary | `846aba6` | stale star icon on word switch | Enter-to-look-up-anyway fallback | `Kit.EmptyState` for "No matches" |
| reminders | `3dfb5c7` | stale fontFamily override across opens | Escape steps back a stage | added missing `Kit.BugGuard` |
| recall | `dd389c6` | formatDue hour/day rounding off-by-one | due-time badge on DUE rows | `Kit.MetaText` status tag |

Working tree is clean after each commit. Nothing was pushed, merged, or run
against the live shell (no `omarchy restart shell`, no IPC calls against the
running shell); the only IPC-adjacent thing done was the recall CLI's own
black-box test suite, which drives the real `~/.local/bin/omarchy-recall`
against a temp state dir with its daemon stubbed, not the live shell.

---

## batch4-media

# Batch 4 (media) sweep notes — 2026-09-08

Branch `plugin-sweep/2026-09-08/batch4-media`, worktree forked from
`~/.config/omarchy` main. Four plugins, four commits, all clean (no WIP left
on HEAD).

## alteringux.cliamp — `ed6bd5d`

`cliamp: stop arming the visstream cooldown on ordinary stop/pause, add
scroll-to-nudge-volume, use Kit.MetaText for Visualiser label`

- **Paused-visualizer bug.** `onExited` on the visstream process
  unconditionally set `root.visCooldown = true` on every exit, including an
  ordinary stop/pause immediately followed by resume — freezing the spectrum
  on idle bands for up to 1.5s even though cliamp was already back to
  playing. Now only arms the cooldown when `root.playing` is still true,
  i.e. a genuine crash while playback was expected to continue.
- Added scroll-to-nudge-volume on the bar strip (`onWheel`, ±2 dB), mirroring
  the panel's own +/-2dB buttons; guarded to no-op when not `running`.
- Replaced the hand-rolled "Visualiser" `Text` (manual color/opacity/font)
  with `Kit.MetaText`, matching the caption convention used elsewhere.

## alteringux.ttsplayer — `bc9f1f9`

`ttsplayer: fix Loop/restart double-fire race, add middle/right-click
mute+stop, dim elapsed line to hint role`

- **Double-fire race.** `restartFromTop()` (Restart-now button / instant
  voice change) stops playback then fires `restartTimer` to call `replay()`.
  But the same `stop` also cleared `current.json`, which `applyState()`'s
  null branch read as "playback ended" and independently restarted
  `loopTimer` to call `replay()` again when Loop was on — two overlapping
  `piper-tts` processes on the shared queue. Fixed with a
  `root._explicitRestart` flag: set true when `restartFromTop()` begins, set
  false only once `restartTimer` actually fires `replay()`; the loop-restart
  branch in `applyState()` now checks `!root._explicitRestart` before
  restarting on its own.
- Middle/right-click on the bar icon now mute / stop directly, without
  opening the panel — same shortcut shape as cliamp and score.
- The elapsed/position line in the panel is now `Kit.Palette.faint` +
  `Style.font.caption` instead of full `barForeground` at `bodySmall` — moved
  from primary-status to hint-role text per ADR-0005, since the PanelHead
  meta line above it already carries the primary status.
- Playback still routes only through `~/Work/bin/tts-player-ctl` and
  piper-tts's `current.json` watch — no second playback path added.

## alteringux.newsbar — `8ac2664`

`newsbar: guard runRefresh/setHidden through BugGuard, add middle-click
refresh, fix category-chip spacing`

- `runRefresh()` and `setHidden()` were the only two mutating entry points on
  this plugin still running bare (every other alteringux.* plugin's
  equivalents go through `guard.run(...)`); a throw inside either — including
  from the unguarded IPC `refresh()` handler — would previously escape
  uncaught instead of being caught and reported through the shared
  bug-report pipeline. Both now wrap their bodies in `guard.run("runRefresh",
  ...)` / `guard.run("setHidden", ...)`.
- Added a `TapHandler { acceptedButtons: Qt.MiddleButton }` over the bar row
  that calls `runRefresh()` directly — the per-headline `MarqueeSegment` tap
  handlers only accept the left button, so this needed its own handler
  rather than changing theirs. Mirrors cliamp/score's middle-click bar
  shortcuts.
- Category-chip `rightPadding` was `Style.space(1)` — nearly touching the
  headline that follows it, out of step with the source label's
  `Style.space(3)` and the bullet's `Style.space(4)` in the same row. Bumped
  to `Style.space(4)` to match the row's rhythm.

## alteringux.score — `f5cf4fe`

`score: add same-day history tally, fix history row timestamp overflow`

This finishes the WIP commit (`07df327`) that was folded back into the
working tree with `git reset --soft HEAD~1` and completed here; the WIP
commit no longer exists on this branch.

- Added `Model.countToday(history, nowMs)` — counts history entries
  timestamped on the same local calendar day as `nowMs` (defaults to
  `Date.now()`), skipping entries with a missing or unparsable timestamp
  rather than counting or throwing on them. Exposed as a same-day tally
  ("N today") next to the History caption, visible only when non-zero.
  Method name deliberately avoids the `top`/`rank`/`score` landmine that
  silently fails to register on Kit components.
- The History caption row is now a `Row` holding `Kit.MetaText` (sized to
  `implicitWidth` rather than `MetaText`'s own `parent.width` default, since
  it now shares the row with the tally `Text`) plus the new tally.
- **Timestamp-overflow bug fix.** Each history entry was a plain `Row` whose
  trailing spacer was `Item { width: parent.width - x }` — that already
  filled all the way to the row's own right edge, and the timestamp `Text`
  was appended *after* it, pushing the timestamp past the visible row and
  off the panel entirely. Converted the entry to a `RowLayout` (action badge
  gets `Layout.preferredWidth`, spacer gets `Layout.fillWidth: true`) — the
  same trailing-content-pin pattern already used in dashboard/stocks/flow.
- Added `test/model.test.js` coverage for `countToday`: same-day match
  against a fixed `nowMs`, entries from a different day excluded, missing/
  unparsable timestamps skipped, empty/null/undefined history returns 0,
  and the `nowMs`-omitted (defaults-to-now) path. All 18 tests in the file
  pass (`node test/model.test.js`).
- `test/cli.test.sh` (black-box tests for `~/.local/bin/omarchy-score`) was
  not run — this change touched only `Model.js`/`Panel.qml`/the JS test
  file, nothing in the external CLI it exercises.

## Batch status

All four plugins (cliamp, ttsplayer, newsbar, score) are committed cleanly
on this branch, each behind its own commit. No IPC or IPC-adjacent test was
run against the live shell; no push, merge, or `omarchy restart shell` was
performed. Nothing outside this worktree was touched.

---

## batch5-automation

# Plugin sweep 2026-09-08 — batch5-automation

Worktree: `/home/alteringux/.local/state/omarchy/plugin-sweep-20260908/batch5-automation`
Branch: `plugin-sweep/2026-09-08/batch5-automation` (forked from `~/.config/omarchy` main)

Scope: `conductor`, `flow`, `grip`, `vpnrotate`, `devcast`, `glimpse`. One real bug, one small
feature, one styling improvement per plugin. Each committed separately, no push, no live-shell
IPC, no `omarchy restart shell`.

**Test-harness note:** `grip/test/cli.test.sh` and `vpnrotate/test/reconcile.test.sh` default to
the LIVE installed `~/.local/bin/omarchy-grip` / `protonvpn-rotate`, not this worktree's
`local-bin/` copy — those two differ (the worktree's copies have already dropped the
`omarchy-pulse` cross-plugin attention integration that's still live). Grip's first run used
`OMARCHY_GRIP_DIR` to point the JS engine at the worktree, but not `OMARCHY_GRIP_BIN`; vpnrotate's
first run used neither override. Confirmed no live state was actually touched (`OMARCHY_STATE_DIR`
is exported by grip's own test and is honored by `omarchy-pulse` too; vpnrotate's do_refresh test
scenarios never hit the code path that raises a real attention item — verified
`~/.local/state/omarchy/alteringux-attention.json` still reads `{"items":{}}` and the pulse-state
file's mtime predates this session). Both suites were then re-run pointed at the worktree's own
binaries (`OMARCHY_GRIP_BIN` / `PROTONVPN_ROTATE_BIN`) and are still 36/36 and 6/6 — the fixes
below don't touch pulse code either way, so this was a verification-hygiene correction, not a code
change. `conductor/test/cli.test.sh` was checked too: its worktree and live `omarchy-conductor`
binaries are byte-identical, so no discrepancy was possible there.

## conductor — `4105e29`

Bug: the session-label `TextField`'s `onAccepted` launched `rituals[0]` on Enter whenever no
ritual was active, regardless of which ritual the label was meant for — silently wrong once 2+
rituals exist. Gated to the single-ritual case, its only unambiguous meaning.

Feature: a live "Running Xm" readout under the in-flight progress line, reusing the existing
`Model.fmtMs(state.startedAt)`. No new persistence or CLI surface.

Style: the ritual card's description now uses `Kit.Palette.faint` (the hint role) instead of a
hand-darkened foreground, per ADR-0005 (panel text hierarchy).

Files: `plugins/alteringux.conductor/Panel.qml`.

## flow — `32bd4c7`

Bug: every canvas edit (move/rename/add/remove/toggleEdge) reassigns `doc` to a fresh clone, so
the node `Repeater` destroys and recreates every delegate with no stable per-node identity. A
delegate destroyed mid-edit skips its `Kit.InlineEdit` commit()/cancel(), so the shared
`inlineEditors` counter's decrement never fires — it sticks above 0 and
`PanelKeyCatcher.blocked` stays true forever, permanently swallowing Esc. Fixed by resetting the
counter on `nodesChanged`, the one point every live editor is guaranteed to be about to die.
Also corrected the editor-strip hint text (said "double-click to rename"; `Kit.InlineEdit`
actually fires on a single click).

Feature: `Model.parseRunState` already carried `finishedAt` but nothing showed it. Added a faint
"last run: <finishedAt>" line next to the existing error line.

Style: promoted the panel header to `Kit.PanelHead` per ADR-0005's own deferred note for this
plugin, prepended above the existing toolbar row (kept as `PanelSectionHeader` since
`PanelHero`'s single `trailingControl` can't hold four buttons).

Tests: `test/model.test.js` run and passing before commit.

Files: `plugins/alteringux.flow/Panel.qml`.

## grip — `4bb69bf`

Inherited a WIP safety-snapshot commit (`02e9b4d`) from the session that got cut off by a rate
limit; folded it back into the working tree (`git reset --soft`), verified it was on the right
track, added a regression test, and committed clean.

Bug: `Model.addTask()` fell back to `String(opts.id)` even when `opts.id` was `undefined`, so
every task added from the panel's quick-add box (which calls `addTask` with no id) collided on
the literal id `"undefined"` — `completeTask`/`dropTask` would then match every un-ided task at
once instead of the one intended. Now generates a unique `task-<now>-<index>` id when none is
supplied.

Feature: a hover-revealed drop (✕) button per row in the open-tasks list, wired to the
`dropTask` verb that `BarWidget.qml` / `grip-cli.js` / `Model.js` already exposed end-to-end —
previously the only way to clear an unwanted task was to tick it off as done. UI-only; does not
touch grip's default-off posture (still ships disabled, no new auto-triggered surface).

Style: replaced five hand-rolled `Qt.rgba(root.barForeground, a)` calls in `Panel.qml` with
Kit's `Util.alpha(color, a)` helper, matching the convention already used by
cpumon/conductor/flow/stocks/sysmon/etc. `Prompt.qml`'s own `Qt.rgba` calls were left alone
(out of scope — one styling improvement per plugin).

Tests: added a regression test in `test/model.test.js` asserting two `addTask` calls with no id
produce distinct ids. Ran both `test/model.test.js` (39/39 pass) and `test/cli.test.sh` against
this worktree's copy via `OMARCHY_GRIP_DIR=$(pwd)` (36/36 pass, against a `mktemp -d` state dir —
never touched live `~/.local/state/omarchy/grip-*.json`).

Files: `plugins/alteringux.grip/Model.js`, `plugins/alteringux.grip/Panel.qml`,
`plugins/alteringux.grip/test/model.test.js`.

## vpnrotate — `8bf0ca0`

Bug: `setKillSwitch()` wrote the `killSwitch` config flag immediately and fired the underlying
`protonvpn-cli` call via `Quickshell.execDetached()` — fire-and-forget, no exit code. The script
itself detects a failed kill-switch call (older CLI, missing permission) and returns non-zero,
but that was thrown away: the toggle would show "on" with its "no leak" reassurance while the
tunnel was actually unprotected. Now runs it as a tracked `Process` and only persists the config
flip once the script exits 0.

Feature: a kill-switch-error line under the toggle (`Kit.Palette.negative`) so a failed apply is
visible in the panel instead of only in `vpnrotate.log`; also exposed on the IPC `status()`
payload as `killSwitchError`.

Also fixed `Panel.qml`'s hand-rolled `prettyInterval()`: it built labels via
`formatCountdown(sec).replace(" 00s", "m")`, but `formatCountdown` already zero-pads an
exact-minute value ("2m 00s"), so the replace left a stray "m" behind ("2mm", "3mm"). Moved it
into `Model.js` as a tested pure function. Only reachable today via a hand-edited
`vpnrotate-config.json` (the panel's five preset buttons don't hit a non-preset value), but a
real, reproducible bug.

Style: swapped `Qt.rgba(...)` / `Qt.darker(fg, 1.4)` hint-text colors in `Panel.qml` for
`Util.alpha` / `Kit.Palette.faint`, matching the file's own status-detail block and the wider
kit convention.

Tests: `test/model.test.js` (19/19) and `test/reconcile.test.sh` (6/6, unaffected —
`local-bin/protonvpn-rotate` untouched) both run and passing before commit.

Files: `plugins/alteringux.vpnrotate/BarWidget.qml`, `plugins/alteringux.vpnrotate/Model.js`,
`plugins/alteringux.vpnrotate/Panel.qml`, `plugins/alteringux.vpnrotate/test/model.test.js`.

## devcast — `783d9df`

Bug: `buildProc`/`catalogProc`/`importProc` all used a bare `onExited: { ... }` handler — no
exit-code parameter, no captured stderr. A failed build (no active session, a stale
`sourcePath`), a failed catalog scan (unreadable projects dir), or a failed import reset the
busy flag and reloaded the same index with zero trace anywhere that anything went wrong — an
unhandled process error on all three of this plugin's background actions.

Fix: each `Process` now has a `stderr: StdioCollector` (the same pattern
`alteringux.conductor` already uses for its stdout) and a real `onExited(code)` that populates a
new `lastError` string from the last non-blank stderr line (or a generic "exit N") on failure,
clearing it on success; a fresh attempt also clears it immediately. Exposed on IPC `status()`.

Feature: a red (`Kit.Palette.negative`) error line in the panel under the build button, shown
only when `lastError` is non-empty — the minimal thing that makes the fix above visible to
someone looking at the panel rather than only at IPC status.

Style: the four remaining `Qt.darker(root.barForeground, 1.4/1.5)` hint-text colors in
`Panel.qml` become `Kit.Palette.faint`, matching the status-detail text already correct a few
lines above in the same file.

Scope note: `omarchy-devcast-catalog.timer` runs live against the real
`~/.local/state/omarchy/devcast-catalog.json` every 30 minutes. Nothing in this change touches
`local-bin/omarchy-devcast` or reads/writes that file directly — the fix only changes how the
widget reports the exit of its own subprocess, so no interaction with the live timer.

Tests: `test/model.test.js` (12/12) re-run as a baseline check; unaffected since `Model.js` was
not touched.

Files: `plugins/alteringux.devcast/BarWidget.qml`, `plugins/alteringux.devcast/Panel.qml`.

## glimpse — `d115d39`

Bug: `runVerb()` fell back to `Quickshell.execDetached()` whenever a verb was fired while
`actionProc` was already running — a second, untracked `omarchy-glimpse` process racing the
first one's read-modify-write of `glimpse-state.json`, and one whose completion never reloaded
the widget's stores (its effect could sit unreflected until the next poll, up to 8s for config).
The easy way to hit it: double-click a grade button on the review screen, firing two concurrent
`finish` calls that score the same round against the SM-2 schedule. Replaced the `execDetached`
fallback with a one-slot pending-verb queue (last call wins) that always runs serialized through
`actionProc`, so every verb's completion reloads state/cards/config and no two
`omarchy-glimpse` processes ever touch the state file at once.

Feature: exposed the in-flight state as `hostWidget.busy` (also on IPC `status()`) and disabled
`Overlay.qml`'s grade buttons and intro Start/Not-now/Snooze buttons while busy, plus a matching
guard inside `gradeRound()` itself — the double-click that used to race the CLI now just does
nothing on the second click instead of double-grading.

Style: the four remaining `Qt.rgba(color.r, color.g, color.b, a)` calls across `Panel.qml` and
`Overlay.qml` become `Util.alpha(color, a)`, matching the kit convention (a fully-opaque
`Qt.rgba(0.5,0.5,0.5,1)` blank-screen filler and the black modal scrim, neither derived from a
theme color, were left alone).

Tests: `test/model.test.js` (16/16) re-run as a baseline check; unaffected since `Model.js` was
not touched. This plugin has no `cli.test.sh` — and no worktree copy of `omarchy-glimpse` under
`local-bin/` exists yet to cross-check against the live installed one (see the test-harness note
above for why that matters); the live `~/.local/bin/omarchy-glimpse` was never invoked this
session.

Files: `plugins/alteringux.glimpse/BarWidget.qml`, `plugins/alteringux.glimpse/Overlay.qml`,
`plugins/alteringux.glimpse/Panel.qml`.

---

## batch6-misc

# Plugin sweep 2026-09-08 — batch6-misc

Worktree: `/home/alteringux/.local/state/omarchy/plugin-sweep-20260908/batch6-misc`
Branch: `plugin-sweep/2026-09-08/batch6-misc` (forked from `~/.config/omarchy` main)

Scope per plugin: one real bug fix, one small fitting feature, one styling/readability
improvement (alteringux.kit conventions where applicable), tests run before commit,
one commit per plugin.

## bottombar (2faa5ca)

**Bug:** a hidden-flag recheck request that landed while `hiddenProbe` was already
running was dropped silently (setting `running = true` on an already-running
`Process` is a no-op) — `hidden` stayed stale until the next 3s poll tick. Fixed by
tracking the request as a `hiddenProbeDirty` flag and re-firing the probe from
`onExited` if one came in mid-flight.

**Feature:** added an IPC `reload()` verb that forces an immediate hidden-flag
recheck instead of waiting up to 3s for the next poll — useful right after a script
flips `bar-off`/`bottombar-off` and wants the change to show without delay.

**Styling:** a failed hosted widget used to collapse to an invisible 1px sliver,
indistinguishable from "not configured" and only discoverable via `status()`. Now
shows a small bordered `!` marker (`Kit.Palette.negative`) with a tooltip naming
the widget that failed.

## dashboard (65b472b)

**Bug:** `Kit.Store`'s `FileView` watch goes dead after the first external write —
every `bin/` writer (refresh/note/track) replaces the file via mktemp+mv, which
swaps the inode the watch is holding, so `onFileChanged` never fires again. Fixed
with a `pollMs: 5000` idle poll fallback, same pattern documented in Kit.Store's own
header for the watch-on-create blind spot.

**Feature:** dashboard was the one alteringux.* bar-widget plugin with zero IPC
surface — every sibling (stocks, score, conductor, ...) exposes at least
open/close/status for scripting and bottombar hosting. Added
open/close/toggle/refresh/status, mirroring stocks' shape.

**Styling:** unified five different hand-rolled dim-text treatments
(`root.barForeground` at various `opacity` values, `Qt.darker(fg, 1.4)`) onto
`Kit.Palette.faint`, per the panel-text-hierarchy convention the rest of the sweep
is converging on.

## crochet (645e421)

**Bug:** the "last run" stats line only checked `lastRun.stitches !== null` before
rendering `stitches + rows + finalRowWidth` — since `parseIndex` nulls each of the
three fields independently, a partial record (one field null, others populated)
rendered the literal string "null" inline. Now all three are checked before
showing the line.

**Feature:** added a `scan()` IPC verb that forces an on-demand pattern rescan
(previously only triggered by opening the panel), so a script can refresh the
catalogue without going through the UI.

**Styling:** unified two `Qt.darker(root.barForeground, 1.4)` hint-text spots onto
`Kit.Palette.faint`.

## deskpet (b79fae5)

**CONFLICT RISK — flagged per the task brief.** `alteringux.deskpet` has its own
separate daily `omarchy-deskpet-auto-improve.timer` running unattended against the
**live** tree, and this worktree forked from main before that timer's latest live
edits. This diff was written and tested against the worktree's (older) copy of the
plugin and **will very likely conflict with live changes at merge time** — the
human needs to reconcile by hand (rebase/re-apply onto the live file, not a blind
merge) rather than fast-forwarding.

**Bug:** the `night_owl` achievement's `check()` read the wall-clock hour off
`lastInteractionMs` directly (`new Date(s.lastInteractionMs).getHours()`), so it
silently **un-unlocked** the moment you next interacted with the pet outside
midnight-5am. Every other achievement here is monotonic in a counter or an age
(the file's own header comment promises "currently unlocked can always be
recomputed fresh from state" as an invariant) — night_owl was the one that quietly
broke it, and the existing test suite had already worked around the resulting
flakiness by pinning `lastInteractionMs` to noon rather than fixing it. Added a
persisted `nightOwlEver` boolean, set once in `withInteraction` (which every
feed/play/poke already flows through) the first time an interaction lands between
midnight and 5am; `night_owl`'s check now reads that flag, so an earned trophy
stays earned. New regression test: `night_owl: sticks once earned instead of
flipping back with the wall-clock hour`. 59/59 tests pass (`node --test
test/model.test.js`).

**Feature:** `toggleSleep()` was reachable only from the settings panel's
Sleep/Wake button — every other mutating action (feed/play/poke/mute/next/prev)
already had an IPC twin for Hyprland keybindings and scripting. Added an IPC
`sleep()` verb.

**Styling:** the panel's closing hint line ("Right-click the pet...") predated
ADR-0005 (panel text hierarchy) and used `Qt.darker(fg, 1.4)` +
`Style.font.bodySmall`. Per the ADR's ramp, an explanatory sentence is the *hint*
role: `Kit.Palette.faint` at `Style.font.caption`, regular weight — fixed to match.
(Note: `deskpet` is out of scope of ADR-0005's original pass entirely — not listed
as done, deferred, or exempt — so its `Kit.PanelHead` opener and remaining
`Style.font.bodySmall`-bold section headers, e.g. "Wardrobe"/"Movement", are still
pre-ADR and were left alone here to keep the diff small; a full ADR-0005 pass over
deskpet is a separate, larger piece of work.)

Not touched: `manifest.json`'s description still says "pick from 11 pets" though
the catalogue has 12 (`Hamster` was added later, per ROADMAP.md's Done list) —
left as-is to keep this diff minimal given the merge-conflict risk above.

## notifications (6483b3b)

**Minor overlap note:** the live tree has one uncommitted line already touching
this file (`git -C ~/.config/omarchy diff plugins/alteringux.notifications/`) —
the exact same one-line `service.` qualifier fix below. Low risk: it's an
identical change, so it should apply or auto-resolve as a no-op at merge, unlike
deskpet's conflict above.

`alteringux.notifications` is `"omarchy": {"clonedFrom": "omarchy.notifications"}`
per its manifest, and the read-only original still ships at
`/usr/share/omarchy/shell/plugins/notifications/`. Diffing this plugin against
that upstream copy is what surfaced both bugs below — worth doing for any
`clonedFrom` plugin, since it cheaply separates "genuine local bug" from
"upstream's own long-standing quirk" (the `removePopupsByOriginalId` scoping bug
below turned out to exist in upstream too — not introduced by the clone).

**Bug (x2):**
1. `handleNotification`'s `Qt.callLater` callback called `removePopupsByOriginalId`
   unqualified. A plain JS function expression handed to `Qt.callLater` doesn't
   carry the enclosing Item's function-property scope the way a QML `id`
   (`popupModel`, referenced the very next line) does, so this silently threw
   "removePopupsByOriginalId is not defined" on every notification — the dedup
   that drops a superseded popup on a `replaces_id` update never ran, leaving a
   stale duplicate toast on screen next to the new one. Qualified as
   `service.removePopupsByOriginalId`.
2. Three `Text` elements (the summary line, both glyph-fallback labels) were
   missing `textFormat: Text.PlainText`, which upstream sets deliberately — its
   own comment (also missing here) explains why: without it, `Text`'s default
   `AutoText` mode can promote a hostile-looking summary string to rich text,
   letting a sender render bold/colored/linked text, or visually spoof another
   app's toast, instead of literal text. Restored on all three, comment included.

**Feature:** `NotificationCard`'s `accentColor` (urgent red for critical,
dimmed for low) was already computed but had zero consumers anywhere in the
file — every toast looked identical regardless of urgency until you read the
text. Wired it into a thin left-edge severity stripe; Normal-urgency toasts
(the common case) stay stripe-free to avoid visual noise.

**Styling/readability:** one `console.warn` was missing the `"notifications:
"` prefix every other warning in this file carries — fixed for
attributability when grepping the shared shell process's logs. (This plugin
has no `Panel.qml` and doesn't import `alteringux.kit` — it's a `service`-kind
plugin, popups only, no bar widget or settings surface — so the
PanelHead/MetaText convention doesn't apply here; ADR-0005 itself lists
`notifications` under "Services with no panel: nothing to do.")

No test suite in this plugin (service kind, no bar widget, no `*.test.js`
anywhere in the tree).

## pulse (629cf07 import, f8612cd sweep)

**Not actually untouched before this — it didn't exist in git at all.**
`alteringux.pulse` is a real, working plugin on disk at
`~/.config/omarchy/plugins/alteringux.pulse/` (bell bar widget + activity feed
panel + `~/.local/bin/omarchy-pulse` CLI + its own `test/model.test.js`), but
`git status` on the live `~/.config/omarchy` repo shows the entire directory as
untracked — it was never committed on any branch. Since this worktree forked
from main, it simply isn't present here, so there was nothing for a sweep diff
to land on. Handled as two separate commits instead of forcing the sweep into
one: **629cf07** imports the five source files verbatim (0 changes, tests run
unmodified: 9/9 pass) so a human reconciling at merge time can take the import
on its own if the live tree gets its own commit first; **f8612cd** is the
actual bug/feature/style sweep on top. Flagging for the human: this plugin
needs a real "first commit" decision made outside this worktree regardless of
what happens with this branch.

**Bug:** the activity feed's per-event message `Text` computed its width as
`evRow.width - <label> - <timeLabel> - evOpen.width - parent.spacing * 3`.
`evOpen` (the hover-only "Open" button) is invisible outside of hover, and a
`Row` excludes an invisible child from both the layout *and* its spacing gaps
— so the flat `spacing * 3` (correct only for the 4-visible-child hovered
case) and the unconditional `evOpen.width` subtraction both overcharged the
message text by one phantom gap and one phantom button-width in the far more
common unhovered, 3-child case. Messages elided more aggressively than they
needed to. Fixed to branch on `evOpen.visible`.

**Feature:** added an IPC `next()` verb that fires the current "do this next"
pick (the loudest outstanding attention item, or the newest actionable unread
event) without opening the panel — bindable to a key once you've learned what
a given pick usually turns out to be. This also completes an invariant the
file's own header comment already promised but didn't quite deliver on
("every control calls the same hostWidget function so there's one
implementation shared with the IPC path") — the panel button's `onClicked`
had the source-branch logic (`attention` → `actOn`, else → `runAction`)
inlined rather than calling a shared function; extracted it to
`hostWidget.runNextAction()`, called by both the button and the new verb.

**Styling/readability:** the "do this next" border color called
`toneFor(level)` three times in the same expression just to destructure
`.r`/`.g`/`.b` out of the identical color for one `Qt.rgba()`. Added
`toneRgba(level, alpha)` so that's one call. (Panel.qml already used
`Kit.PanelHead`/`Kit.MetaText`/`Kit.Palette.faint` throughout — this plugin
was evidently built after ADR-0005 landed, so there was no hand-rolled
dim-text pattern left to unify here.)

`node --test test/model.test.js`: 9/9 pass, unchanged by the sweep commit
(both fixes are in the QML layer; `Model.js` wasn't touched).

## Test-harness note (applies to all six plugins above)

A sibling sweep batch flagged that some plugins' test harnesses shell out to
the *installed* `~/.local/bin/omarchy-<name>` CLI rather than the worktree's
own copy, which can silently validate the wrong code. Checked this against
every plugin in this batch: **not applicable here**. The only test files in
this whole batch are `dashboard`, `crochet`, `deskpet`, and `pulse`'s
`test/model.test.js` — each is a pure-logic test against that plugin's own
`Model.js` (`require("../Model.js")`), with no `child_process`/`execSync`/
`.local/bin` reference anywhere. `bottombar` and `notifications` have no test
files at all. One thing worth noting for whoever runs these next: `dashboard`
and `crochet`'s test files predate `node:test` and define their own
`test(name, fn)` helper with a hand-rolled `ok -`/`FAIL -` console reporter,
so `node --test <file>` reports a misleading "tests 1 / pass 1" (it just sees
one script that ran without throwing) — run them as plain `node
test/model.test.js` and check the exit code, per each file's own header
comment. `deskpet` and `pulse` use real `node:test`, where `node --test` gives
an accurate per-test count. Re-ran all four this way as part of this note;
all pass (dashboard 10/10, crochet 8/8, deskpet 59/59, pulse 9/9).

## Summary

| Plugin | Commit(s) | Bug | Feature | Style |
|---|---|---|---|---|
| bottombar | 2faa5ca | hidden-probe race drops a recheck | IPC `reload()` | failed-widget `!` marker |
| dashboard | 65b472b | dead FileView watch after external write | full IPC surface | unified `Kit.Palette.faint` |
| crochet | 645e421 | partial `lastRun` renders literal "null" | IPC `scan()` | unified `Kit.Palette.faint` |
| deskpet | b79fae5 | `night_owl` achievement un-unlocks | IPC `sleep()` | ADR-0005 hint-line fix |
| notifications | 6483b3b | dropped-scope dedup + missing PlainText hardening | urgency stripe | log-prefix consistency |
| pulse | 629cf07, f8612cd | event-row width miscalc | IPC `next()` | `toneRgba()` dedupe |

**Merge-time attention needed:**
- `deskpet` — real conflict risk. Its own daily auto-improve timer has been
  editing the live tree since this worktree forked; reconcile by hand.
- `notifications` — trivial, low-risk overlap: the live tree already carries
  the exact same one-line `service.` qualifier fix, uncommitted.
- `pulse` — needs a decision outside this worktree: the plugin was never
  committed to the live repo's git history at all. This branch's import
  commit (629cf07) is one option; there may be a better time/place for that
  first commit that isn't a bug-sweep branch.

---

## batch7-newplugins

# Batch 7 — new plugins (2026-09-08)

Worktree: `~/.local/state/omarchy/plugin-sweep-20260908/batch7-newplugins`
Branch: `plugin-sweep/2026-09-08/batch7-newplugins`
`shell.json` untouched throughout — both plugins ship inactive, per the task.

## alteringux.diskmon (commit `68ced06`)

**Gap it fills.** The `cpumon`/`memmon`/`tempmon`/`netwatch` system-monitor
family had no disk-usage widget. `df` answers fully in one shot (no delta
between samples the way CPU% needs), so it's its own CLI/state file rather
than riding on `sysmon-state.json`.

**CLI surface** (`local-bin/omarchy-diskmon`):
```
sample                 read df, write diskmon-state.json
get | status           print state (sampling first if missing)
list [--json]          every non-virtual mount and its usage
largest [PATH] [--json]  top-10 immediate subdirs of PATH by size (du)
watch [--interval S]   foreground loop
config                 print diskmon-config.json (hand-edit)
reset                  wipe state, keep config
```
Config: `watchMount` (default `/`), `warnPct` (80), `critPct` (92),
`largestPath` (`~`), `excludeFstypes`.

**Widget.** Bar glyph + watched-mount percent-full, sampled every 30s.
Panel: gauge, 10-minute trend sparkline with min/avg/max (reuses the
cpumon/memmon/tempmon family's generic `Sysmon.TrendChart`/`StatGrid`), full
mount list, largest subdirectories under `largestPath` (on-demand `du`, not
on the sampling timer). `AttentionDot` on warn/crit thresholds.

**shell.json opt-in** (`bar.layout.left` or `.right`, e.g. next to
`alteringux.netwatch`):
```jsonc
{ "id": "alteringux.diskmon" }
```

**Test results (re-run this session):** `test/cli.test.sh` 14/14 passed
(fixture `df`/`du` output, doesn't depend on actual disk state);
`test/model.test.js` 9/9 passed (tolerant parsing, formatting, sparkline
projections).

## alteringux.reposwatch (commit `bdcea51`, finished this session)

Inherited as a WIP safety-snapshot commit (`f7d39a1`) from a session cut off
by a rate limit. `git show f7d39a1 --stat` showed the CLI, `Model.js`,
`BarWidget.qml`, `Panel.qml`, `manifest.json`, `improve.json`, and both test
files already written and — once run — already passing in full. The only gap
against diskmon's bar was a missing `README.md`. Folded the WIP commit back
into the working tree (`git reset --soft HEAD~1`), added the README, and
committed clean as `bdcea51`.

**Gap it fills.** None of the existing widgets surface git working-tree
state. `reposwatch` watches an explicit list of repo paths (no filesystem
crawl — `add`/`remove` are the whole curation interface, since recursively
walking for `.git` is slow and surprising about what ends up watched) and
reports dirty counts + upstream divergence.

**CLI surface** (`local-bin/omarchy-reposwatch`):
```
scan                   git-status every configured repo, write state
get | status           print state (scanning first if missing)
list [--json]          the repos array (table or --json)
add PATH               add PATH to the watch list, then scan
remove PATH            drop PATH from the watch list, then scan
watch [--interval S]   foreground loop
config                 print reposwatch-config.json (seeded from
                       ~/.config/omarchy + ~/Work if they exist as repos)
reset                  wipe state, keep config
```
Per-repo status: `path`, `name`, `ok`/`error`, `branch`, `detached`,
`dirty.{staged,unstaged,untracked,total}` (from `git status --porcelain=v1`
column parsing), `hasUpstream`, `ahead`/`behind` (from
`git rev-list --left-right --count @{u}...HEAD`), `lastCommitTs`.

**Widget.** Bar glyph + trouble count (dirty + errored repos), `✓` when
calm. Sampled every 60s (git status is cheap but not free, and dirty state
doesn't change on a CPU-monitor cadence). Panel: totals row
(dirty/ahead/behind/errors), then one row per repo with branch, ahead/behind,
dirty breakdown, and relative last-commit age. `AttentionDot`: critical only
when a watched path is gone or isn't a git repo (config problem), warning for
anything dirty or diverged. Middle-click / panel Enter rescans immediately.

**shell.json opt-in** (`bar.layout.left` or `.right`, e.g. alongside
`alteringux.netwatch`/`alteringux.diskmon`):
```jsonc
{ "id": "alteringux.reposwatch" }
```

**Test results (this session):**
- `test/cli.test.sh`: 22/22 passed — drives the CLI against real throwaway
  git repos under a tmpdir (clean repo, staged+unstaged+untracked dirty repo,
  a real ahead/behind pair against a bare remote, a non-repo path, totals
  aggregation, `add`/`remove`/`get`/`reset`).
- `test/model.test.js`: 10/10 passed — tolerant `parseState`/`parseRepo`,
  `repoLevel`/`overallLevel` classification, `formatDirty`/`formatAheadBehind`,
  `barLabel`, `isStale`.

Both suites run clean from a fresh `chmod +x` + explicit `OMARCHY_*_BIN` /
`OMARCHY_STATE_DIR` override, so they don't depend on anything already being
installed under `~/.local/bin` or `~/.local/state/omarchy`.

## Landmines checked against

- No business logic in QML: both `BarWidget.qml`/`Panel.qml` only read a
  `Kit.Store`-parsed model and call the CLI via `Process`/`Quickshell.execDetached`;
  all counting/classification lives in each plugin's `Model.js`, unit-tested
  with plain `node --test`.
- No QML method named `top`/`rank`/`score` in either widget (reposwatch's
  method surface: `scanNow`, `open`, `close`, `togglePanel`, `injectPanel`,
  `switchPanel`, `relativeAge`, `levelColor`).
- State/flag files are single atomic writes (`mktemp` + `mv -f`) in both
  CLIs' `put_file`.
- `shell.json` never edited by this session — both plugins are proposals
  only, opted in via the snippets above.

