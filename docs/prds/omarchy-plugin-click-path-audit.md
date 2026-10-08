# Omarchy plugin click-path audit

Date: 2026-10-08. Readiness remains **84/100 provisional**.

## Coverage contract

[Touchpoint records](evidence/05-click-paths/touchpoints.json) account for all 42
first-party product manifests through the existing catalog-completeness test.
Kit is recorded as shared infrastructure; third-party packages are excluded.
The discovery revision records the starting branch state; per-file SHA-256 values
identify the actual source inspected, including subsequent source fixes.

The broader inventory contains **1,170 QML signal-handler occurrences in 97 files**
and **42 declared host entry points**. This supersedes the earlier 574-line search,
which covered a selected set of handler/key names. Multiple handlers on one line
are separate records. The 102 hashed package QML files include five files without
handlers. These are discovery counts, not verified controls or journeys.

Every untraced package hook starts `pending`. The signal name supplies only a
candidate classification. Internal lifecycle, timer, watcher and completion hooks
must be connected to their owning action during ordered tracing. IPC methods,
notification routes, CLI entry points, inherited Kit actions and dynamic loaders
still need explicit per-package mapping; the initial syntactic inventory is not
a claim of complete user-control coverage. Empty calls/read/write/reset arrays
mean unknown, not that the action has no effects.

Package `stores` locate persistence/process/timer/IPC objects and QML methods.
Their state transitions remain pending. The shared `Kit.Store` record traces
reload, debounced save, immediate flush, adoption, missing-file initialization,
watch/poll and failure signals from current source. This is source evidence only.

`source-reviewed` means an ordered source trace exists. `native-pass` additionally
requires actual interaction evidence. `failed` retains the observed defect and
its evidence; `not-applicable` needs a reason. No pending record is a product pass.

## Per-plugin frontier

Coverage setup is ready. Package state/call traces, native principal journeys and
the display/theme/text-scale matrix remain open. Earlier native evidence in the
[production audit](omarchy-plugin-production-audit.md) retains its limited scope
and must be reconciled with these records before it closes a touchpoint.

| Product manifest | Discovered hooks + host entries | State objects/methods located | Principal journey and required return/failure check | Verdict |
| --- | ---: | ---: | --- | --- |
| `alteringux.agenda` | 3 | 16 | Synthetic due event → one reminder; refresh/restart does not duplicate it | pending |
| `alteringux.agentglass` | 39 | 28 | Open workspace/session → action completes; vanished session reports failure | pending |
| `alteringux.ask` | 12 | 15 | Submit → answer → optional speech; speech failure retains answer | pending |
| `alteringux.bottombar` | 29 | 35 | Open hosted widget → correct panel/IPC; toggle visibility and preserve ownership | pending |
| `alteringux.breathe` | 101 | 72 | Choose → start → pause/resume → exit; one daemon and no orphan cue players | pending |
| `alteringux.calendar` | 33 | 30 | Browse → edit → save → reload; AI disclosure before submission and retained result | pending |
| `alteringux.cliamp` | 37 | 40 | Play/pause and track change; missing player reports unavailable state | pending |
| `alteringux.clock` | 35 | 37 | Previous/next month → today → Help → return; navigation never selects a date | pending |
| `alteringux.conductor` | 25 | 34 | Start ritual → ordered steps → result; failed step and retry remain distinct | pending |
| `alteringux.countdown` | 46 | 39 | Add → edit → expiry → remove; invalid dates retain editor input | pending |
| `alteringux.cpumon` | 16 | 28 | Open per-core/process view; stale/missing samples retain truthful units/status | pending |
| `alteringux.cursortrail` | 4 | 4 | Enable/intensity/disable; overlay stays click-through and exits cleanly | pending |
| `alteringux.dashboard` | 20 | 20 | Open → refresh → read sections; missing timestamp never says “Up to date” | pending |
| `alteringux.deskpet` | 52 | 62 | Pet action → quiet/disable; vision and unsolicited speech respect opt-in | pending |
| `alteringux.devcast` | 14 | 30 | Select replay → play/scrub/export; build/import failure preserves selection | pending |
| `alteringux.dictionary` | 20 | 22 | Selected text/search → suggestions → detail → back; empty result retains query | pending |
| `alteringux.diskmon` | 16 | 28 | Open mount/path detail → sample; failed sampling exposes retained age/error | pending |
| `alteringux.flow` | 31 | 45 | Edit node → save → run → inspect output; failed run preserves edits | pending |
| `alteringux.glimpse` | 38 | 43 | Study → quiz → result → next; missing image and rapid actions remain recoverable | pending |
| `alteringux.grip` | 25 | 38 | Add/check in → intervention → dismiss; escalation settings and exit work | pending |
| `alteringux.memmon` | 16 | 28 | Open pressure/swap/process detail; missing sample is not zero pressure | pending |
| `alteringux.nanogpt` | 18 | 18 | Refresh usage → result; retained snapshot keeps its collector timestamp | pending |
| `alteringux.netwatch` | 20 | 30 | Open connections/detail → refresh; missing network/tool reports status | pending |
| `alteringux.newsbar` | 55 | 56 | Refresh both feeds by keyboard/mouse → result; source switch and failed fetch recover | pending |
| `alteringux.notifications` | 36 | 65 | Open history → inspect → dismiss/clear; retained content/focus match action | pending |
| `alteringux.phone` | 69 | 62 | Synthetic contact add/edit/delete and message preparation; failed helper reports failure | pending |
| `alteringux.pomodoro` | 24 | 27 | Start → pause → resume → next phase; rapid commands preserve intended phase | pending |
| `alteringux.pulse` | 16 | 30 | Open unread source → acknowledge/action → refresh; selection and failure feedback persist | pending |
| `alteringux.recall` | 57 | 57 | Lesson → answer → feedback → next → exit; failed/missing content remains dismissible | pending |
| `alteringux.reminders` | 10 | 9 | Enter → next → back → confirm/cancel; draft survives back and cancel schedules nothing | pending |
| `alteringux.reposwatch` | 9 | 20 | Scan synthetic repos → open selected repo; stale/unavailable repo remains identifiable | pending |
| `alteringux.score` | 8 | 26 | Increment/decrement → undo → reset/history; ordered rapid actions yield the expected score | pending |
| `alteringux.skilldashboard` | 20 | 21 | `remove_refresh_restore`: confirm Remove → refresh → Restore; protected paths fail safely | package source traced; native pending |
| `alteringux.sports` | 62 | 42 | Select match/section → refresh → detail; cached matches/articles keep section timestamps | pending |
| `alteringux.stocks` | 19 | 19 | Select market → refresh → inspect; retained quotes keep Yahoo Finance and fetch time | pending |
| `alteringux.stopwatch` | 23 | 44 | Start → pause/resume → cancel; persisted state returns to idle after deletion | pending |
| `alteringux.sysmon` | 15 | 27 | Open overview/detail → refresh; shared sample age and missing sensors remain clear | pending |
| `alteringux.tempmon` | 19 | 29 | Inspect sensor/threshold → alert/recovery; missing sensor is not a safe temperature | pending |
| `alteringux.timers` | 40 | 37 | Add label → start → finish/remove; invalid input and confirmation preserve intended timer | pending |
| `alteringux.ttsplayer` | 23 | 45 | Play/pause → voice change → stop; stream failure retains truthful transport state | pending |
| `alteringux.vpnrotate` | 27 | 48 | Synthetic connect/rotate/disconnect results; Wi-Fi guard, busy gate and kill-switch failure | pending |
| `alteringux.wordstep` | 30 | 72 | Selection → read → pause/resume → exit; requested paused/failed speech prevents advance | pending |

