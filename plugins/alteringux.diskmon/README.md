# alteringux.diskmon

Disk-usage widget for the Omarchy bar — the one system-monitor metric the
existing family (`cpumon` / `memmon` / `tempmon` / `netwatch`) doesn't cover.
Percent-full for a watched mount on the bar, plus a panel with every real
mount's usage, a 10-minute trend sparkline, and the largest subdirectories
under a configured path.

## Why a separate CLI instead of folding into `omarchy-sysmon`

`omarchy-sysmon` exists because CPU% needs a **delta** between two
`/proc/stat` reads — that's the whole reason it keeps a baseline file and a
flock-coalesced sampler shared across three widgets. Disk usage doesn't have
that problem: one `df` call already is the answer. Bolting disk onto
`sysmon-state.json` would mean an unrelated shape riding along with
cpu/memory/temp for no shared benefit, so `omarchy-diskmon` is its own CLI
with its own state file, following the same house shape (docs/adr/0006).

## Files it owns (`~/.local/state/omarchy/`)

| File | Written by | Contents |
|---|---|---|
| `diskmon-state.json` | `omarchy-diskmon sample` | `primary` (the watched mount + level), `mounts` (every non-virtual mount), `history` (10-minute pct ring) |
| `diskmon-config.json` | seeded once, then **hand-edit** | settings below |

### Config

```jsonc
{
  "watchMount": "/",          // which mount the bar glyph + gauge track
  "warnPct": 80,               // level: "warning" at/above this
  "critPct": 92,               // level: "critical" at/above this
  "largestPath": "~",          // path the panel's "largest" scan walks
  "excludeFstypes": ["tmpfs", "devtmpfs", "squashfs", "overlay", "proc", "sysfs", ...]
}
```

## CLI reference

```
omarchy-diskmon sample                 read `df`, write diskmon-state.json
omarchy-diskmon get | status           print diskmon-state.json (sampling first if missing)
omarchy-diskmon list [--json]          every non-virtual mount and its usage
omarchy-diskmon largest [PATH] [--json]
                                        top-10 immediate subdirs of PATH by size (`du`)
                                        PATH defaults to config.largestPath
omarchy-diskmon watch [--interval S]   foreground loop: sample; sleep
omarchy-diskmon config                 print config (edit the file by hand)
omarchy-diskmon reset                  wipe state (keeps config)
```

`largest` shells out to `du --max-depth=1`, which can be slow on a huge
directory — it's only called on demand (panel open / Enter to refresh), never
on the bar widget's sampling timer.

## Widget behaviour

- Bar glyph + `watchMount`'s percent-full, sampled every 30s (disk usage moves
  slowly compared to CPU/memory, so this ticks far less often than cpumon's
  2s).
- An `AttentionDot` lights up warning/critical per the configured thresholds.
- Panel: watched-mount gauge, a 10-minute trend sparkline + min/avg/max
  (reusing the cpumon/memmon/tempmon family's `Sysmon.TrendChart` /
  `Sysmon.StatGrid` — those components are generic over any `{values,max,n}`
  series, not sysmon-specific), the full mount list, and the largest
  subdirectories under `largestPath`.
- Middle-click samples immediately; Enter inside the panel re-samples and
  re-scans `largest`.

## Tests

```bash
bash ~/.config/omarchy/plugins/alteringux.diskmon/test/cli.test.sh
node --test ~/.config/omarchy/plugins/alteringux.diskmon/test/model.test.js
```

The bash suite drives the CLI against fixture `df`/`du` output (env-var
overrides, same pattern as `omarchy-sysmon`'s `OMARCHY_SYSMON_*` fixtures), so
results don't depend on how full the disk actually is. The node suite covers
`Model.js`'s tolerant parsing, formatting, and sparkline/stat projections.

## Self-improvement loop

This plugin opts in (`improve.json`). See `../../docs/self-improvement-loop.md`.

## Opting in

This plugin ships **inactive** — creating the files does not add it to the
bar. To try it, add it to a `left` or `right` section of `bar.layout` in
`~/.config/omarchy/shell.json` (it fits the `cpumon`/`memmon`/`tempmon`/
`netwatch` system-monitor cluster) and restart the shell:

```jsonc
{
  "id": "alteringux.diskmon"
}
```

e.g. right after `alteringux.netwatch` in `bar.layout.left`. This README does
not make that edit — it's a proposal for a human to opt into.
