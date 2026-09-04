# Plugin self-improvement loop

A propose-and-approve loop for the `alteringux.*` plugins that opt in with an
`improve.json`. It never edits code unattended — the most it does on its own is
write Markdown files full of proposed diffs.

Engine: `~/.local/bin/omarchy-plugin-improve` (snapshot: `local-bin/`).
State: `~/.local/state/omarchy/improve/<tool>/`.

Currently opted in: **netwatch**, **devcast** (each has `improve.json` +
`roadmap.md`).

## Three decoupled stages

### 1. Insights — always on, inert

The plugin's own CLI appends short observations when it notices it fell short,
and you can add your own:

```
omarchy-netwatch flag "month total is 200 MB under what the router says"
omarchy-devcast  flag <cast-id> "the diff showed the whole file"
omarchy-plugin-improve insights netwatch          # recent
omarchy-plugin-improve digest   netwatch          # the aggregated view
```

Auto-emitted kinds are listed at the bottom of each plugin's `roadmap.md`
(netwatch: `counter-reset`, `iface-change`, `spike-alert`, `no-iface`;
devcast: `unknown-tool`, `unpaired-tool`, `heavy-truncation`, `high-redaction`,
`no-steps`). All are best-effort and backgrounded — they never change the
outcome of the command that emitted them.

### 2. Critic — gated, OFF by default

`critic` feeds the digest + `roadmap.md` + the current source of the files in
`improve.json.sources` to Featherless (`llm-blurb`, off the Claude
subscription) and asks for ≤3 minimal unified diffs. Output:
`~/.local/state/omarchy/improve/<tool>/proposals/<date>.md`.

It refuses unless explicitly enabled:

```
omarchy-plugin-improve toggle on        # creates ~/.local/state/omarchy/toggles/plugin-improve-on
omarchy-plugin-improve critic netwatch  # or: critic --all
omarchy-plugin-improve critic netwatch --force        # one-off without toggling on
omarchy-plugin-improve critic netwatch --force --dry-run   # just print the prompt
```

A weekly attempt is scheduled by `omarchy-plugin-improve-critic.timer`
(systemd --user, **not enabled** — `systemctl --user enable --now
omarchy-plugin-improve-critic.timer` to run it; still a no-op until `toggle
on`).

### 3. Apply — manual, reviewable, never merges

```
omarchy-plugin-improve proposals netwatch
omarchy-plugin-improve show      netwatch [<date>]
omarchy-plugin-improve apply     netwatch <date> [--only N]
omarchy-plugin-improve revert    netwatch
```

`apply` creates a throwaway git worktree of `~/.config/omarchy` at
`~/.local/state/omarchy/improve/<tool>/worktree` on branch
`improve/<tool>-<date>`, applies each `` ```diff `` block it can
(`git apply --recount --3way`, then GNU `patch`, then leaves the rest as
`.diff` files for hand-application), and runs the plugin's `testCmd` against
the worktree. It prints a review/accept/discard summary and stops. Nothing is
staged, committed, or copied back — you pull in what you want by hand, then
`revert` to delete the worktree and branch.

`~/.local/bin/omarchy-*` files are represented in `improve.json.sources` by
their tracked `local-bin/<name>` snapshot path; accepting such a change means
copying the reviewed file from the worktree's `local-bin/` back to
`~/.local/bin/` yourself.

## Adding another plugin

Drop an `improve.json` in its dir:

```json
{
  "tool": "<name>",
  "criticModel": "Qwen/Qwen3-30B-A3B-Instruct-2507",
  "pluginDir": "plugins/alteringux.<name>",
  "testCmd": "node --test {{dir}}",
  "sources": ["local-bin/omarchy-<name>", "plugins/alteringux.<name>/Model.js"]
}
```

optionally a `roadmap.md` and an `improve-prompt.md` (extra guidance appended
to the critic prompt). Wire `omarchy-plugin-improve insight <name> …` calls
into the plugin's CLI where it can tell it fell short.
