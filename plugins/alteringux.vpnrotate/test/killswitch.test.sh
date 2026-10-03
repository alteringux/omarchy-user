#!/usr/bin/env bash
# Regression tests for the two bugs fixed in ~/.local/bin/protonvpn-rotate:
#
#   1. "Proton turns itself off after a while" — auto-rotate disconnected then
#      failed to reconnect (rc=1 :: Connection failed on the free pool) with
#      nothing retrying, so the tunnel stayed down. Fix: cli_connect_retry, and
#      rotate reconnects on top of the live tunnel instead of dropping first.
#
#   2. Kill switch never engaged — proton-vpn-cli 1.0.3 rejects a kill-switch
#      change while connected, and the widget only ever tried it at shell start
#      (connected). Fix: do_killswitch does disconnect -> set -> reconnect, and
#      a `sync` verb reconciles the CLI setting to the widget config flag.
#
#   bash test/killswitch.test.sh
#
# The script calls the CLI wrappers inside $(...) command substitutions, so
# stub *state* is kept in files (subshell writes to a var wouldn't survive);
# reads go through cat.
set -uo pipefail

SCRIPT="${PROTONVPN_ROTATE_BIN:-$HOME/.local/bin/protonvpn-rotate}"
[ -f "$SCRIPT" ] || { echo "cannot find protonvpn-rotate at $SCRIPT" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export XDG_STATE_HOME="$WORK/state"

# shellcheck disable=SC1090
source "$SCRIPT"   # dispatch is guarded — this only pulls in the functions
cli_signed_in() { return 0; }  # auth gate is covered in auth.test.sh
mkdir -p "$STATE_DIR"

CALLS_F="$WORK/calls"; KS_F="$WORK/ks"; CONN_F="$WORK/conn"; FAILS_F="$WORK/fails"

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL - %s\n     %s\n' "$1" "$2"; fail=$((fail+1)); }
calls() { tr '\n' ' ' <"$CALLS_F" 2>/dev/null | sed 's/ *$//'; }
record() { printf '%s\n' "$1" >>"$CALLS_F"; }

# ── stubs (state in files) ───────────────────────────────────────────────
cli_killswitch_current() { cat "$KS_F"; }
cli_killswitch() { record "set:$1"; [ "$1" = on ] && echo standard >"$KS_F" || echo off >"$KS_F"; }
is_connected_cli() { [ "$(cat "$CONN_F")" = true ]; }
cli_disconnect() { record "disconnect"; echo false >"$CONN_F"; }
cli_connect_random() {
  local n; n="$(cat "$FAILS_F")"
  if [ "$n" -gt 0 ]; then
    echo $((n-1)) >"$FAILS_F"; record "connect:fail"
    echo "Error: Connection failed."; return 1
  fi
  record "connect:ok"; echo true >"$CONN_F"
  echo "Connected to JP-FREE#1 in Tokyo, Japan. Your new IP address is 203.0.113.7."
}
current_server() { echo "JP-FREE#1"; }
probe_ip()       { printf '203.0.113.7\tJP\tTokyo\tProbe Org\n'; }
sleep()          { :; }
wifi_state_str() { echo connected; }   # these tests exercise the kill-switch path, not the wifi gate

scenario() {  # ks_state connected fails killSwitchCfg
  : >"$CALLS_F"; echo "$1" >"$KS_F"; echo "$2" >"$CONN_F"; echo "$3" >"$FAILS_F"
  printf '{ "autoRotate": false, "intervalSec": 600, "killSwitch": %s }\n' "$4" >"$CONFIG_FILE"
}

# ── cli_connect_retry: transient failures are retried ────────────────────
scenario off false 2 false
cli_connect_retry 3 0 >/dev/null; rc=$?
[ $rc -eq 0 ] && [ "$(calls)" = "connect:fail connect:fail connect:ok" ] \
  && ok "cli_connect_retry: two transient failures then success -> rc=0" \
  || bad "cli_connect_retry retry" "rc=$rc calls='$(calls)'"

scenario off false 9 false
cli_connect_retry 3 0 >/dev/null; rc=$?
[ $rc -ne 0 ] && [ "$(grep -c 'connect:fail' "$CALLS_F")" -eq 3 ] \
  && ok "cli_connect_retry: all 3 attempts fail -> non-zero" \
  || bad "cli_connect_retry exhausted" "rc=$rc calls='$(calls)'"

# ── do_killswitch sync: no-op when CLI already matches config ────────────
scenario standard true 0 true
do_killswitch sync >/dev/null 2>&1
[ -z "$(calls)" ] && ok "sync: config on + CLI standard -> no CLI calls" \
  || bad "sync no-op (on)" "calls='$(calls)'"

scenario off true 0 false
do_killswitch sync >/dev/null 2>&1
[ -z "$(calls)" ] && ok "sync: config off + CLI off -> no CLI calls" \
  || bad "sync no-op (off)" "calls='$(calls)'"

# ── do_killswitch sync while DISCONNECTED: set only, no tunnel churn ────
scenario off false 0 true
do_killswitch sync >/dev/null 2>&1
[ "$(calls)" = "set:on" ] && [ "$(cat "$KS_F")" = standard ] \
  && ok "sync: disconnected -> set only, no disconnect/reconnect" \
  || bad "sync disconnected" "calls='$(calls)' ks=$(cat "$KS_F")"

# ── do_killswitch sync while CONNECTED: disconnect -> set -> reconnect ──
scenario off true 0 true
do_killswitch sync >/dev/null 2>&1
[ "$(calls)" = "disconnect set:on connect:ok" ] \
  && [ "$(cat "$KS_F")" = standard ] && [ "$(cat "$CONN_F")" = true ] \
  && ok "sync: connected -> disconnect, set, reconnect (in order)" \
  || bad "sync connected dance" "calls='$(calls)' ks=$(cat "$KS_F") conn=$(cat "$CONN_F")"

# ── do_killswitch sync: turns a standing kill switch back off ──────────
scenario standard false 0 false
do_killswitch sync >/dev/null 2>&1
[ "$(calls)" = "set:off" ] && [ "$(cat "$KS_F")" = off ] \
  && ok "sync: config off + CLI standard -> set off" \
  || bad "sync turn off" "calls='$(calls)' ks=$(cat "$KS_F")"

# ── do_connect re-asserts the kill switch while disconnected ───────────
scenario off false 0 true
do_connect false >/dev/null 2>&1
[ "$(calls)" = "set:on connect:ok" ] \
  && ok "do_connect: asserts kill switch before connecting when config wants it" \
  || bad "do_connect ks assert" "calls='$(calls)'"

# ── do_connect never asserts the kill switch when config doesn't want it ─
scenario off false 0 false
do_connect false >/dev/null 2>&1
[ "$(calls)" = "connect:ok" ] \
  && ok "do_connect: no kill-switch call when config flag is false" \
  || bad "do_connect ks off" "calls='$(calls)'"

# ── do_connect (rotate) never pre-disconnects ─────────────────────────
scenario off true 0 false
do_connect true >/dev/null 2>&1
case " $(calls) " in
  *" disconnect "*) bad "rotate no pre-disconnect" "calls='$(calls)'" ;;
  *" connect:ok "*) ok "do_connect rotate: reconnects on top, no disconnect-first" ;;
  *) bad "rotate connect" "calls='$(calls)'" ;;
esac

# ── do_connect: a failing reconnect is retried, not a single shot ─────
scenario off false 9 false
do_connect true >/dev/null 2>&1
n=$(grep -c 'connect:fail' "$CALLS_F")
[ "$n" -ge 3 ] \
  && ok "do_connect: failed reconnect retried ($n attempts), not stranded after one" \
  || bad "do_connect retry count" "attempts=$n calls='$(calls)'"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
