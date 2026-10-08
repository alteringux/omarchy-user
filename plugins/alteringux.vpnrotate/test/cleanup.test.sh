#!/usr/bin/env bash
# Focused regressions for bounded VPN transitions:
#   - a connected CLI response without a verified probe is cleaned up
#   - a failed disconnect clears cached state and retries cleanup once
#   - SIGTERM during connect clears state and does not strand the tunnel
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SCRIPT="${PROTONVPN_ROTATE_BIN:-$REPO/local-bin/protonvpn-rotate}"
[ -f "$SCRIPT" ] || { echo "cannot find protonvpn-rotate at $SCRIPT" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export XDG_STATE_HOME="$WORK/state"

# shellcheck disable=SC1090
source "$SCRIPT"
mkdir -p "$STATE_DIR"

pass=0 fail=0
ok()   { printf 'ok   - %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL - %s\n     %s\n' "$1" "$2"; fail=$((fail+1)); }

CONN_F="$WORK/connected"; CALLS_F="$WORK/calls"
echo false >"$CONN_F"
: >"$CALLS_F"
record() { printf '%s\n' "$1" >>"$CALLS_F"; }
calls() { tr '\n' ' ' <"$CALLS_F" | sed 's/ *$//'; }
cli_signed_in() { return 0; }
wifi_state_str() { echo connected; }
is_connected_cli() { [ "$(cat "$CONN_F")" = true ]; }
current_server() { echo "NL-FREE#1"; }
sleep() { :; }
cli_killswitch_current() { echo off; }
cli_killswitch() { :; }

seed_state() {
  cat >"$STATE_FILE" <<EOF
{ "connected": $1, "action": "idle", "server": "NL-FREE#1", "exitIp": "198.51.100.7",
  "country": "NL", "city": "Amsterdam", "org": "", "since": 100, "lastRotate": 100,
  "error": "", "updated": $(date +%s) }
EOF
}
cli_disconnect() { record disconnect; echo false >"$CONN_F"; return 0; }
# ── external CLI timeout kills a spawned child too ───────────────────────
TIMEOUT_CLI="$WORK/timeout-cli"; LEAK_PID="$WORK/leaked-pid"; export LEAK_PID
cat >"$TIMEOUT_CLI" <<'EOF'
#!/usr/bin/env bash
(sleep 30) &
echo "$!" >"$LEAK_PID"
sleep 30
EOF
chmod +x "$TIMEOUT_CLI"
CLI_BIN="$TIMEOUT_CLI"; CLI_TIMEOUT_SEC=1
set +e
cli_connect_random >/dev/null
timeout_rc=$?
set -e
leaked_pid="$(cat "$LEAK_PID" 2>/dev/null || true)"
command sleep 0.2
if [ -n "$leaked_pid" ] && kill -0 "$leaked_pid" 2>/dev/null; then
  child_alive=0
else
  child_alive=1
fi
[ "$timeout_rc" -eq 124 ] && [ "$child_alive" -ne 0 ] \
  && ok "timed-out CLI: returns 124 and leaves no spawned child" \
  || bad "CLI timeout cleanup" "rc=$timeout_rc child_alive=$child_alive pid=$leaked_pid"

# Restore test stubs' CLI-independent state after the wrapper smoke check.
CLI_TIMEOUT_SEC=20

# ── success from CLI but no verified probe must disconnect + clear state ──
seed_state false
: >"$CALLS_F"
cli_connect_retry() { echo true >"$CONN_F"; echo connected; return 0; }
probe_ip() { return 1; }
set +e
do_connect false >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ] && [ "$(state_get connected)" = false ] \
  && [ "$(state_get action)" = idle ] && grep -q '^disconnect$' "$CALLS_F" \
  && ok "connect without a verified probe: disconnects and clears state" \
  || bad "connect probe cleanup" "rc=$rc state=$(cat "$STATE_FILE") calls=$(calls)"

# ── failed disconnect gets a bounded cleanup retry and clears stale state ──
seed_state true
: >"$CALLS_F"; echo true >"$CONN_F"
cli_disconnect() { record disconnect; echo false >"$CONN_F"; return 1; }
set +e
do_disconnect >/dev/null 2>&1
rc=$?

set -e
n="$(grep -c '^disconnect$' "$CALLS_F")"
[ "$rc" -eq 1 ] && [ "$n" -eq 2 ] && [ "$(state_get connected)" = false ] \
  && [ "$(state_get action)" = idle ] && [[ "$(state_get error)" == *disconnect* ]] \
  && ok "failed disconnect: retries cleanup and clears stale state" \
  || bad "disconnect failure cleanup" "rc=$rc calls=$n state=$(cat "$STATE_FILE")"
# ── refresh must not adopt a connected CLI without a verified probe ──────
seed_state false
cli_status_raw() { printf 'Status: Connected\nServer: NL-FREE#1 in Amsterdam, Netherlands\n'; }
probe_ip() { return 1; }
set +e
do_refresh >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ] && [ "$(state_get connected)" = false ] \
  && [ "$(state_get action)" = idle ] \
  && ok "refresh without a verified probe: keeps state disconnected" \
  || bad "refresh probe cleanup" "rc=$rc state=$(cat "$STATE_FILE")"

# ── interruption during connect clears state and invokes disconnect ───────
seed_state false
: >"$CALLS_F"; echo false >"$CONN_F"
cli_disconnect() { record disconnect; echo false >"$CONN_F"; return 0; }
cli_connect_retry() { echo true >"$CONN_F"; command sleep 1; }
(
  do_connect false >/dev/null 2>&1
) &
pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ "$(state_get action)" = connecting ] && break
  command sleep 0.05
done
kill -TERM "$pid" 2>/dev/null || true
set +e
wait "$pid"
rc=$?
set -e
[ "$rc" -eq 130 ] && [ "$(state_get connected)" = false ] \
  && [ "$(state_get action)" = idle ] && grep -q '^disconnect$' "$CALLS_F" \
  && ok "SIGTERM during connect: clears state and disconnects" \
  || bad "connect interruption cleanup" "rc=$rc state=$(cat "$STATE_FILE") calls=$(calls)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
