# Omarchy Plugin Audit and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute in this session without subagents, including review, as the user requested.

**Goal:** Complete the behavior and native design audit of all 42 first-party plugins, repair demonstrated defects, and reassess production readiness from recorded evidence.

**Architecture:** Preserve each plugin's product design and use the existing Kit for shared interaction mechanics. Trace controls through ordered state changes and helper completion before changing code. Keep the Quickshell dependency repair in the separate [runtime plan](2026-10-08-quickshell-lock-repair.md), which can be reviewed independently.

**Tech Stack:** Qt Quick/QML, Quickshell 0.3.1, Qt 6.11.2, Bash, Python 3, Node 26.7.0, Hyprland, Linux AT-SPI, existing repository test runner.

**Spec:** [Omarchy plugin product teardown, including the implementation specification](../../prds/omarchy-plugin-product-teardown.md), especially “Implementation decisions” and “Testing decisions”. Also implements the user's requested click-path and production audits.

## Global Constraints

- “Keep the existing 42 first-party manifest IDs as scope. `alteringux.kit` is shared infrastructure; `io.github.*` packages are third-party.”
- “Use one manifest-completeness check for both the README catalog and teardown rows; a first-party manifest without either row is an inventory failure.” Extend that same check for the audit record.
- “Do not infer runtime accessibility from declarations or compilation.”
- “Visible interaction and layout claims require rendered/native evidence.”
- “Keep the calendar month grid and Score's large numeric value.”
- “Do not report success before the CLI completes, and preserve the existing backup-before-remove behavior.”
- “Keep the busy indicator and both-feed refresh callback.”
- “Changing unrelated shell configuration, widget placement, domain models, services, or user worktree edits” remains out of scope.
- Use the existing candidate at `/home/alteringux/worktrees/omarchy-production-candidate`; preserve the dirty original checkout at `/home/alteringux/.config/omarchy`. Read applicable AGENTS.md before execution. Do not recreate either checkout.
- Run Graft first. Its current source index omits QML; use exhaustive `rg -a` for QML after establishing that gap. Search Hindsight before tests, fixes, and commits; verify remembered claims against current evidence.
- Use synthetic skills, calendar entries, messages, credentials, and helper responses for mutation checks. Keep local NewsBar feed scripts and ignored settings out of commits.
- A score of 100 is an outcome to substantiate, not an acceptance assertion to force. Any unmet gate remains visible in the final score and report.

## Review Focus

1. Rapid repeated activation and out-of-order completion must not discard the final intended action or show stale success — Task 3, `rapid_activation_preserves_intent`.
2. Removing a skill, refreshing, and restoring it must retain a recoverable row and preserve ownership/path guards — Task 3, `remove_refresh_restore`.
3. Empty, failed, or stale provider responses must preserve useful previous data and truthful timestamps — Task 3, `failed_refresh_preserves_provenance`.
4. Opening Help, dismissing it, and returning to an existing control must neither trigger a domain action nor lose usable focus — Task 2, `help_returns_focus_once`.
5. Constrained displays, long content, and enlarged text must retain reachable controls and scrolling in both themes — Task 4, `constrained_long_content`.

---

## Verified starting point

