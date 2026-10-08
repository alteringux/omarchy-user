# Omarchy plugin production audit

Date: 2026-10-08

**84/100 — provisional. Rollout held pending native recovery and verification.**
This is an engineering readiness judgment. The production-audit rubric
caps the score at 84 until launch-critical journeys have
direct end-to-end evidence.

## Release surface

42 first-party product plugins, their shared Kit, packaged helpers, and shell
integration. Inventory and design findings are in the
[product teardown](omarchy-plugin-product-teardown.md); verification history
is in the [execution ledger](progress.md).

The remaining work is specified in the
[plugin audit and release plan](../superpowers/plans/2026-10-08-omarchy-plugin-audit-and-release.md)
and the separate
[runtime lock repair plan](../superpowers/plans/2026-10-08-quickshell-lock-repair.md).
The user authorized proceeding on 2026-10-08. Both preserve execution without
subagents; their remaining implementation and native verification tasks are open.

## Evidence checked

- Earlier full desktop checks passed 79 suites, loaded 129 production QML
  components with zero failures, and validated all 42 product manifests.
- The inventory check detects missing, extra, and duplicate catalog entries.
- Clock and Score native mouse and keyboard Help journeys passed. Wordstep's
  selection-to-reader shortcut passed. These cover those journeys only.
- Calendar, Skill Dashboard, Dashboard, Stocks, NanoGPT, and Sports were
  rendered and reviewed at the current display size and theme.
- Candidate source is published on `codex/omarchy-production-candidate`.
  The first CI run failed at checkout because the existing theme gitlink lacked
  a URL. Restoring its verified upstream in `.gitmodules` fixed checkout.
- The next remote run reached all 77 portable suites: 72 passed and five failed.
  Those five now pass in a sandbox with an empty home and ImageMagick absent.
  The complete remote rerun subsequently passed all 77 suites on
  `8b9d85f7cdf4d46a39c45a7dd3adbed4424a3576`:
  [GitHub Actions run 37724926490](https://github.com/alteringux/omarchy-user/actions/runs/37724926490).
- The candidate QML probe loaded 126 components with zero failures. The three
  additional live-checkout components belong to excluded third-party plugins.
  All four inventory/host-schema tests passed against the candidate.
- The complete candidate Breathe suite passed 131 checks with desktop sound
  files hidden. Its slow-cue fixture now checks process ownership directly;
  an isolated negative control left two prior players alive and failed.
- Breathe's focused concurrent-daemon check passed with exactly one opening
  cue. Disabling its lifetime ownership lock in an isolated negative control
  produced two cues and failed the assertion; the daemon source was restored.
- A private headless Sway compositor reproduced the installed Quickshell's
  fatal lock error: one lock became secure, a second request caused exit 134
  with the production signature. The test compositor was then stopped.
  This establishes a reproducible failure path, not every trigger in the live shell.
- The coverage seam now accounts for all 42 JSON audit records and report rows.
  Broader discovery found 1,170 QML handler occurrences in 97 files plus 42 host
  entries; the earlier selected-hook search was incomplete. Package-local Skill
  Dashboard traces identified undefined Palette bindings, Enable retaining disabled
  status, and ownership escape through a symlinked parent. The candidate repairs
  these; focused binding/CLI regressions and two-component QML loading pass.
  The full local portable rerun passed all 77 suites after those fixes.
- The attached-action probe passes four checks/one invocation. A private Wayland
  reader fixture passes 24 geometry checks at actual 340/340/640 px owner widths.
  These do not establish native keyboard, screenshot or AT-SPI completion.

## Risks and evidence missing

1. **Release state:** portable CI is green for the candidate. Commits `aadce0c`,
   `889695f`, and `8b9d85f` contain the source, checkout repair, and portable
   fixture repairs respectively. The feature branch is not merged; desktop
   release gates remain open.
2. **Native journeys:** the remaining plugins and Wordstep's other operations
   need direct interaction evidence. Component loading does not prove them.
3. **Accessibility:** native AT-SPI probes exposed application roots without
   QML descendants. Local Qt accessible interfaces do not resolve this gap.
4. **Layouts:** review at constrained sizes, enlarged text, and alternate
   themes remains incomplete across the 42 packages.
5. **Live shell:** the latest geometry probe failed on an IPC timeout. A live
   Quickshell crash (PID 3825163, SIGABRT) reports “Tried to show lockscreen
   surfaces without active lock.” An isolated second-lock request now reproduces
   that signature. The upstream repair is staged in a separate release-source
   checkout. Its earlier build stopped when a temporary CMake path disappeared;
   the full feature build has resumed with stable copied CMake tooling. Recovery
   and repaired-runtime verification remain open. No native gate pass is claimed
   from this state.

## Continuation checkpoint

- Active objective: improve the score to 100 with verified fixes; no subagents.
- Candidate: `/home/alteringux/worktrees/omarchy-production-candidate`, branch
  `codex/omarchy-production-candidate`, base `9a65c52`, latest `8b9d85f`.
- Preserve the original worktree and its existing user changes.
- The earlier aggregate session `49169` finished: 75 passed, one failed. Its
  Breathe failure was repaired and the whole Breathe suite subsequently passed.
- Logs: `/tmp/omarchy-production-candidate-tests.log`,
  `/tmp/omarchy-production-candidate-breathe.log`,
  `/tmp/omarchy-portable-fixtures.log`, `/tmp/omarchy-ci-second-full.log`.
- Failed CI runs: `37723549036` (checkout), `37723996464` (five suites).
- Passing CI run: `37724926490`, all 77 portable suites, exact commit verified.
- Local-only NewsBar feed scripts and their test remain intentionally ignored;
  the original checkout has one additional local suite.
- Crash report: `~/.cache/quickshell/crashes/cwd92nckkmt/report.txt`.
  Diagnosis extracted no core and changed no desktop state.
- Source-copy inventory: `/tmp/omarchy-production-candidate-files.txt`.
- Runtime checkout: `/home/alteringux/worktrees/quickshell-lock-backport`.
  Official repair `afb2c27cd6d600d221d9379a332ee1b321a68487` is staged over
  release commit `1a4716cde794a59928d9d9fc15f2afc7a95de360`; no installed runtime changed.
- Lock baseline: `/tmp/quickshell-native-audit/lock-probe.qml` and
  `/tmp/quickshell-native-audit/lock-baseline.log`.
  Build session `97863` exited 2; inspect `/tmp/quickshell-lock-build.log`.
- Next action after publishing the review candidate: use the runtime plan's
  stable local CMake steps to resume the build and regression.
  Continue native AT-SPI delivery and the remaining
  package journeys and layout reviews.
- Raise the score only when the corresponding evidence is complete.
