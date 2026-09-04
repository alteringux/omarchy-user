# alteringux.netwatch

Native network-traffic tracker for the Omarchy bar: live down/up rate, hour /
day / month rollups, monthly-quota alerts, and a live connection breakdown —
no `vnstat` / `nethogs` / `bandwhich`, no root.

## How it actually works

### Rates and totals come from `/proc/net/dev`

That file is the kernel's per-interface counter table. Each interface row has
cumulative **bytes since boot** for RX (col 1) and TX (col 9). Two facts follow:

- **A rate** is just `(bytes_now - bytes_prev) / seconds_between`. Every
  bandwidth tool does this; there is no special API.
- **"How much today / this month"** is *not* something the kernel tracks — it
  only knows "since boot". So `omarchy-netwatch sample` reads the counter, takes
  the delta since the previous reading (stored in `netwatch-sample.json`), and
  **accumulates** that delta into its own hour / day / month buckets in
  `netwatch-state.json`. Run it on a cadence and the buckets fill in.

A delta that comes back negative (reboot, `ip link` reset, interface switch,
32-bit counter wrap) is **discarded**, not stored — the new low reading just
becomes the next baseline.

Two things call `sample`:

| Caller | When | Why |
|---|---|---|
| `omarchy-netwatch-sample.timer` (systemd --user) | every 30s | buckets keep accruing even when the shell / bar isn't running |
| the bar widget's own `Timer` | every `sampleIntervalSec` | a live rate while you're looking at it |

Both writing is fine — `sample` is cheap and the bucket maths is a sum of
deltas regardless of who sampled.

### Connections come from `ss`

`omarchy-netwatch top` parses `ss -tunHp` into a by-state / by-process /
by-peer breakdown. Without root you see **your own** processes' sockets, which
is enough to answer "what's talking right now". `Recv-Q`/`Send-Q` are shown as
a rough *queued bytes* figure — they are **not** throughput (per-process byte
rates need `nethogs`/eBPF/root, deliberately out of scope here).

## Files it owns (`~/.local/state/omarchy/`)

| File | Written by | Contents |
|---|---|---|
| `netwatch-state.json` | `omarchy-netwatch sample` | the rich state the widget/panel watch: rates ring, buckets, peak, quota, alert watermarks |
| `netwatch-sample.json` | `omarchy-netwatch sample` | last raw counter reading, for the next delta |
| `netwatch-config.json` | seeded once, then **hand-edit** | settings below |

### Config

```jsonc
{
  "iface": "auto",          // "auto" = follow the default route; or "wlp2s0"
  "sampleIntervalSec": 20,  // widget tick
  "monthlyQuotaGB": 0,      // 0 = unlimited; >0 turns on the % gauge + 80/100% alerts
  "quotaCountsTx": true,    // count upload toward the cap too
  "spikeMbps": 50,          // 3 consecutive samples over this → one info alert (10-min cooldown)
  "ratesRingSize": 180,     // live sparkline history (min 10)
  "hourlyCap": 72, "dailyCap": 90, "monthlyCap": 24,
  "webhook": ""             // optional n8n URL — see below
}
```

## Reuse of sibling plugin CLIs

- **Alerts** (`omarchy-pulse log alteringux.netwatch …`) — quota 80% / 100% and
  sustained-spike events land in the Pulse activity feed and raise an attention
  item with a "View traffic" action.
- **VPN tag** — the panel's meta line reads `protonvpn-rotate status` and the
  interface name/type to mark whether the active link is a tunnel.

## n8n (optional)

Set `webhook` to an n8n Webhook URL and every `sample` POSTs
`{ ts, status, alerts }` — a heartbeat you can archive for history beyond the
90-day ring, with `alerts[]` non-empty only when one just fired.

`netwatch.n8n.json` in this directory is an importable workflow with two flows:

1. **Webhook → Has alerts? →** split per alert → `notify-send` (add ntfy /
   email / Slack channels here); the no-alert branch is a NoOp where you wire a
   Sheets/DB/file archive node.
2. **Daily 08:00 →** `omarchy-netwatch month --json` → format → deliver a
   "month so far" digest.

Import it at `http://127.0.0.1:5678`, point the delivery nodes at your
channels, and set `webhook` in `netwatch-config.json` to the webhook node's
URL.

## CLI reference

```
omarchy-netwatch sample [--webhook URL]   read counters, roll buckets, fire alerts
omarchy-netwatch status                   flat { iface, rxRate, txRate, today, month, quota… }
omarchy-netwatch get                      dump netwatch-state.json
omarchy-netwatch today | week | month     rollup (add --json for the raw series)
omarchy-netwatch sparkline [-n N]         last N live rate samples (JSON)
omarchy-netwatch top [--json]             live connection breakdown from `ss`
omarchy-netwatch watch [--interval S]     foreground sample loop
omarchy-netwatch config                   print config (edit the file by hand)
omarchy-netwatch reset                    wipe state + sample (keeps config)
```

## Tests

```bash
node --test ~/.config/omarchy/plugins/alteringux.netwatch/
```

Covers the delta engine, backwards-counter/interface-change guards, bucket
rollup + capping, quota 80/100% one-shot alerts + month reset, the sustained-
spike detector + cooldown, and the `status`/`report` projections.
