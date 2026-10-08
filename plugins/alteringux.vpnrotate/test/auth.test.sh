#!/usr/bin/env bash
# Regression tests for the auth gate + fail-fast + single-flight fixes in
# ~/.local/bin/protonvpn-rotate. The bug: while ProtonVPN was signed out, the
# widget's keep-up watchdog and this script retried `connect` (3x, with sleeps)
# and `killswitch sync` forever, each invocation re-initialising the Proton
# core API and pinning the shell at ~50% CPU.
#
#   bash test/auth.test.sh
#
# House style matches killswitch.test.sh: stub the CLI wrappers as functions,
# source the script (dispatch is guarded), keep $(...)-mutated state in files.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SCRIPT="${PROTONVPN_ROTATE_BIN:-$REPO/local-bin/protonvpn-rotate}"
[ -f "$SCRIPT" ] || { echo "cannot find protonvpn-rotate at $SCRIPT" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export XDG_STATE_HOME="$WORK/state"

# shellcheck disable=SC1090
source "$SCRIPT"   # dispatch is guarded — this only pulls in the functions
mkdir -p "$STATE_DIR"

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL - %s\n     %s\n' "$1" "$2"; fail=$((fail+1)); }

CALLS_F="$WORK/calls"
calls()  { tr '\n' ' ' <"$CALLS_F" 2>/dev/null | sed 's/ *$//'; }
record() { printf '%s\n' "$1" >>"$CALLS_F"; }

# ── shared stubs ────────────────────────────────────────────────────────────
: >"$CALLS_F"
SIGNED_IN_F="$WORK/signed_in"; echo no >"$SIGNED_IN_F"
cli_signed_in()      { [ "$(cat "$SIGNED_IN_F")" = yes ]; }
is_connected_cli()   { return 1; }
cli_connect_random() { record "connect"; echo "Error: Authentication required. Please sign in with 'protonvpn signin'."; return 1; }
cli_disconnect()     { record "disconnect"; }
cli_killswitch()     { record "set:$1"; echo standard; }
cli_killswitch_current() { echo off; }
current_server()     { echo ""; }
probe_ip()           { printf '\t\t\t\n'; return 1; }
sleep()              { record "sleep:$1"; }
wifi_state_str()     { echo connected; }
printf '{ "autoRotate": false, "intervalSec": 600, "killSwitch": true }\n' >"$CONFIG_FILE"

# ── connect_error_class ────────────────────────────────────────────────────
[ "$(connect_error_class 'Error: Authentication required. Please sign in')" = auth ] \
  && ok "connect_error_class: auth error -> auth" \
  || bad "connect_error_class auth" "got $(connect_error_class 'Authentication required')"

[ "$(connect_error_class 'Random selection is not available on the free plan.')" = plan ] \
  && ok "connect_error_class: free-plan restriction -> plan" \
  || bad "connect_error_class plan" "got $(connect_error_class 'not available on the free plan')"

[ "$(connect_error_class 'Error: Connection failed.')" = transient ] \
  && ok "connect_error_class: connection failed -> transient" \
  || bad "connect_error_class transient" "got $(connect_error_class 'Connection failed')"

# ── cli_connect_retry: a non-retryable class bails after ONE attempt ───────
: >"$CALLS_F"
cli_connect_retry 3 0 >/dev/null; rc=$?
[ "$rc" -eq 3 ] && [ "$(grep -c '^connect$' "$CALLS_F")" -eq 1 ] && ! grep -q '^sleep' "$CALLS_F" \
  && ok "cli_connect_retry: auth error -> rc=3 after 1 attempt, no sleep, no retry" \
  || bad "cli_connect_retry fail-fast" "rc=$rc calls='$(calls)'"

# ── cli_connect_retry: transient still retries the full budget ─────────────
: >"$CALLS_F"
cli_connect_random() { record "connect"; echo "Error: Connection failed."; return 1; }
cli_connect_retry 3 0 >/dev/null; rc=$?
[ "$rc" -eq 1 ] && [ "$(grep -c '^connect$' "$CALLS_F")" -eq 3 ] \
  && ok "cli_connect_retry: transient error -> still retries 3x (rc=1)" \
  || bad "cli_connect_retry transient retry" "rc=$rc calls='$(calls)'"
cli_connect_random() { record "connect"; echo "Error: Authentication required."; return 1; }

# ── do_connect: signed out -> rc=3, CLI connect never called ──────────────
: >"$CALLS_F"; echo no >"$SIGNED_IN_F"
set +e; do_connect false >/dev/null 2>"$WORK/err"; rc=$?; set -e
[ "$rc" -eq 3 ] && [ -z "$(calls)" ] \
  && ok "do_connect: signed out -> rc=3, zero CLI calls" \
  || bad "do_connect signed-out" "rc=$rc calls='$(calls)'"

# ── do_connect: signed out leaves a 'signin' hint in the status file ──────
grep -qi "signin" "$STATE_FILE" \
  && ok "do_connect: signed out -> status file error tells the user to sign in" \
  || bad "do_connect signed-out status" "state=$(cat "$STATE_FILE")"

# ── do_connect: failures counter is NOT bumped for a not-signed-in refusal ─
[ "$(metric_get failures)" = "" ] || [ "$(metric_get failures)" = 0 ] \
  && ok "do_connect: signed-out refusal doesn't inflate the failure counter" \
  || bad "do_connect signed-out failures" "failures=$(metric_get failures)"

# ── do_killswitch sync: signed out -> rc=0, deferred, no CLI calls ────────
: >"$CALLS_F"
set +e; do_killswitch sync >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 0 ] && [ -z "$(calls)" ] \
  && ok "do_killswitch sync: signed out -> rc=0 (deferred), zero CLI calls" \
  || bad "do_killswitch sync signed-out" "rc=$rc calls='$(calls)'"

# ── do_killswitch on: signed out -> rc=3 (explicit user action, clear error) ─
: >"$CALLS_F"
set +e; do_killswitch on >/dev/null 2>"$WORK/kserr"; rc=$?; set -e
[ "$rc" -eq 3 ] && [ -z "$(calls)" ] && grep -qi "sign" "$WORK/kserr" \
  && ok "do_killswitch on: signed out -> rc=3, no CLI call, stderr explains" \
  || bad "do_killswitch on signed-out" "rc=$rc calls='$(calls)' err=$(cat "$WORK/kserr")"

# ── signed back in: do_killswitch sync resumes normal behaviour ───────────
: >"$CALLS_F"; echo yes >"$SIGNED_IN_F"
set +e; do_killswitch sync >/dev/null 2>&1; rc=$?; set -e
[ "$(calls)" = "set:on" ] \
  && ok "do_killswitch sync: signed in + config wants on + CLI off -> set:on" \
  || bad "do_killswitch sync signed-in" "rc=$rc calls='$(calls)'"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
