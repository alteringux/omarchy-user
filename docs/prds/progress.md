# Plugin execution ledger

## Current continuation — 2026-10-08

The user invoked click-path-audit and writing-plans. Two self-reviewed plans now
live under `docs/superpowers/plans/2026-10-08-`: the plugin audit/release plan and
the Quickshell lock-repair plan. Their package table matches all 42 manifest IDs;
execution stays in this session without subagents. The user authorized proceeding
on 2026-10-08; implementation and native verification remain open. Click-path discovery counted 574
handler/key-hook lines in 89 QML files; this is an inventory, not a behavior pass.

The installed Quickshell reproduced the fatal lock signature in a private Sway
compositor: `HOLDER_SECURE`, then a second lock request, then exit 134 with
`Tried to show lockscreen surfaces without active lock`. The isolated compositor
was stopped afterward. The official upstream repair is staged in
`/home/alteringux/worktrees/quickshell-lock-backport`; no installed package changed.
The full build exited 2 at 4% when its temporary uv-cache CMake executable went
missing. The runtime plan specifies a stable copied CMake 4.4.4 environment,
regeneration, and resumption of the existing objects. The score remains 84/100
provisional, with native recovery and verification open.


Production candidate follow-up (2026-10-08): isolated branch
`codex/omarchy-production-candidate` is published at `8b9d85f`.
[Remote CI run 37724926490](https://github.com/alteringux/omarchy-user/actions/runs/37724926490)
passed all 77 portable suites at the verified full commit SHA. Its earlier
checkout failure was fixed by restoring the existing theme gitlink's verified
URL in `.gitmodules`; a positive/negative integrity check now covers that case.
The five subsequent CI suite failures were repaired: checkout-relative binding
and engine fixtures, explicit Sports test configuration, and ImageMagick checks
at Glimpse's image-operation boundaries. All five pass with an empty fixture
home and ImageMagick unavailable. The full candidate Breathe suite passes 131
checks with desktop sounds hidden; its slow-cue fixture checks actual player
ownership and rejects a negative control with two prior players still alive.
Candidate QML loading passes 126 components (the live checkout's additional
three are excluded third-party components), and all four catalog/host-schema
tests pass. Local-only NewsBar flows remain intentionally ignored.
The fresh live geometry gate failed on shell IPC timeout. Quickshell's crash
report for PID 3825163 records SIGABRT and “Tried to show lockscreen surfaces
without active lock.” No native gate pass or crash fix is claimed. The audit
remains provisional at 84/100; native recovery, AT-SPI delivery, package-wide
journeys and broader layout review remain open. Details and continuation state
are in [the production audit](omarchy-plugin-production-audit.md).

This review checkpoint contains the current continuation only. The older local
execution history remains in the preserved original worktree. See the
[product teardown and implementation specification](omarchy-plugin-product-teardown.md)
for the 42-plugin design findings and agreed fixes.

## Implement-spec continuation — 2026-10-08

Draft PR #13 and the existing candidate remain the integration review surface.
The catalog seam now requires all 42 JSON audit records and report rows. Its four
tests pass, with negative controls rejecting missing IDs and unsupported native
passes. Broader discovery found 1,170 hooks/97 QML files plus 42 host entries;
package state/call/native coverage remains open.

Skill Dashboard source tracing reproduced and repaired undefined palette-role
bindings, Enable retaining disabled status, and symlink-parent ownership escape.
Focused palette, QML-load and lifecycle checks pass. Canonical guards also reject
unsafe IDs, forged trash paths and occupied/dangling restore destinations.

The shared attached-action probe passes four checks/one invocation. A private
Wayland reader fixture passes 24 geometry checks at measured owner widths. These
are scoped proofs; they do not establish external AT-SPI or whole-panel journeys.
The full Quickshell repair build is running with stable copied CMake tooling in
the isolated dependency checkout. No installed runtime has changed.

The full local portable implementation run passed all 77 suites after these fixes.
