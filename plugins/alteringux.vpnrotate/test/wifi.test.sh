#!/usr/bin/env bash
# Tests for the WiFi-only gate in ~/.local/bin/protonvpn-rotate:
#   - wifi_state_str() collapses `nmcli -t -f TYPE,STATE dev` output to one of
#     connected | disconnected | unavailable | unknown
#   - do_connect() refuses a fresh connect when WiFi is down (rc=2, no CLI call)
#   - do_connect() on the rotate path is NOT gated — it rides a live tunnel
#
#   bash test/wifi.test.sh
#
# Same house style as killswitch.test.sh / metrics.test.sh: stub the CLI/system
# wrappers as shell functions, source the script (its dispatch is guarded), and
# keep any state the script mutates inside $(...) in files.
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

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL - %s\n     %s\n' "$1" "$2"; fail=$((fail+1)); }

NMCLI_OUT="$WORK/nmcli_out"
nmcli() { cat "$NMCLI_OUT" 2>/dev/null; }   # ignores args, replays the fixture
uncache() { WIFI_CACHE=""; WIFI_CACHE_AT=0; }

# ── wifi_state_str parses nmcli output ───────────────────────────────────
printf 'wifi:connected\n' >"$NMCLI_OUT"; uncache
[ "$(wifi_state_str)" = connected ] \
  && ok "wifi_state_str: lone wifi:connected -> connected" \
  || bad "wifi_state_str connected" "got $(wifi_state_str)"

printf 'wifi:disconnected\n' >"$NMCLI_OUT"; uncache
[ "$(wifi_state_str)" = disconnected ] \
  && ok "wifi_state_str: lone wifi:disconnected -> disconnected" \
  || bad "wifi_state_str disconnected" "got $(wifi_state_str)"

printf 'ethernet:connected\nwifi:connected\nloopback:unmanaged\n' >"$NMCLI_OUT"; uncache
[ "$(wifi_state_str)" = connected ] \
  && ok "wifi_state_str: mixed device rows pick the wifi row" \
  || bad "wifi_state_str mixed" "got $(wifi_state_str)"

printf 'wifi:connected\nwifi-p2p:disconnected\n' >"$NMCLI_OUT"; uncache
[ "$(wifi_state_str)" = connected ] \
  && ok "wifi_state_str: wifi-p2p row ignored, wifi:connected wins" \
  || bad "wifi_state_str p2p" "got $(wifi_state_str)"

printf 'ethernet:connected\n' >"$NMCLI_OUT"; uncache
[ "$(wifi_state_str)" = unknown ] \
  && ok "wifi_state_str: no wifi row at all -> unknown" \
  || bad "wifi_state_str no-wifi" "got $(wifi_state_str)"

: >"$NMCLI_OUT"; uncache
nmcli() { return 1; }
[ "$(wifi_state_str)" = unknown ] \
  && ok "wifi_state_str: nmcli errors -> unknown (don't block a non-NM box)" \
  || bad "wifi_state_str nmcli-fail" "got $(wifi_state_str)"
nmcli() { cat "$NMCLI_OUT" 2>/dev/null; }

# ── wifi_active is the connected-only predicate ──────────────────────────
printf 'wifi:connected\n' >"$NMCLI_OUT"; uncache
wifi_active && ok "wifi_active: true when wifi:connected" || bad "wifi_active up" "expected rc 0"
printf 'wifi:disconnected\n' >"$NMCLI_OUT"; uncache
wifi_active && bad "wifi_active down" "expected non-zero rc" || ok "wifi_active: false when wifi:disconnected"

# ── do_connect refuses a fresh connect when WiFi is down ─────────────────
CONN_F="$WORK/conn"; echo false >"$CONN_F"
is_connected_cli()       { [ "$(cat "$CONN_F")" = true ]; }
cli_killswitch_current() { echo off; }
cli_connect_retry()      { echo "connect wrapper SHOULD NOT be called" >&2; echo x >"$WORK/leaked"; return 0; }
current_server()         { echo "JP-FREE#1"; }
probe_ip()               { printf '203.0.113.7\tJP\tTokyo\tProbe Org\n'; }
sleep()                  { :; }
printf '{ "autoRotate": false, "intervalSec": 600, "killSwitch": false }\n' >"$CONFIG_FILE"

printf 'wifi:disconnected\n' >"$NMCLI_OUT"; uncache
rm -f "$WORK/leaked"
set +e
do_connect false >/dev/null 2>"$WORK/err"; rc=$?
set -e
[ "$rc" -eq 2 ] && [ ! -e "$WORK/leaked" ] && grep -qi "wifi" "$WORK/err" \
  && ok "do_connect false: refused on no-wifi (rc=2, no CLI call, stderr explains)" \
  || bad "do_connect no-wifi" "rc=$rc leaked=$([ -e "$WORK/leaked" ] && echo yes || echo no) err=$(cat "$WORK/err")"

# ── do_connect false: 'unknown' wifi is allowed through (backstop only) ───
printf 'ethernet:connected\n' >"$NMCLI_OUT"; uncache
cli_connect_retry() { echo true >"$CONN_F"; echo "Connected to JP-FREE#1."; return 0; }
set +e
do_connect false >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -eq 0 ] && [ "$(cat "$CONN_F")" = true ] \
  && ok "do_connect false: wifi 'unknown' is not blocked (widget is the first gate)" \
  || bad "do_connect unknown-wifi" "rc=$rc conn=$(cat "$CONN_F")"

# ── do_connect true (rotate) is exempt even with wifi down ───────────────
echo true >"$CONN_F"
printf 'wifi:disconnected\n' >"$NMCLI_OUT"; uncache
cli_connect_retry() { echo true >"$CONN_F"; echo "Connected to JP-FREE#2."; return 0; }
set +e
do_connect true >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -eq 0 ] && [ "$(cat "$CONN_F")" = true ] \
  && ok "do_connect true: rotate is allowed even when wifi:disconnected (live tunnel)" \
  || bad "do_connect rotate-off-wifi" "rc=$rc conn=$(cat "$CONN_F")"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
