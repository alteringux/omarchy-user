#!/usr/bin/env bash
# Black-box tests for ~/.local/bin/omarchy-sysmon — the CLI that owns
# sysmon-state.json (docs/adr/0006-cli-first-plugins.md).
#
#   bash test/cli.test.sh
#
# Drives the CLI against fixture /proc-shaped files instead of the real
# kernel, so results are deterministic across machines and don't depend on
# what the CPU happens to be doing right now.
set -uo pipefail

CLI="${OMARCHY_SYSMON_BIN:-$HOME/.local/bin/omarchy-sysmon}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export OMARCHY_STATE_DIR="$WORK"
export OMARCHY_SYSMON_STAT="$WORK/stat"
export OMARCHY_SYSMON_MEMINFO="$WORK/meminfo"
export OMARCHY_SYSMON_LOADAVG="$WORK/loadavg"
export OMARCHY_SYSMON_UPTIME="$WORK/uptime"
export OMARCHY_SYSMON_SENSORS_JSON='{"coretemp-isa-0000":{"Adapter":"ISA adapter","Package id 0":{"temp1_input":68.000000},"Core 0":{"temp2_input":66.000000}}}'

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }

state() { jq -r "$1" "$WORK/sysmon-state.json"; }

write_stat() { # write_stat <cpu-total-fields...> — one aggregate "cpu" line
  printf 'cpu  %s\n' "$1" > "$WORK/stat"
}

printf 'MemTotal:        8000000 kB\nMemAvailable:    2000000 kB\nSwapTotal:       1000000 kB\nSwapFree:         800000 kB\n' > "$WORK/meminfo"
printf '1.50 2.00 2.50 1/200 12345\n' > "$WORK/loadavg"
printf '86400.00 12345.00\n' > "$WORK/uptime"

# ── first sample: no baseline yet, cpu% must be 0 ────────────────────────
write_stat "100 0 100 800 0 0 0 0 0 0"
"$CLI" sample
[ "$(state '.cpu.pct')" = "0" ] && ok "first sample reports 0% cpu (nothing to diff against)" \
  || bad "first sample cpu%" "$(state '.cpu.pct')"
[ -f "$WORK/sysmon-sample.json" ] && ok "first sample lays down the baseline file" \
  || bad "baseline file" "missing"

# ── second sample: delta-based cpu% ──────────────────────────────────────
# busy = user+nice+system+irq+softirq+steal; idle = idle+iowait
# prev: busy=200 idle=800 total=1000
# next: busy=400 idle=900 total=1300 -> d_busy=200 d_total=300 -> 66.67%
write_stat "200 0 200 900 0 0 0 0 0 0"
"$CLI" sample
pct="$(state '.cpu.pct')"
awk -v p="$pct" 'BEGIN { exit !(p > 66 && p < 67.4) }' \
  && ok "second sample computes cpu% from the delta (~66.7%)" \
  || bad "delta cpu%" "pct=$pct"

# ── memory ────────────────────────────────────────────────────────────────
[ "$(state '.memory.totalKb')" = "8000000" ] && ok "memory.totalKb from MemTotal" \
  || bad "memory.totalKb" "$(state '.memory.totalKb')"
memPct="$(state '.memory.pct')"
awk -v p="$memPct" 'BEGIN { exit !(p > 74.9 && p < 75.1) }' \
  && ok "memory.pct = (total-available)/total * 100 (75%)" \
  || bad "memory.pct" "$memPct"

# ── swap ──────────────────────────────────────────────────────────────────
swapPct="$(state '.swap.pct')"
awk -v p="$swapPct" 'BEGIN { exit !(p > 19.9 && p < 20.1) }' \
  && ok "swap.pct = (total-free)/total * 100 (20%)" \
  || bad "swap.pct" "$swapPct"

# ── load average + uptime ─────────────────────────────────────────────────
[ "$(state '.load.one + 0')" = "1.5" ] && ok "load.one from loadavg" || bad "load.one" "$(state '.load.one')"
[ "$(state '.load.fifteen + 0')" = "2.5" ] && ok "load.fifteen from loadavg" || bad "load.fifteen" "$(state '.load.fifteen')"
[ "$(state '.uptimeSec')" = "86400" ] && ok "uptimeSec truncates /proc/uptime" || bad "uptimeSec" "$(state '.uptimeSec')"

# ── temperature: prefers coretemp Package id 0 ────────────────────────────
[ "$(state '.temp')" = "68" ] && ok "temp reads coretemp Package id 0" || bad "temp" "$(state '.temp')"

# ── temperature: falls back when no coretemp/k10temp chip is present ─────
OMARCHY_SYSMON_SENSORS_JSON='{"nvme-pci-0100":{"Adapter":"PCI adapter","Composite":{"temp1_input":41.500000}}}' "$CLI" sample
[ "$(state '.temp')" = "41.5" ] && ok "temp falls back to the hottest available sensor" \
  || bad "temp fallback" "$(state '.temp')"

# ── temperature: null when no sensor data at all ──────────────────────────
OMARCHY_SYSMON_SENSORS_JSON='{}' "$CLI" sample
[ "$(state '.temp')" = "null" ] && ok "temp is null with no sensor data" || bad "temp null" "$(state '.temp')"

# ── per-core breakdown ────────────────────────────────────────────────────
printf 'cpu  200 0 200 900 0 0 0 0 0 0\ncpu0 100 0 100 450 0 0 0 0 0 0\ncpu1 100 0 100 450 0 0 0 0 0 0\n' > "$WORK/stat"
"$CLI" sample
[ "$(state '.cpu.cores | length')" = "2" ] && ok "cores array has one entry per cpuN line" \
  || bad "cores length" "$(state '.cpu.cores | length')"

# ── get seeds a state file if missing ─────────────────────────────────────
rm -f "$WORK/sysmon-state.json"
"$CLI" get >/dev/null
[ -f "$WORK/sysmon-state.json" ] && ok "get samples on first run when no state file exists" \
  || bad "get seeds state" "missing"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