## Release blockers

- Native AT-SPI roots currently lack QML descendants; accessible declarations
  and component loading do not close this gate.
- Full ordered traces, cross-state resets, async completion/failure feedback,
  principal journeys and normal/constrained layouts remain unverified.
- Live shell geometry/recovery is blocked by the reproduced Quickshell lock
  fatal error. The dependency repair stays in its separate checkout and plan.
- Runtime recovery, update/rollback and all required acceptance evidence must
  pass before readiness can be reassessed or issue #12 closed.

See the [execution plan](../superpowers/plans/2026-10-08-omarchy-plugin-audit-and-release.md)
and [runtime repair plan](../superpowers/plans/2026-10-08-quickshell-lock-repair.md).

## Skill Dashboard findings and verification

- **CLICK-PATH-skilldashboard-001:** seven color-expression lines contained eight
  static role accesses on the non-singleton `Kit.Palette` type. The actual Qt
  expressions returned `undefined`; the panel now owns one palette instance and
  all eight resolve to colors. The portable Kit guard rejects this API misuse.
- **CLICK-PATH-skilldashboard-002:** Disable → Enable retained `disabled`.
  The CLI now writes `active` for Enable; the lifecycle regression passes.
- **CLICK-PATH-skilldashboard-003:** lexical HOME-prefix validation allowed a
  symlinked parent to move an outside fixture. Canonical confinement now covers
  removal, restore and removed-row discovery. Invalid IDs, forged backup paths,
  occupied and dangling restore destinations are rejected; backups survive.

[Recorded before/after results](evidence/05-click-paths/skilldashboard-regressions.json)
cover Qt expression bindings and disposable CLI fixtures. The two package QML
components load without failures. All 19 discovered package-local hooks have an
ordered source trace; the manifest host entry and inherited/IPC/CLI routes still
need reconciliation. Full native lifecycle interaction and rendered color review
remain open.

## Shared reader and action probe

The attached-action probe reports four true checks and one invocation. It does
not test external AT-SPI delivery. The reader's old `qmltestrunner` fixture lacked
Quickshell's embedded plugin; an offscreen window attempt then stalled. The new
runner uses installed Quickshell and a private Sway compositor. Its 340/340/640 px
owner windows at 16/32/32 px text pass eight checks each. A negative control caught
the compositor tiling the first owner at 796 px; the isolated floating-window
rule fixes the fixture and verifies the actual requested width.

[Scoped matrix](evidence/05-click-paths/native-matrix.json) and
[reader geometry results](evidence/05-click-paths/reader-layout-result.json)
record these cases. They do not close native keyboard, screenshot or AT-SPI gates.
Run the reader with
`python3 docs/prds/evidence/02-accessibility/run-reader-layout-probe.py --sway /absolute/path/to/sway`.
The runner requires Bubblewrap, Qt and Quickshell on the audit host; portable CI
continues to defer host-only native checks.
