#!/usr/bin/env bash
# Regression tests for the status-file reconciliation in
# ~/.local/bin/protonvpn-rotate (the "bar icon doesn't sync when the tunnel
# changes out of band" bug). Sources the script with cli_status_raw / probe_ip
# stubbed, drives do_refresh against a throwaway state dir, asserts the file.
#
#   bash test/reconcile.test.sh
set -uo pipefail

SCRIPT="${PROTONVPN_ROTATE_BIN:-$HOME/.local/bin/protonvpn-rotate}"
[ -f "$SCRIPT" ] || { echo "cannot find protonvpn-rotate at $SCRIPT" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export XDG_STATE_HOME="$WORK/state"

# shellcheck disable=SC1090
source "$SCRIPT"   # dispatch is guarded, so this only pulls in the functions

pass=0 fail=0
ok()   { printf 'ok   - %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL - %s\n     %s\n' "$1" "$2"; fail=$((fail+1)); }
field() { state_get "$1"; }

reset_state() {
  mkdir -p "$STATE_DIR"
  cat >"$STATE_FILE" <<EOF
{
  "connected": $1, "action": "$2", "server": "$3", "exitIp": "$4",
  "country": "$5", "city": "", "org": "", "since": ${6:-0},
  "lastRotate": ${7:-0}, "error": "$8", "updated": $(date +%s)
}
EOF
}

# ── parse_cli_status ─────────────────────────────────────────────────────
cli_status_raw() { printf 'Status: Connected\nServer: NL-FREE#127 in Amsterdam, Netherlands\nLoad: 36%%\nProtocol: wireguard\n'; }
got="$(parse_cli_status)"
[ "$got" = $'true\tNL-FREE#127\tAmsterdam\tNetherlands' ] \
  && ok "parse_cli_status: connected line -> connected/server/city/country" \
  || bad "parse_cli_status connected" "got: $(printf %q "$got")"

cli_status_raw() { printf 'Status: Disconnected\n'; }
got="$(parse_cli_status)"
[ "$got" = $'false\t\t\t' ] \
  && ok "parse_cli_status: disconnected -> false and blanks" \
  || bad "parse_cli_status disconnected" "got: $(printf %q "$got")"

# ── do_refresh: adopt an out-of-band connection ─────────────────────────
cli_status_raw() { printf 'Status: Connected\nServer: JP-FREE#3 in Tokyo, Japan\n'; }
probe_ip() { printf '203.0.113.9\tJP\tTokyo\tProbe Org\n'; }
reset_state false error "" "" "" 0 0 "connect failed: Random selection is not available on the free plan."
do_refresh >/dev/null
if [ "$(field connected)" = "true" ] && [ "$(field server)" = "JP-FREE#3" ] \
   && [ "$(field exitIp)" = "203.0.113.9" ] && [ -z "$(field error)" ]; then
  ok "do_refresh: stale 'error' file adopts the live connection + verified IP"
else
  bad "do_refresh adopt" "connected=$(field connected) server=$(field server) ip=$(field exitIp) error=$(field error)"
fi

# ── do_refresh: drop to disconnected when the CLI says so ───────────────
cli_status_raw() { printf 'Status: Disconnected\n'; }
probe_ip() { printf '\t\t\t\n'; return 1; }
reset_state true idle "JP-FREE#3" "203.0.113.9" "JP" 1000 1000 ""
do_refresh >/dev/null
if [ "$(field connected)" = "false" ] && [ -z "$(field server)" ] && [ "$(field lastRotate)" = "1000" ]; then
  ok "do_refresh: CLI disconnected -> file cleared, lastRotate preserved"
else
  bad "do_refresh drop" "connected=$(field connected) server=$(field server) lastRotate=$(field lastRotate)"
fi

# ── do_refresh: already in sync -> no probe, server + since preserved ───
cli_status_raw() { printf 'Status: Connected\nServer: NL-FREE#127 in Amsterdam, Netherlands\n'; }
probe_ip() { echo "PROBE SHOULD NOT RUN" >&2; printf 'x\tx\tx\tx\n'; }
reset_state true idle "NL-FREE#127" "185.107.56.78" "NL" 500 800 ""
out="$(do_refresh 2>&1)"
if [ "$(field exitIp)" = "185.107.56.78" ] && [ "$(field since)" = "500" ] \
   && [ "$(field lastRotate)" = "800" ] && ! grep -q "SHOULD NOT RUN" <<<"$out"; then
  ok "do_refresh: in-sync connection is left alone (no re-probe)"
else
  bad "do_refresh in-sync" "ip=$(field exitIp) since=$(field since) lr=$(field lastRotate) out=$out"
fi

# ── do_refresh: don't stomp a fresh in-flight transition ───────────────
cli_status_raw() { printf 'Status: Disconnected\n'; }
probe_ip() { printf '\t\t\t\n'; return 1; }
reset_state false connecting "" "" "" 0 0 ""
do_refresh >/dev/null
[ "$(field action)" = "connecting" ] \
  && ok "do_refresh: skips while a fresh 'connecting' is in flight" \
  || bad "do_refresh mid-transition" "action=$(field action)"

# ── do_refresh: clears a STALE transient action once past the 45s guard ─
cli_status_raw() { printf 'Status: Disconnected\n'; }
probe_ip() { printf '\t\t\t\n'; return 1; }
cat >"$STATE_FILE" <<EOF
{ "connected": false, "action": "connecting", "server": "", "exitIp": "",
  "country": "", "city": "", "org": "", "since": 0, "lastRotate": 1234,
  "error": "", "updated": $(( $(date +%s) - 600 )) }
EOF
do_refresh >/dev/null
[ "$(field action)" = "idle" ] && [ "$(field connected)" = "false" ] && [ "$(field lastRotate)" = "1234" ] \
  && ok "do_refresh: stale 'connecting' (CLI disconnected, >45s old) -> reset to idle, lastRotate kept" \
  || bad "do_refresh stale-transient" "action=$(field action) connected=$(field connected) lr=$(field lastRotate)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
