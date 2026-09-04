# netwatch roadmap

Candidate accuracy / analytics improvements. The critic (`omarchy-plugin-improve
critic netwatch`) may propose diffs against these, ranked by what the insight
digest shows is actually hurting, and may append new candidates here.

## Accuracy

- **Counter-wrap vs reboot.** `ingest` currently discards any backwards delta.
  Distinguish a 64-bit wrap (delta ≈ 2^64) — which should still be counted —
  from a genuine reset (small new value).
- **Sub-interval sampling drift.** When both the widget and the systemd timer
  sample, `dt` shrinks and rounding error accumulates in the buckets. Track a
  `lastCountedByte` per direction and roll deltas off that, not off wall-clock.
- **Interface-change accounting.** On an iface switch the in-flight delta is
  dropped silently; log how much was lost so the day bucket's error is known.

## Analytics

- **Rolling baseline.** Replace the fixed `spikeMbps` with a mean+stddev per
  hour-of-week computed from the daily/hourly buckets; alert on z-score.
- **Predictive quota.** From month-to-date slope, project the date the cap is
  hit; surface in `status.quota`.
- **Signal correlation.** Sample `iw dev <iface> link` (bitrate, signal dBm)
  alongside throughput; add `status.link` and a "throughput vs signal" series.
- **Protocol / port mix.** Periodic `ss -s` + top remote ports → a
  `status.mix` like `{ "443": 0.83, "53": 0.04, ... }`.
- **Per-connection buckets.** Key buckets on the NetworkManager active
  connection id so home / hotspot / VPN totals are separate.
- **Cost.** `costPerGB` config field → `status.quota.cost`.

## Signals the plugin already emits (see improve insight kinds)

- `counter-reset` — backwards counter seen
- `iface-change` — active interface changed between samples
- `spike-alert` — sustained-rate alert fired (candidate false positive)
- `no-iface` — `sample` could not find a usable interface
- `flag` — a human `omarchy-netwatch flag "..."`
