#!/usr/bin/env bash
# Black-box tests for ~/.local/bin/omarchy-diskmon — the CLI that owns
# diskmon-state.json (docs/adr/0006-cli-first-plugins.md).
#
#   bash test/cli.test.sh
#
# Drives the CLI against fixture `df`/`du` output instead of the real
# filesystem, so results are deterministic across machines regardless of how
# full the disk actually is.
set -uo pipefail

CLI="${OMARCHY_DISKMON_BIN:-$HOME/.local/bin/omarchy-diskmon}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export OMARCHY_STATE_DIR="$WORK"

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }

state() { jq -r "$1" "$WORK/diskmon-state.json"; }

DF_FIXTURE='Filesystem     Type            1024-blocks       Used  Available Capacity Mounted on
/dev/sda2      ext4            102400000   81920000   15360000       85% /
tmpfs          tmpfs             8000000        100    7999900        1% /run
/dev/sda3      ext4             51200000   10240000   38400000       21% /home'

# ── config seeding ────────────────────────────────────────────────────────
"$CLI" config >/dev/null
[ -f "$WORK/diskmon-config.json" ] && ok "any verb seeds diskmon-config.json" \
  || bad "config seed" "missing"
[ "$(jq -r '.watchMount' "$WORK/diskmon-config.json")" = "/" ] \
  && ok "seeded config defaults watchMount=/" || bad "config default" "$(cat "$WORK/diskmon-config.json")"

# ── sample: virtual filesystems are excluded ──────────────────────────────
OMARCHY_DISKMON_DF_OUTPUT="$DF_FIXTURE" "$CLI" sample
mount_count="$(state '.mounts | length')"
[ "$mount_count" = "2" ] && ok "sample excludes tmpfs, keeps real mounts" \
  || bad "mount count" "$mount_count"
printf '%s\n' "$(state '.mounts[].fstype')" | grep -q tmpfs \
  && bad "tmpfs excluded" "tmpfs leaked into mounts" \
  || ok "tmpfs is not in the mounts list"

# ── primary mount picks watchMount ("/") and reports its pct ─────────────
[ "$(state '.primary.target')" = "/" ] && ok "primary mount follows watchMount (/)" \
  || bad "primary.target" "$(state '.primary.target')"
[ "$(state '.primary.pct')" = "85" ] && ok "primary.pct matches df's Capacity column" \
  || bad "primary.pct" "$(state '.primary.pct')"

# ── warn/crit thresholds ──────────────────────────────────────────────────
[ "$(state '.primary.level')" = "warning" ] && ok "85% crosses the default 80% warn threshold" \
  || bad "primary.level" "$(state '.primary.level')"

DF_CRIT='Filesystem     Type            1024-blocks       Used  Available Capacity Mounted on
/dev/sda2      ext4            102400000   96000000   6400000       96% /'
OMARCHY_DISKMON_DF_OUTPUT="$DF_CRIT" "$CLI" sample
[ "$(state '.primary.level')" = "critical" ] && ok "96% crosses the default 92% crit threshold" \
  || bad "primary.level crit" "$(state '.primary.level')"

# ── history ring: sample appends {ts,pct}, capped ─────────────────────────
rm -f "$WORK/diskmon-state.json"
OMARCHY_DISKMON_DF_OUTPUT="$DF_FIXTURE" "$CLI" sample
OMARCHY_DISKMON_DF_OUTPUT="$DF_FIXTURE" "$CLI" sample
OMARCHY_DISKMON_DF_OUTPUT="$DF_FIXTURE" "$CLI" sample
hlen="$(state '.history | length')"
[ "$hlen" = "3" ] && ok "each sample appends one history entry" || bad "history length" "$hlen"
hshape="$(state '.history[-1] | [has("ts"), has("pct")] | all')"
[ "$hshape" = "true" ] && ok "history entries carry ts/pct" || bad "history entry shape" "$(state '.history[-1]')"

# ── get seeds state if missing ────────────────────────────────────────────
rm -f "$WORK/diskmon-state.json"
OMARCHY_DISKMON_DF_OUTPUT="$DF_FIXTURE" "$CLI" get >/dev/null
[ -f "$WORK/diskmon-state.json" ] && ok "get seeds state when missing" \
  || bad "get seeds state" "missing"

# ── largest: top subdirs by size, self-entry dropped ──────────────────────
DU_FIXTURE="$(printf '5242880\t/home/user/Videos\n1048576\t/home/user/Documents\n20971520\t/home/user/.cache\n100\t/home/user\n')"
largest_json="$(OMARCHY_DISKMON_DU_OUTPUT="$DU_FIXTURE" "$CLI" largest /home/user --json)"
[ "$(printf '%s' "$largest_json" | jq -r '. | length')" = "3" ] \
  && ok "largest drops the self-entry (path == PATH)" || bad "largest length" "$largest_json"
[ "$(printf '%s' "$largest_json" | jq -r '.[0].path')" = "/home/user/.cache" ] \
  && ok "largest sorts by size descending" || bad "largest order" "$largest_json"

# ── reset wipes state but keeps config ────────────────────────────────────
"$CLI" reset >/dev/null
[ -f "$WORK/diskmon-config.json" ] && ok "reset keeps config" || bad "reset kept config" "config missing"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
