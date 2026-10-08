# Quickshell Lock Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute without subagents.

**Goal:** Verify a minimal upstream repair for the reproduced Quickshell lock crash and produce a reviewable runtime recovery candidate.

**Architecture:** Keep the installed release's source and apply the existing upstream fix in an isolated checkout. Compare the installed binary and the candidate under the same synthetic lock scenario in a private headless compositor. Keep dependency recovery separate from plugin design changes.

**Tech Stack:** C++20, Qt 6.11.2, Quickshell 0.3.1, CMake 4.4.4, Make, Python 3, Bubblewrap, local Sway 1.12/wlroots 0.20.2 packages.

**Spec:** [Production audit](../../prds/omarchy-plugin-production-audit.md), live-shell blocker; [plugin implementation plan](2026-10-08-omarchy-plugin-audit-and-release.md), native release prerequisites. Repair source: [upstream commit afb2c27](https://github.com/quickshell-mirror/quickshell/commit/afb2c27cd6d600d221d9379a332ee1b321a68487).

## Global Constraints

- Preserve installed `/usr/bin/quickshell` and packaged `/usr/share/omarchy` files during diagnosis/build verification.
- Preserve the original plugin worktree and all existing user changes.
- Use the full feature set; do not disable PAM, locking, Wayland, accessibility or other shipped features to obtain a pass.
- All deliberate lock/crash probes use a private compositor and runtime directory with the real desktop socket hidden.
- Use synthetic data, disable the probe's Quickshell crash reporter and core dumping, and terminate only owned test processes.
- Build one job at a time on this machine. Do not repeat an unchanged successful build/check.
- No upstream comments, issues, or messages are part of this plan.

## Review Focus

1. A second lock request must be declined while the existing holder remains secure — Task 1.
2. A lock property change during surface creation must not re-enter incomplete surface setup or abort — Task 1.
3. After unlocking, a later lock must become secure; stale ownership must not block it — Task 1.
4. A failed probe must clean up only its own compositor and leave the user's desktop/session intact — Task 1.
5. A candidate that passes the synthetic case must still load real plugin QML and pass host integration before release — Task 2 and the plugin plan's Task 5.

---

## Existing state and files

Checkout: `/home/alteringux/worktrees/quickshell-lock-backport` at release commit `1a4716cde794a59928d9d9fc15f2afc7a95de360`. The official fix is already applied and staged in `src/wayland/session_lock.cpp`, `src/wayland/session_lock.hpp`, and `src/wayland/session_lock/session_lock.cpp`. The upstream changelog conflict was resolved by retaining the release's absence of `changelog/next.md`. Do not reapply the cherry-pick.

The full build was launched as `make -C build -j1`; log: `/tmp/quickshell-lock-build.log`. It exited 2 at 4% because its generated Makefiles reference a now-missing CMake executable under `/home/alteringux/.cache/uv/archive-v0/`. This was an exit-127 tool-path failure, not a demonstrated C++ compilation failure. Configure had succeeded using verified CLI11 2.7.2 headers extracted into `.audit-deps/`; system packages were not installed.

Baseline evidence: `/tmp/quickshell-native-audit/lock-probe.qml` and `lock-baseline.log`. Installed Quickshell reached `HOLDER_SECURE`, then exited 134 with the same production fatal message. The Sway compositor used for that baseline was subsequently stopped. This reproduces a failure path; it does not prove every trigger in the user's live shell.

### Task 1: Preserve and extend the regression at the actual lock boundary

**Files:** Create in the dependency checkout `tests/session-lock-regression.qml` and `tests/run-session-lock-regression.py`; inspect the three staged runtime files above. Preserve concise results under the plugin repo's `docs/prds/evidence/06-lock-crash/`.

**Interfaces:** Runner CLI: `python3 tests/run-session-lock-regression.py --quickshell <absolute-binary> --sway <absolute-binary> --expect crash|pass --output <directory>`. Exit 0 means the expected result occurred, not that `--expect crash` is a product pass. Its JSON output records binary/version, scenario, process exit, holder secure state, challenger state, and log path.

- [ ] **Step 1:** Copy the existing synthetic QML scenario and implement the runner with a fresh temporary runtime/compositor for every case. Resolve the local Sway libraries explicitly. Hide `/run` and inherited desktop/session bus variables; expose only the test compositor socket to the tested client. In `finally`, stop and reap only processes created by the runner.
- [ ] **Step 2:** Preserve the negative baseline assertion: `assert returncode != 0`; require both `HOLDER_SECURE` and `Tried to show lockscreen surfaces without active lock` in its output. An import failure or timeout is a harness failure, not a successful reproduction.
- [ ] **Step 3:** Add the fixed-case assertions: second request leaves `holder.locked && holder.secure` true and `challenger.locked` false; holder unlock succeeds; challenger subsequently becomes secure and can unlock. Add a separate case that changes the requested lock state from a surface's creation callback and requires bounded completion without an abort. Use a deadline so a hung state fails.
- [ ] **Step 4:** Run the installed-binary negative case once with the durable runner. Expected: exit 0 from the runner and a recorded client crash with the exact signature. Assert the pre-existing live compositor PID/socket identity is unchanged after test cleanup.
- [ ] **Step 5:** Inspect the staged patch against the official three runtime changes and run `git diff --cached --check`. Keep `.audit-deps/`, `.ignore`, graph files, and unrelated `.gitignore` changes out of the repair commit.

### Task 2: Build and verify the complete candidate

**Files:** Existing `build/`, staged runtime files, Task 1 probes, and `docs/prds/evidence/06-lock-crash/README.md` in the plugin repository.

**Interfaces:** Consume Task 1's runner and the configured full-feature build. Produce a candidate binary with build provenance and before/after evidence; no installed-file mutation is implied.

- [ ] **Step 1:** Create a stable local tool environment: `uv venv --python /usr/bin/python3 .audit-tools`. Keep it untracked.
- [ ] **Step 2:** Install the pinned tool into that environment: `uv pip install --link-mode copy --python .audit-tools/bin/python cmake==4.4.4`. Require `.audit-tools/bin/cmake --version` to report 4.4.4; copied package files must not depend on the disappearing archive path.
- [ ] **Step 3:** Regenerate with `.audit-tools/bin/cmake -S . -B build -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DNO_PCH=ON -DBUILD_TESTING=ON -DFRAME_POINTERS=ON -DDISTRIBUTOR='Omarchy production audit candidate' -DCMAKE_PREFIX_PATH="$PWD/.audit-deps/usr"`. Expected: configure/generate success with all features retained and the stable CMake path in generated Makefiles.
- [ ] **Step 4:** Resume `make -C build -j1`. Preserve reusable objects. On an actual compiler failure, record the exact error and change only its demonstrated cause. Expected: successful full target build.
- [ ] **Step 5:** Run `.audit-tools/bin/ctest --test-dir build --output-on-failure`. Expected: zero failed tests. Record warnings separately from failures.
- [ ] **Step 6:** Run Task 1's `--expect pass` scenarios against the resulting candidate binary under fresh isolated compositors. Expected: no fatal error; correct holder/challenger ownership and reacquisition; no owned processes left behind.
- [ ] **Step 7:** Run the repository's production QML load probe with the candidate binary selected on a temporary PATH and a private compositor. Expected: 126 first-party/Kit components, zero failures, unless a documented source change intentionally changes that count. Do not equate this with full native integration.
- [ ] **Step 8:** Commit the three upstream runtime files and focused regression probes in the dependency checkout, preserving the upstream fix identifier in the commit body. Keep `.audit-tools/` and other local build files out of the commit. Record exact source revision, tool versions, feature configuration, binary checksum and before/after results in the plugin evidence README.
- [ ] **Step 9:** Prepare a concrete package/recovery proposal that preserves package-manager ownership and an installable rollback artifact. Review it before any privileged runtime replacement. Resume the plugin plan's native host checks only after the chosen recovery is actually running and IPC is responsive.

## Self-review and execution handoff

All five failure classes map to explicit regression or integration checks. The plan reuses the upstream repair and existing build instead of adding another lock implementation. A green synthetic regression closes that reproduction only; live-shell recovery, AT-SPI and all-plugin journeys remain separate gates. Execute in the existing session without subagents after plan review.
