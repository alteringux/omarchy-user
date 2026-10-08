# Quickshell lock regression

The installed binary reaches `HOLDER_SECURE`; requesting a second lock causes
`Tried to show lockscreen surfaces without active lock` and SIGABRT. A durable
runner reproduced this under private headless Sway. GDB intercepts the fatal
signal before kernel delivery; debugger exit 134 is not a measured client exit.
The runner verifies the pre-existing Hyprland PID/start-time and Wayland socket
identity after cleanup. A normal-process negative control is rejected.

[Baseline result and binary provenance](baseline-result.json) ·
[Debugger output](baseline-client.log).

The upstream repair is applied in the separate release-source checkout:
`/home/alteringux/worktrees/quickshell-lock-backport`. Its three runtime source
files match commit `afb2c27cd6d600d221d9379a332ee1b321a68487` over release
`1a4716cde794a59928d9d9fc15f2afc7a95de360`. The full feature build uses copied
CMake 4.4.4 in `.audit-tools/`, after the earlier temporary-path tool failure.

**Candidate verification is pending.** The runner also checks rejection of a
second lock, subsequent acquisition/unlock, and a lock-property change during
surface creation. Those candidate scenarios have not yet passed; no runtime is
installed from this work. Native accessibility, all-plugin journeys, host
geometry and deployment/rollback remain separate release gates.

See the [runtime plan](../../../superpowers/plans/2026-10-08-quickshell-lock-repair.md).
