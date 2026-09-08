# alteringux.reposwatch

Git working-tree status across a watched list of repos, on the bar. A trouble
count (dirty + unreadable repos) as the glyph, with a panel breaking each
watched repo down by branch, staged/unstaged/untracked counts, ahead/behind
its upstream, and how long ago its last commit landed.

## Why its own CLI and state file

Nothing here needs a delta between two samples the way `omarchy-sysmon`'s
CPU% does — `git status --porcelain` and `git rev-list --left-right --count`
each answer fully in one shot. So `omarchy-reposwatch` is its own CLI with its
own state file, following the same house shape as `diskmon`/`netwatch`
(docs/adr/0006-cli-first-plugins.md): the CLI is the sole writer, the widget
is a thin `Kit.Store` watcher plus a sampling `Timer`.

The one thing that does need explicit user input — unlike diskmon's mounts or
netwatch's interfaces, which `df`/`/proc/net/dev` enumerate on their own —
is *which* repos to watch. There's no filesystem crawl: `add`/`remove` are
the whole interface for curating the list, because recursively walking
directories for `.git` is slow and surprising about what ends up watched.

## Files it owns (`~/.local/state/omarchy/`)

| File | Written by | Contents |
|---|---|---|
| `reposwatch-state.json` | `omarchy-reposwatch scan` | `repos` (per-repo status), `totals` (aggregate counts) |
| `reposwatch-config.json` | seeded once, then **hand-edit or `add`/`remove`** | `repos`: the watched path list |

Seeding: on first run, `~/.config/omarchy` and `~/Work` are added
automatically if they exist and are git repos (the two paths this house's own
docs already treat as having genuine signal); otherwise the list starts
empty and `add` is how it grows.

### Per-repo status shape

```jsonc
{
  "path": "/home/alteringux/Work",
  "name": "Work",
  "ok": true,
  "error": null,
  "branch": "master",
  "detached": false,
  "dirty": { "staged": 0, "unstaged": 2, "untracked": 5, "total": 7 },
  "hasUpstream": true,
  "ahead": 1,
  "behind": 0,
  "lastCommitTs": 1757308800
}
```

`ok: false` (path doesn't exist, or isn't a git repo) carries a human-readable
`error` instead of the status fields — that's the "critical" case, distinct
from a repo that's merely dirty or diverged ("warning").

## CLI reference

```
omarchy-reposwatch scan                   git-status every configured repo, write state
omarchy-reposwatch get | status           print reposwatch-state.json (scanning first if missing)
omarchy-reposwatch list [--json]          the repos array (pretty table, or --json)
omarchy-reposwatch add PATH               add PATH to the watch list, then scan
omarchy-reposwatch remove PATH            drop PATH from the watch list, then scan
omarchy-reposwatch watch [--interval S]   foreground loop: scan; sleep
omarchy-reposwatch config                 print reposwatch-config.json (seeding it first)
omarchy-reposwatch reset                  wipe state (keeps config)
```

## Widget behaviour

- Bar glyph + a trouble count: how many watched repos are dirty or errored,
  or a check mark (`✓`) when every repo is clean and caught up. Sampled every
  60s — git status across a handful of repos is cheap but not free, and a
  repo's dirty state doesn't change on a CPU-monitor cadence.
- An `AttentionDot` lights up warning/critical: critical only when a watched
  path is gone or isn't a git repo (a config problem), warning for anything
  dirty or ahead/behind its upstream.
- Panel: totals row (dirty / ahead / behind / errors), then one row per
  watched repo — name, branch, ahead/behind, staged/unstaged/untracked
  breakdown, and relative age of its last commit.
- Middle-click rescans immediately; Enter inside the panel does the same.

## Tests

```bash
bash ~/.config/omarchy/plugins/alteringux.reposwatch/test/cli.test.sh
node --test ~/.config/omarchy/plugins/alteringux.reposwatch/test/model.test.js
```

The bash suite drives the CLI against real throwaway git repos under a
tmpdir (git status porcelain output is exact and cheap to produce for real,
so a real repo is simpler and more trustworthy than a fixture string) — 22
assertions covering config seeding, clean/dirty/non-repo scans, ahead/behind
against a real upstream, totals aggregation, and `add`/`remove`/`reset`. The
node suite covers `Model.js`'s tolerant parsing, level classification, and
formatting — 10 assertions, all passing as of this commit.

## Self-improvement loop

This plugin opts in (`improve.json`). See `../../docs/self-improvement-loop.md`.

## Opting in

This plugin ships **inactive** — creating the files does not add it to the
bar. To try it, add it to a `left` or `right` section of `bar.layout` in
`~/.config/omarchy/shell.json` and restart the shell:

```jsonc
{
  "id": "alteringux.reposwatch"
}
```

e.g. alongside `alteringux.netwatch`/`alteringux.diskmon` in
`bar.layout.left`, or in its own `Development`-category slot. This README
does not make that edit — it's a proposal for a human to opt into.
