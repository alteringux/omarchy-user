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

# A malformed history container must be ignored rather than aborting sample.
rm -f "$WORK/sysmon-sample.json"
printf '{"history":{"not":"an array"}}\n' > "$WORK/sysmon-state.json"
write_stat "200 0 200 900 0 0 0 0 0 0"
"$CLI" sample
[ "$(state '.history | length')" = "1" ] && ok "malformed history container is reset safely" \
  || bad "malformed history container" "$(state '.history')"

# A malformed cpu baseline must also fall back to the first-sample aggregate.
printf 'not json\n' > "$WORK/sysmon-sample.json"
"$CLI" sample
[ "$(state '.cpu.pct')" = "0" ] && ok "malformed cpu baseline is reset safely" \
  || bad "malformed cpu baseline" "$(state '.cpu.pct')"

# ── history ring: sample appends {ts,cpu,mem,temp}, capped ────────────────
rm -f "$WORK/sysmon-state.json" "$WORK/sysmon-sample.json"
write_stat "200 0 200 900 0 0 0 0 0 0"
"$CLI" sample; "$CLI" sample; "$CLI" sample
hlen="$(state '.history | length')"
[ "$hlen" = "3" ] && ok "each sample appends one history entry" || bad "history length" "$hlen"
hshape="$(state '.history[-1] | [has("cpu"), has("mem"), has("ts")] | all')"
[ "$hshape" = "true" ] && ok "history entries carry ts/cpu/mem" \
  || bad "history entry shape" "$(state '.history[-1]')"

# ── top --json: top-5 by cpu and by mem from a ps fixture ────────────────
printf '1 firefox 42.5 8.3\n2 node 12.0 3.1\n3 Xorg 5.5 1.2\n4 chrome 30.0 22.0\n' > "$WORK/ps"
top_json="$(OMARCHY_SYSMON_PS_OUTPUT="$(cat "$WORK/ps")" "$CLI" top --json)"
[ "$(printf '%s' "$top_json" | jq -r '.byCpu[0].name')" = "firefox" ] \
  && ok "top --json ranks byCpu by %cpu" || bad "top byCpu" "$top_json"
[ "$(printf '%s' "$top_json" | jq -r '.byMem[0].name')" = "chrome" ] \
  && ok "top --json ranks byMem by %mem" || bad "top byMem" "$top_json"

# ── sensors: only tempN_input leaves, voltage/current/fan dropped ────────
printf '%s' '{"coretemp-isa-0000":{"Package id 0":{"temp1_input":68.0}},"applesmc-isa-0300":{"Exhaust":{"fan1_input":4476.0},"TA0V":{"in0_input":15.5}}}' > "$WORK/sensors.json"
sensors_json="$(OMARCHY_SYSMON_SENSORS_JSON="$(cat "$WORK/sensors.json")" "$CLI" sensors)"
[ "$(printf '%s' "$sensors_json" | jq -r 'length')" = "1" ] \
  && ok "sensors keeps only tempN_input leaves" || bad "sensors filter" "$sensors_json"
[ "$(printf '%s' "$sensors_json" | jq -r '.[0].celsius')" = "68" ] \
  && ok "sensors reports the leaf temperature" || bad "sensors value" "$sensors_json"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