- Candidate commit: `8b9d85f7cdf4d46a39c45a7dd3adbed4424a3576` on `codex/omarchy-production-candidate`.
- [CI run 37724926490](https://github.com/alteringux/omarchy-user/actions/runs/37724926490): all 77 portable suites passed on that exact commit.
- Candidate QML load probe: 126 components, zero failures. Candidate inventory/host validation: four tests passed. Breathe: 131 checks passed with desktop sound files hidden.
- Clock and Score Help, plus Wordstep selection-to-reader launch/Escape, have earlier native evidence. Preserve its precise scope; it does not cover every control in those plugins.
- Current report: 84/100 provisional, rollout held. Remaining gaps include native accessibility, full click paths, the layout matrix, and a live shell lock crash.
- The installed Quickshell reproduces `Tried to show lockscreen surfaces without active lock` when an isolated probe attempts a second lock. The upstream repair is applied only in an isolated dependency checkout. Its build stopped at 4% when the generated Makefiles' temporary CMake executable disappeared; the repaired runtime is unverified.
- A QML search found 574 handler/key-hook lines across 89 first-party files. This includes internal timers and is a discovery count, not 574 verified user controls.

## File and evidence boundaries

| Path | Responsibility |
| --- | --- |
| `docs/prds/omarchy-plugin-click-path-audit.md` | Human-readable findings and per-plugin verdicts |
| `docs/prds/evidence/05-click-paths/touchpoints.json` | Complete control inventory, ordered call/state traces, and evidence references |
| `docs/prds/evidence/05-click-paths/native-matrix.json` | Actual native journey, accessibility, and display-profile results |
| `tests/omarchy-plugin-catalog.test.py` | Existing manifest completeness seam, extended to audit IDs |
| `plugins/alteringux.kit/{ActionButton,KeyboardPanel,PanelKeys,PanelHead,Store}.qml` | Shared behavior; modify only for a reproduced defect and check every consumer |
| Each exact package directory in Task 3 | Package-specific handlers, models, and existing tests |
| `docs/prds/omarchy-plugin-production-audit.md` | Final score, blockers, evidence and release decision |
| `README.md`, `tests/run-all.sh`, `.github/workflows/plugin-checks.yml` | Existing release procedure/checks; retain unless a demonstrated gap requires a change |

Paths below are relative to the candidate unless explicitly absolute. The latest audit/progress notes and several native probes currently exist only in the original checkout. Inspect and copy only the named evidence files needed for a task; do not copy the entire dirty checkout.

### Task 1: Make audit coverage explicit at the existing inventory seam

**Files:** Modify `tests/omarchy-plugin-catalog.test.py:14-66`; create `docs/prds/omarchy-plugin-click-path-audit.md` and `docs/prds/evidence/05-click-paths/touchpoints.json`.

**Interfaces:** Reuse `manifest_ids(plugin_root) -> list[str]` and `inventory_diff(catalog, manifests) -> dict`. The JSON document has `schemaVersion: 1` and `plugins: [{id, stores, touchpoints}]`; each touchpoint records `id`, `source` (`path`, `line`), `entry`, `calls` in order, `reads`, `writes`, `resets`, `expected`, `observed`, `status`, and `evidence`. Status is `pending`, `source-reviewed`, `native-pass`, `failed`, or `not-applicable`; evidence is an array of relative artifact paths. A source review cannot set `native-pass`.

- [ ] **Step 1:** Extend `test_catalog_matches_all_first_party_product_manifests` to compare `[row['id'] for row in audit['plugins']]` with the existing manifest set, using the existing `inventory_diff` assertion `{missing: [], extra: [], duplicate: []}`. Retain the count of 42 and the existing missing/extra/duplicate fixture.
- [ ] **Step 2:** Run `python3 tests/omarchy-plugin-catalog.test.py PluginCatalogTest`; expect failure because the audit record does not yet exist.
- [ ] **Step 3:** Populate exactly the 42 IDs in Task 3. Start unreviewed touchpoints as `pending`. Inventory QML handlers, keyboard shortcuts, menus, form changes/submission, bar entry points, and CLI/notification entry points advertised by each manifest. Mark internal hooks with their owning action or a reason they are not user touchpoints.
- [ ] **Step 4:** Map shared and package-owned state setters: ordered writes, cross-state resets, process completion, file reload, watcher/poll behavior and failure feedback. Cite actual file/line spans. Keep this map in each record's `stores`; do not introduce a runtime state abstraction.
- [ ] **Step 5:** Run `python3 tests/omarchy-plugin-catalog.test.py PluginCatalogTest`; expect all catalog tests to pass, with 42 unique audit IDs. Inspect unclassified hooks against the raw search inventory; inventory completeness alone does not change any behavior verdict.
- [ ] **Step 6:** Commit these three files only as `docs: track complete plugin click-path audit coverage`.

### Task 2: Verify shared activation, Help, focus, and accessibility

**Files:** Inspect the five Kit files in the boundary table and `plugins/alteringux.kit/PanelFocus.js`. Reuse original-checkout probes `docs/prds/evidence/02-accessibility/run-action-button-probe.py`, `run-reader-layout-probe.py`, `tst_reader_layout.qml`, and `docs/prds/evidence/03-recovery-help/run-recovery-pilot-native.py` with its `RecoveryPilotProbe.qml`. Record results in `native-matrix.json` and the click-path report.

**Interfaces:** Preserve `ActionButton.clicked()`, `PanelKeys.openHelp()`, `enterControls()`, `dismissRecovery()`, `KeyboardPanel.focusOwner()`, `focusInitialTarget()`, and `Store.reload()/save()/flush()`. Native records contain `plugin`, `case`, `revision`, `environment`, `input`, `expected`, `observed`, `status`, `evidence`; a non-pass includes its reason.

- [ ] **Step 1:** Run `python3 docs/prds/evidence/02-accessibility/run-action-button-probe.py` after bringing the inspected probe into the candidate. Expect four true checks and one invocation; classify this as a local attached-action check, not native AT-SPI.
- [ ] **Step 2:** Exercise `help_returns_focus_once` in actual Clock and Score surfaces: mouse Help and F1 open Help; Escape dismisses Help; focus returns to the initiating control; the calendar month/score value is unchanged; the next Enter/Space invokes the focused control exactly once. Reuse existing native evidence if its revision and changed-consumer scope still apply. The existing `ydotool` probe targets the real desktop and must not be mistaken for input isolated to headless Sway.
- [ ] **Step 3:** Query the native AT-SPI tree from outside the application. For each interactive surface, require named actionable descendants and successful invocation of a non-destructive control. Preserve the current zero-descendant failure. Compare one minimal Qt Quick control with one production Kit control under the same compositor/session to localize any new failure; do not repeat already exhausted environment/cache probes without changed evidence.
- [ ] **Step 4:** For any demonstrated shared defect, first add the failing assertion to the relevant existing probe, then apply the smallest shared fix and rerun that probe plus every affected package's native case. Example invariant: `assert invocations == 1` after one enabled activation, unchanged after hidden or disabled activation.
- [ ] **Step 5:** Run the existing reader-layout probe and `python3 docs/prds/evidence/02-accessibility/run-plugin-load-probe.py`; expect passing reader geometry and no component failures. Commit only verified Kit/probe changes and their evidence. Leave unresolved native accessibility as a failed gate.

### Task 3: Complete each plugin's ordered behavior trace and fix reproduced failures

This is a repeated task, executed and reviewed **one plugin at a time**. Each row is an independent deliverable. Its files are the QML entry points under the exact package directory, their directly called `Model.js`/helper files, and that package's existing `test/` directory. Do not edit another package merely because it has a similar surface.

**Interfaces:** Consume Task 1's state map and touchpoint records. Retain all existing QML methods, CLI verbs, JSON state fields, and IPC target names. Produce a complete ordered trace for every discovered user touchpoint and a native result for the principal journey and each repaired interaction.

| Package directory under `plugins/` | Principal journey and mandatory failure/return check |
| --- | --- |
| `alteringux.agenda` | Synthetic due event → one reminder; refresh/restart does not duplicate it |
| `alteringux.agentglass` | Open workspace/session → action completes; vanished session reports failure |
| `alteringux.ask` | Submit → answer → optional speech; speech failure retains answer |
| `alteringux.bottombar` | Open hosted widget → correct panel/IPC; toggle visibility and preserve ownership |
| `alteringux.breathe` | Choose → start → pause/resume → exit; one daemon and no orphan cue players |
| `alteringux.calendar` | Browse → edit → save → reload; AI disclosure before submission and retained result |
| `alteringux.cliamp` | Play/pause and track change; missing player reports unavailable state |
| `alteringux.clock` | Previous/next month → today → Help → return; navigation never selects a date |
| `alteringux.conductor` | Start ritual → ordered steps → result; failed step and retry remain distinct |
| `alteringux.countdown` | Add → edit → expiry → remove; invalid dates retain editor input |
| `alteringux.cpumon` | Open per-core/process view; stale/missing samples retain truthful units/status |
| `alteringux.cursortrail` | Enable/intensity/disable; overlay stays click-through and exits cleanly |
| `alteringux.dashboard` | Open → refresh → read sections; missing timestamp never says “Up to date” |
| `alteringux.deskpet` | Pet action → quiet/disable; vision and unsolicited speech respect opt-in |
| `alteringux.devcast` | Select replay → play/scrub/export; build/import failure preserves selection |
| `alteringux.dictionary` | Selected text/search → suggestions → detail → back; empty result retains query |
| `alteringux.diskmon` | Open mount/path detail → sample; failed sampling exposes retained age/error |
| `alteringux.flow` | Edit node → save → run → inspect output; failed run preserves edits |
| `alteringux.glimpse` | Study → quiz → result → next; missing image and rapid actions remain recoverable |
| `alteringux.grip` | Add/check in → intervention → dismiss; escalation settings and exit work |
| `alteringux.memmon` | Open pressure/swap/process detail; missing sample is not zero pressure |
| `alteringux.nanogpt` | Refresh usage → result; retained snapshot keeps its collector timestamp |
| `alteringux.netwatch` | Open connections/detail → refresh; missing network/tool reports status |
| `alteringux.newsbar` | Refresh both feeds by keyboard/mouse → result; source switch and failed fetch recover |
| `alteringux.notifications` | Open history → inspect → dismiss/clear; retained content/focus match action |
| `alteringux.phone` | Synthetic contact add/edit/delete and message preparation; failed helper reports failure |
| `alteringux.pomodoro` | Start → pause → resume → next phase; rapid commands preserve intended phase |
| `alteringux.pulse` | Open unread source → acknowledge/action → refresh; selection and failure feedback persist |
| `alteringux.recall` | Lesson → answer → feedback → next → exit; failed/missing content remains dismissible |
| `alteringux.reminders` | Enter → next → back → confirm/cancel; draft survives back and cancel schedules nothing |
| `alteringux.reposwatch` | Scan synthetic repos → open selected repo; stale/unavailable repo remains identifiable |
| `alteringux.score` | Increment/decrement → undo → reset/history; ordered rapid actions yield the expected score |
| `alteringux.skilldashboard` | `remove_refresh_restore`: confirm Remove → refresh → Restore; protected paths fail safely |
| `alteringux.sports` | Select match/section → refresh → detail; cached matches/articles keep section timestamps |
| `alteringux.stocks` | Select market → refresh → inspect; retained quotes keep Yahoo Finance and fetch time |
| `alteringux.stopwatch` | Start → pause/resume → cancel; persisted state returns to idle after deletion |
| `alteringux.sysmon` | Open overview/detail → refresh; shared sample age and missing sensors remain clear |
| `alteringux.tempmon` | Inspect sensor/threshold → alert/recovery; missing sensor is not a safe temperature |
| `alteringux.timers` | Add label → start → finish/remove; invalid input and confirmation preserve intended timer |
| `alteringux.ttsplayer` | Play/pause → voice change → stop; stream failure retains truthful transport state |
| `alteringux.vpnrotate` | Synthetic connect/rotate/disconnect results; Wi-Fi guard, busy gate and kill-switch failure |
| `alteringux.wordstep` | Selection → read → pause/resume → exit; requested paused/failed speech prevents advance |

For each row:

- [ ] **Step 1:** Trace every handler's calls in order through the QML/model/helper and asynchronous completion. Record the final state promised by the visible label. Check sequential undo, stale responses, missing transitions, dead guards and watcher resets.
- [ ] **Step 2:** Execute the principal journey with synthetic data and record actual input/output. Add `rapid_activation_preserves_intent` where commands can overlap: issue A then B while A is busy, and assert the documented final result and queue/coalescing policy. Do not assume restarting a Process in `onExited` is broken: inspected Quickshell `Process::onFinished` clears its process pointer before emitting `exited`; a package-level failure needs its own reproduction.
- [ ] **Step 3:** For Skill Dashboard, run `bash tests/omarchy-skilldashboard-lifecycle.test.sh` and add only missing assertions for removed-row persistence, excluded installed totals, successful Restore, invalid trash path and occupied destination. For data providers, run `failed_refresh_preserves_provenance`: good snapshot → failed refresh → same successful timestamp/data with visible failure/cache state.
- [ ] **Step 4:** For a failure, create `CLICK-PATH-<plugin>-NNN` with exact source, ordered trace, expected/actual state and a focused failing check in the existing package test file. If the package has no suitable check, create `plugins/alteringux.<plugin>/test/click-path.test.py`, using `unittest` and a synthetic helper/process fixture. A purely local model check cannot close a visible native failure.
- [ ] **Step 5:** Apply the smallest fix at the demonstrated source; map all callers before shared/multi-file changes. Run `bash tests/run-all.sh --portable <plugin>` and require at least one selected suite, zero failures; run `python3 docs/prds/evidence/02-accessibility/run-plugin-load-probe.py --package alteringux.<plugin>` and the failing native journey again.
- [ ] **Step 6:** Commit the plugin's verified fix/test/evidence together. If no defect is found, commit only its reviewed audit evidence. The row is complete when every touchpoint is classified, every demonstrated defect has a disposition, and the principal/repaired native journeys have actual results. Any non-pass remains an open release gate.

### Task 4: Finish the rendered and assistive-technology matrix

**Files:** `native-matrix.json`, the click-path report, and only the exact package/Kit source and probe files implicated by a reproduced failure.

**Interfaces:** Consume the Task 3 package records. Each visual result adds `surface`, `width`, `height`, `theme`, `textScale`, `contentCase` and evidence references to the Task 2 native-record shape.

- [ ] **Step 1:** Review each applicable real surface at 1280×800 and 800×600 logical output sizes, in light and dark themes, at 100% and 150% text scale. These are audit profiles, not new product minimums. Cover each distinct panel, guide, overlay or form; give service-only plugins an explicit visual non-applicability reason.
- [ ] **Step 2:** Run `constrained_long_content` using a 120-character label, a long unbroken URL, a multiline result, an empty list, and an error message. Assert primary action and exit remain reachable, focused controls scroll into view, meaningful text is not silently lost, and no horizontal content escapes its surface.
- [ ] **Step 3:** Record each profile's rendered observation. Keep screenshots only where needed to substantiate a visual finding or distinct reviewed state; never substitute a browser mock for native QML. Preserve plugin-specific design exceptions from the teardown.
- [ ] **Step 4:** Reproduce any layout/accessibility defect in a focused existing probe, fix its owning component, and rerun the failing profile plus affected consumers. For assistive technology, require external names, roles, state and action delivery; local Qt interfaces alone leave that gate open.
- [ ] **Step 5:** Commit each independent verified layout/accessibility repair and its evidence. Record all remaining platform limitations explicitly.

### Task 5: Verify release, rollback and the final readiness score

**Files:** `docs/prds/omarchy-plugin-production-audit.md`, `README.md:107-116`, `.github/workflows/plugin-checks.yml`, `tests/run-all.sh`, `tests/omarchy-bar-layout.test.sh`, and the completed audit records.

**Interfaces:** Consume native results from Tasks 2–4 and the runtime plan. Produce the final report with exact revision, reproducible checks, open findings, rollback procedure, and score rationale.

- [ ] **Step 1:** On the final candidate, run `git diff --check`, `bash tests/run-all.sh --portable`, the full QML load probe, and `python3 tests/omarchy-plugin-catalog.test.py`. Expect zero failures; account explicitly for any intentional inventory/component-count change from 42/126.
- [ ] **Step 2:** Publish the authorized candidate branch and verify a green CI run at its exact SHA. Reuse the existing green run only if that SHA is unchanged.
- [ ] **Step 3:** After runtime recovery, run `bash tests/omarchy-bar-layout.test.sh` on both the built-in `eDP-1` profile and a fallback display. Require geometry and popup IPC success; require NewsBar only where its configured screen can host it. Preserve and restore the user's display state.
- [ ] **Step 4:** Exercise update and `git revert <commit>` rollback in a disposable deployment with synthetic state. Require state/config preservation, restored startup and responsive IPC. Document an actionable procedure for the currently dirty live checkout; do not treat a clean-worktree prerequisite as permission to discard its changes.
- [ ] **Step 5:** Reconcile all 42 audit IDs, all discovered touchpoints, all required surface profiles, and every numbered finding. Do not close a finding from compilation alone. Score using `ecc:production-audit`: cap at 84 when launch-critical end-to-end evidence is missing, and apply its stricter 69 caps if any of those conditions exist. A 100 requires all agreed gates passing and no unresolved finding within this audited scope; it is not a claim that software has no possible bugs.
- [ ] **Step 6:** Commit the final report/release instructions and present the complete candidate diff and recovery evidence for the release decision. Keep the branch unmerged until the applicable release decision is made; do not close issue #12 while required acceptance evidence is open.

## Self-review and execution handoff

- Scope: all 42 product IDs appear once in Task 3; Kit is separate and third-party plugins are excluded.
- Spec coverage: inventory/design exceptions → Tasks 1/3; Help/header/focus → Task 2; lifecycle/Agentglass/NewsBar/Calendar/data trust → Task 3; rendered/AT-SPI requirements → Tasks 2/4; built-in/fallback geometry and release → Task 5.
- Review Focus: each of the five failure classes has a named check in its owning task.
- Existing passed work is a baseline, not work to redo without a changed revision or unresolved concern.
- Dependency lock recovery is delegated to the separate plan as a workstream, not to another agent.
- Review both plans before executing new tasks. Execution stays in this session with no subagents. The isolated dependency build has stopped and its precise resumption steps are in the runtime plan; no candidate runtime has been installed.
