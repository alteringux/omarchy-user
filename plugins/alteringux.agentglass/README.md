# Agentglass for Omarchy

CLI-first native bar widget and popup for the local agentglass cockpit.
The widget reads the existing CLI; the server remains the source of workflow
state, sampled process resources, and recorded spend.

Use the CLI from this checkout:

```bash
python3 bin/agentglass-agent status
python3 bin/agentglass-agent status --details --json --limit 12
python3 bin/agentglass-agent resources --limit 12
python3 bin/agentglass-agent services --limit 12
python3 bin/agentglass-agent workspace --home
python3 bin/agentglass-agent workspace --home --discover
python3 bin/agentglass-agent setup
```

`status` reads two metadata endpoints, shows attention first, and caps rows
at 12. `--details` adds capacity, installed agent choices, local services, and
recorded spend for the last 24 hours.
`resources` caps process rows at 24 and omits command lines; it includes the
working directory as context. `services` lists bounded TCP listeners and this
user's active, activating, or failed systemd services; it flags public binds
and marks agent ancestry as a signal rather than ownership. Existing
`start`, `schedule`, `field`, and `read` commands provide launch and drill-down.
The native agent form delegates to `agentglass-agent start`, uses an installed
CLI, preserves default permissions, and sends the optional first instruction
over stdin instead of exposing it in process arguments. A separate managed-run
form accepts a command and arguments, starts them without a shell, and offers
bounded CPU priority plus an optional soft memory threshold.
Generic local workflows can run under their own transient systemd unit, so
builds, audio jobs, downloads, and services have a stable unit identity and
per-unit CPU/memory accounting:

```bash
agentglass-agent run "nightly build" --cwd ~/code/orbit -- make -j2
agentglass-agent runs --json
agentglass-agent run-stop agentglass-run-nightly-build-<id>.service
```

Commands are passed as argv, not through a shell. Runs default to a low CPU
weight; systemd weights are relative priorities, not CPU caps. `--priority`
accepts `background` or `normal`; managed work cannot request foreground
priority. Optional `--memory-high 4G` is a soft pressure threshold, never an
OOM limit. Completed runs stay in the managed list until cleared, so peak
memory and accumulated CPU remain inspectable.
The launch inherits `HOME` and `PATH`, not arbitrary shell environment secrets.
Unmanaged work remains visible in the process list but is not assigned to a
workflow.
`workspace --all` clears workspace filtering; `--home` persists home as the
scope shared by connected clients. `--home --discover` also registers only
already-observed repositories beneath home; it never crawls the home directory.
Neither establishes telemetry coverage.
`setup` explicitly persists `~`, registers only already-observed repositories
beneath it, connects installed supported agent integrations, and verifies the
saved scope. It reports partial failures and configured connections separately
from received telemetry; it does not crawl home. The OpenCode plugin takes
effect in newly started OpenCode sessions.

Install from this checkout:

```bash
python3 integrations/omarchy/agentglass/install.py
```

The installer also installs `agentglass-agent` into `~/.local/bin`. Pass
`--bin-dir <path>` for another user-level location; it refuses to replace a
different command and reports if the chosen directory is not on `PATH`.

Use `--omarchy-dir <path>` to target an alternate Omarchy config directory;
`--help` only prints usage and does not access user configuration.

The installer creates timestamped backups of `shell.json` and any previous
plugin (outside the scanned plugin directory, under `omarchy/backups/agentglass`),
installs the current CLI beside the bridge under
`~/.config/omarchy/plugins/alteringux.agentglass/`, and adds the widget beside
Omarchy's agent indicator. Omarchy hot-reloads these files; use
`omarchy restart shell` only if needed. Restore a backup by copying its
`shell.json` back and moving the previous plugin directory back into place.

The bar polls lightweight status every 10 seconds. Capacity and spend are
fetched while the panel is open. Cached readings older than 30 seconds show
as stale; failed refreshes retain previous counts while marking the server
unreachable. State is atomically replaced and contains no auth token.

## What the readings establish

The [workflow glossary](../../../GLOSSARY.md) distinguishes observation,
resource attribution, and managed workflow control.

Scope, a running scanner, and received telemetry are separate facts. A
workspace of `~` does not prove every workflow is instrumented. Resource
readings describe this user's observed processes, parent PIDs, sampled CPU,
and RSS; process CPU is a percentage of one core, and the first CPU reading
is unknown until a second sample exists.
RSS includes shared pages and should not be treated as an exact allocation.
Recorded model spend depends on received usage and pricing data.

The server's process ancestry flag includes same-user tmux servers. It is
not task ownership, so the native view labels it only as a signal. TCP listeners
and user systemd units are inventoried, but they are not reliably joined to
every task/session or cgroup. Automatic resource control requires explicit
managed workload identity and a contention policy before it can act safely.

Checks: `bun test server/test/agent-cli-status.test.ts server/test/machine-services.test.ts`
and `bun test integrations/omarchy/agentglass/test/model.test.js`.
