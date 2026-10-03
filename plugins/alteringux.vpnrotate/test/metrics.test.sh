#!/usr/bin/env bash
# Tests for the metrics sidecar in ~/.local/bin/protonvpn-rotate:
#   - do_metrics parses server load / protocol and samples the iface counters
#   - a successful rotate bumps the rotation tallies and the distinct-IP set
#   - "IP actually changed" is only counted when the exit IP moved
#   - a failed connect bumps the failure counter
#
#   bash test/metrics.test.sh
#
# State that the script mutates inside $(...) is kept in files (see
# killswitch.test.sh for why).
set -uo pipefail

SCRIPT="${PROTONVPN_ROTATE_BIN:-$HOME/.local/bin/protonvpn-rotate}"
[ -f "$SCRIPT" ] || { echo "cannot find protonvpn-rotate at $SCRIPT" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export XDG_STATE_HOME="$WORK/state"

# shellcheck disable=SC1090
source "$SCRIPT"
cli_signed_in() { return 0; }  # auth gate is covered in auth.test.sh
mkdir -p "$STATE_DIR"

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL - %s\n     %s\n' "$1" "$2"; fail=$((fail+1)); }
m() { metric_get "$1"; }

# ── stubs ───────────────────────────────────────────────────────────────
CONN_F="$WORK/conn"; echo true >"$CONN_F"
RX_F="$WORK/rx"; TX_F="$WORK/tx"; echo 1000 >"$RX_F"; echo 200 >"$TX_F"
NEXT_IP_F="$WORK/nextip"; echo "203.0.113.1" >"$NEXT_IP_F"

is_connected_cli() { [ "$(cat "$CONN_F")" = true ]; }
cli_status_raw() { printf 'Status: Connected\nServer: JP-FREE#1 in Tokyo, Japan\nLoad: 42%%\nProtocol: wireguard\n'; }
iface_bytes()    { printf '%s\t%s\n' "$(cat "$RX_F")" "$(cat "$TX_F")"; }
measure_latency(){ echo 37; }
current_server() { echo "JP-FREE#1"; }
cli_connect_retry() { echo "Connected to JP-FREE#1. Your new IP address is x."; return 0; }
probe_ip()       { printf '%s\tJP\tTokyo\tProbe Org\n' "$(cat "$NEXT_IP_F")"; }
sleep()          { :; }
wifi_state_str() { echo connected; }   # wifi gate is covered in wifi.test.sh; keep do_connect flowing here

seed_state() {  # connected exitIp
  cat >"$STATE_FILE" <<EOF
{ "connected": $1, "action": "idle", "server": "JP-FREE#0", "exitIp": "$2",
  "country": "JP", "city": "Tokyo", "org": "", "since": 100, "lastRotate": 100,
  "error": "", "updated": $(date +%s) }
EOF
}

# ── num_or_zero sanitiser ──────────────────────────────────────────────
[ "$(num_or_zero 42)" = 42 ] && [ "$(num_or_zero '')" = 0 ] && [ "$(num_or_zero 'x9')" = 0 ] \
  && ok "num_or_zero: passes integers, zeroes everything else" \
  || bad "num_or_zero" "42->$(num_or_zero 42) ''->$(num_or_zero '') x9->$(num_or_zero x9)"

# ── do_metrics: load + protocol + counters + latency land in the file ──
rm -f "$METRICS_FILE"; seed_state true "203.0.113.9"
do_metrics >/dev/null
[ "$(m load)" = 42 ] && [ "$(m protocol)" = wireguard ] && [ "$(m latencyMs)" = 37 ] \
  && [ "$(m rxBytes)" = 1000 ] && [ "$(m txBytes)" = 200 ] \
  && ok "do_metrics: writes load / protocol / latency / iface bytes" \
  || bad "do_metrics write" "load=$(m load) proto=$(m protocol) lat=$(m latencyMs) rx=$(m rxBytes) tx=$(m txBytes)"

# ── do_metrics while disconnected: load/latency zeroed, counters kept ──
echo false >"$CONN_F"
do_metrics >/dev/null
[ "$(m load)" = 0 ] && [ "$(m latencyMs)" = 0 ] \
  && ok "do_metrics: disconnected -> load and latency zeroed" \
  || bad "do_metrics disconnected" "load=$(m load) lat=$(m latencyMs)"
echo true >"$CONN_F"

# ── rotate success: rotation tallies + distinct-IP set grow ───────────
rm -f "$METRICS_FILE" "$IPS_FILE"; seed_state true "203.0.113.9"; echo "203.0.113.1" >"$NEXT_IP_F"
do_connect true >/dev/null 2>&1
r1_rot="$(m rotations)"; r1_today="$(m rotationsToday)"; r1_chg="$(m ipChangedCount)"; r1_ips="$(m distinctIps)"
[ "$r1_rot" = 1 ] && [ "$r1_today" = 1 ] && [ "$r1_chg" = 1 ] && [ "$r1_ips" = 1 ] && [ -n "$(m todayDate)" ] \
  && ok "rotate: rotations=1, today=1, ipChanged=1 (IP moved), distinctIps=1" \
  || bad "rotate tally #1" "rot=$r1_rot today=$r1_today chg=$r1_chg ips=$r1_ips date=$(m todayDate)"

# ── rotate again, SAME resulting IP: rotations++ but ipChanged stays ──
seed_state true "203.0.113.1"; echo "203.0.113.1" >"$NEXT_IP_F"
do_connect true >/dev/null 2>&1
[ "$(m rotations)" = 2 ] && [ "$(m ipChangedCount)" = 1 ] && [ "$(m distinctIps)" = 1 ] \
  && ok "rotate: unchanged exit IP -> rotations++ but ipChanged and distinctIps hold" \
  || bad "rotate tally #2" "rot=$(m rotations) chg=$(m ipChangedCount) ips=$(m distinctIps)"

# ── rotate to a THIRD distinct IP ────────────────────────────────────
seed_state true "203.0.113.1"; echo "203.0.113.2" >"$NEXT_IP_F"
do_connect true >/dev/null 2>&1
[ "$(m rotations)" = 3 ] && [ "$(m ipChangedCount)" = 2 ] && [ "$(m distinctIps)" = 2 ] \
  && ok "rotate: new exit IP -> ipChanged=2, distinctIps=2" \
  || bad "rotate tally #3" "rot=$(m rotations) chg=$(m ipChangedCount) ips=$(m distinctIps)"

# ── failed connect bumps the failure counter ────────────────────────
cli_connect_retry() { echo "Error: Connection failed."; return 1; }
is_connected_cli()  { return 1; }
f0="$(m failures)"
do_connect false >/dev/null 2>&1
[ "$(m failures)" = "$(( ${f0:-0} + 1 ))" ] \
  && ok "failed connect: failures counter += 1" \
  || bad "failure counter" "was=$f0 now=$(m failures)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
