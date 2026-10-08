#!/usr/bin/env bash
# Tests for ~/.local/bin/omarchy-hide-window and its keybindings.
#
# No framework, no network, no compositor: `hyprctl` and `setsid` are replaced
# by mocks in ./mocks that read fixtures from MOCK_* env vars and log dispatch
# calls to a file. Run:  bash ~/.config/omarchy/tests/omarchy-hide-window.test.sh

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$REPO/local-bin/omarchy-hide-window"
BINDINGS="$REPO/hypr/bindings.lua"
export PATH="$HERE/mocks:$PATH"

RESULTS=$(mktemp)
trap 'rm -f "$RESULTS"' EXIT

ok()    { echo P >> "$RESULTS"; printf '  \033[32mok\033[0m   %s\n' "$1"; }
no()    { echo F >> "$RESULTS"; printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1"$'\n'"        want: [$3]"$'\n'"        got:  [$2]"; fi; }

# clients_json addr ws [addr ws ...]  -> hyprctl -j clients fixture
clients_json() {
  local out="[" first=1
  while [ $# -ge 2 ]; do
    [ $first -eq 1 ] || out+=","
    first=0
    out+=$(printf '{"address":"%s","pid":0,"workspace":{"name":"%s"}}' "$1" "$2")
    shift 2
  done
  printf '%s]' "$out"
}

# run <name> <body-fn>: fresh state file + dispatch log + sourced script per test
run() {
  local fn=$1 tmp
  tmp=$(mktemp -d)
  (
    set +eu
    export OMARCHY_HIDE_STATE="$tmp/state"
    export OMARCHY_HIDE_TIMEOUT=0
    export OMARCHY_HIDE_NO_AUDIO=1          # never touch the real pactl
    export MOCK_DISPATCH_LOG="$tmp/dispatch.log"
    export MOCK_NOTIFY_LOG="$tmp/notify.log"
    export MOCK_SETSID_LOG="$tmp/setsid.log"
    export NOTIFY="$HERE/mocks/notify"      # script no longer calls it; kept so a regression is caught
    : > "$MOCK_DISPATCH_LOG"
    : > "$MOCK_NOTIFY_LOG"
    : > "$MOCK_SETSID_LOG"
    : > "$OMARCHY_HIDE_STATE"
    # shellcheck disable=SC1090
    source "$SCRIPT"
    "$fn" "$tmp"
  )
  rm -rf "$tmp"
}

# --- reap_decision ------------------------------------------------------------

t_reap_scratchpad() {
  export MOCK_CLIENTS=$(clients_json 0xAA special:scratchpad)
  check "reap_decision: still in scratchpad -> close" "$(reap_decision 0xAA)" close
}
t_reap_moved_out() {
  export MOCK_CLIENTS=$(clients_json 0xAA 3)
  check "reap_decision: window pulled to ws 3 -> skip" "$(reap_decision 0xAA)" skip
}
t_reap_gone() {
  export MOCK_CLIENTS='[]'
  check "reap_decision: window already gone -> skip" "$(reap_decision 0xAA)" skip
}

# --- do_reap ----------------------------------------------------------------

t_do_reap_closes() {
  printf '100\t0xAA\n' > "$OMARCHY_HIDE_STATE"
  export MOCK_CLIENTS=$(clients_json 0xAA special:scratchpad)
  ( do_reap 0xAA )
  check "do_reap: dispatches a targeted Lua close" "$(cat "$MOCK_DISPATCH_LOG")" \
    'hl.dsp.window.close({ window = "address:0xAA" })'
  check "do_reap: prunes state after close" "$(cat "$OMARCHY_HIDE_STATE")" ""
}
t_do_reap_spares_retrieved() {
  printf '100\t0xAA\n' > "$OMARCHY_HIDE_STATE"
  export MOCK_CLIENTS=$(clients_json 0xAA 2)
  ( do_reap 0xAA )
  check "do_reap: no close when window was retrieved" "$(cat "$MOCK_DISPATCH_LOG")" ""
  check "do_reap: still prunes stale state entry" "$(cat "$OMARCHY_HIDE_STATE")" ""
}

# --- state helpers --------------------------------------------------------

t_state_roundtrip() {
  _state_add 0x1; _state_add 0x2
  check "_state_add: appends, oldest first" "$(_state_addrs | tr '\n' ',')" "0x1,0x2,"
  _state_remove 0x1
  check "_state_remove: drops the entry" "$(_state_addrs | tr '\n' ',')" "0x2,"
  _state_add 0x2
  check "_state_add: dedups an existing address" "$(_state_addrs | tr '\n' ',')" "0x2,"
}

# --- pick_last_hidden ---------------------------------------------------------

t_pick_newest() {
  printf '100\t0xOLD\n200\t0xNEW\n' > "$OMARCHY_HIDE_STATE"
  export MOCK_CLIENTS=$(clients_json 0xOLD special:scratchpad 0xNEW special:scratchpad)
  check "pick_last_hidden: returns newest hidden" "$(pick_last_hidden)" 0xNEW
}
t_pick_skips_stale() {
  printf '100\t0xKEEP\n200\t0xSTALE\n' > "$OMARCHY_HIDE_STATE"
  export MOCK_CLIENTS=$(clients_json 0xKEEP special:scratchpad 0xSTALE 4)
  check "pick_last_hidden: skips a stale newest, returns older hidden" "$(pick_last_hidden)" 0xKEEP
}
t_pick_none() {
  printf '100\t0xGONE\n' > "$OMARCHY_HIDE_STATE"
  export MOCK_CLIENTS='[]'
  check "pick_last_hidden: nothing hidden -> empty" "$(pick_last_hidden)" ""
}

# --- do_hide ----------------------------------------------------------------

t_hide() {
  export MOCK_ACTIVEWINDOW='{"address":"0xABC"}'
  ( do_hide )
  check "do_hide: parks active window in scratchpad (Lua dispatch)" \
    "$(grep -c 'hl.dsp.window.move({ window = "address:0xABC", workspace = "special:scratchpad", follow = false })' "$MOCK_DISPATCH_LOG")" 1
  check "do_hide: records the window in state" "$(_state_addrs)" 0xABC
  check "do_hide: spawns a reaper for the parked window" \
    "$(grep -c -- '--reap 0xABC' "$MOCK_SETSID_LOG")" 1
  check "do_hide: stays silent (no desktop notification)" "$(cat "$MOCK_NOTIFY_LOG")" ""
}
t_hide_no_window() {
  export MOCK_ACTIVEWINDOW='{}'
  ( do_hide )
  check "do_hide: no-op when there is no active window" "$(cat "$MOCK_DISPATCH_LOG")" ""
}

# --- do_hide_all ----------------------------------------------------------

t_hide_all() {
  export MOCK_CLIENTS='[
    {"address":"0xAA","pid":11,"workspace":{"name":"1"}},
    {"address":"0xBB","pid":22,"workspace":{"name":"3"}},
    {"address":"0xCC","pid":33,"workspace":{"name":"special:scratchpad"}}
  ]'
  ( do_hide_all )
  check "do_hide_all: parks 0xAA (current workspace)" \
    "$(grep -c 'hl.dsp.window.move({ window = "address:0xAA", workspace = "special:scratchpad", follow = false })' "$MOCK_DISPATCH_LOG")" 1
  check "do_hide_all: parks 0xBB (a different workspace)" \
    "$(grep -c 'hl.dsp.window.move({ window = "address:0xBB", workspace = "special:scratchpad", follow = false })' "$MOCK_DISPATCH_LOG")" 1
  check "do_hide_all: leaves a window already in a special workspace alone" \
    "$(grep -c 'address:0xCC' "$MOCK_DISPATCH_LOG")" 0
  check "do_hide_all: records both parked windows, oldest first" \
    "$(_state_addrs | tr '\n' ',')" "0xAA,0xBB,"
  check "do_hide_all: lands on a clean workspace 1" \
    "$(grep -c 'hl.dsp.focus({ workspace = "1" })' "$MOCK_DISPATCH_LOG")" 1
  check "do_hide_all: one reaper per parked window" \
    "$(grep -c -- '--reap 0x' "$MOCK_SETSID_LOG")" 2
  check "do_hide_all: stays silent (no desktop notification)" \
    "$(cat "$MOCK_NOTIFY_LOG")" ""
}
t_hide_all_none() {
  export MOCK_CLIENTS='[]'
  ( do_hide_all )
  check "do_hide_all: nothing open -> only the workspace-1 focus dispatch" \
    "$(cat "$MOCK_DISPATCH_LOG")" 'hl.dsp.focus({ workspace = "1" })'
  check "do_hide_all: nothing open -> empty state" "$(_state_addrs)" ""
  check "do_hide_all: nothing open -> no reaper" "$(cat "$MOCK_SETSID_LOG")" ""
}
t_hide_all_only_special() {
  export MOCK_CLIENTS='[{"address":"0xCC","pid":33,"workspace":{"name":"special:magic"}}]'
  ( do_hide_all )
  check "do_hide_all: every window already special -> nothing parked" "$(_state_addrs)" ""
  check "do_hide_all: every window already special -> no move dispatch" \
    "$(grep -c 'window.move' "$MOCK_DISPATCH_LOG")" 0
}

# --- do_unhide ------------------------------------------------------------

t_unhide() {
  printf '100\t0xH\n' > "$OMARCHY_HIDE_STATE"
  export MOCK_CLIENTS=$(clients_json 0xH special:scratchpad)
  export MOCK_ACTIVEWORKSPACE='{"name":"3"}'
  ( do_unhide )
  check "do_unhide: moves hidden window to current workspace, focus follows (Lua dispatch)" \
    "$(grep -c 'hl.dsp.window.move({ window = "address:0xH", workspace = "3", follow = true })' "$MOCK_DISPATCH_LOG")" 1
  check "do_unhide: clears it from state" "$(_state_addrs)" ""
}
t_unhide_nothing() {
  : > "$OMARCHY_HIDE_STATE"
  export MOCK_CLIENTS='[]'
  export MOCK_ACTIVEWORKSPACE='{"name":"3"}'
  ( do_unhide )
  check "do_unhide: no dispatch when nothing is hidden" "$(cat "$MOCK_DISPATCH_LOG")" ""
  check "do_unhide: stays silent when nothing is hidden" "$(cat "$MOCK_NOTIFY_LOG")" ""
}

# --- source guard ---------------------------------------------------------

t_source_guard() {
  export MOCK_ACTIVEWINDOW='{"address":"0xSHOULDNOTFIRE"}'
  # sourcing already happened in run(); it must not have executed any action
  check "source guard: sourcing the script runs no action" "$(cat "$MOCK_DISPATCH_LOG")" ""
}

# --- bindings.lua wiring (checks the real config file) --------------------

bind_checks() {
  grep -q 'hl.unbind("SUPER + W")' "$BINDINGS" \
    && check "bindings: SUPER+W is unbound before rebinding" ok ok \
    || check "bindings: SUPER+W is unbound before rebinding" missing ok
  grep -Eq 'o\.bind\("SUPER \+ W".*omarchy-hide-window"\)' "$BINDINGS" \
    && check "bindings: SUPER+W -> omarchy-hide-window (hide)" ok ok \
    || check "bindings: SUPER+W -> omarchy-hide-window (hide)" missing ok
  grep -q 'o.bind("SUPER + SHIFT + W", "Close window", hl.dsp.window.close())' "$BINDINGS" \
    && check "bindings: SUPER+SHIFT+W -> real Close window" ok ok \
    || check "bindings: SUPER+SHIFT+W -> real Close window" missing ok
  grep -Eq 'o\.bind\("SUPER \+ SHIFT \+ S".*omarchy-hide-window --unhide"\)' "$BINDINGS" \
    && check "bindings: SUPER+SHIFT+S -> omarchy-hide-window --unhide" ok ok \
    || check "bindings: SUPER+SHIFT+S -> omarchy-hide-window --unhide" missing ok
  grep -Eq 'o\.bind\("SUPER \+ ALT \+ DELETE".*omarchy-hide-window --hide-all"\)' "$BINDINGS" \
    && check "bindings: SUPER+ALT+DELETE -> omarchy-hide-window --hide-all" ok ok \
    || check "bindings: SUPER+ALT+DELETE -> omarchy-hide-window --hide-all" missing ok
  grep -Eq 'o\.bind\("SUPER \+ ALT \+ BACKSPACE".*omarchy-hide-window --hide-all"\)' "$BINDINGS" \
    && check "bindings: SUPER+ALT+BACKSPACE twin (apple 'delete' key) -> --hide-all" ok ok \
    || check "bindings: SUPER+ALT+BACKSPACE twin (apple 'delete' key) -> --hide-all" missing ok
}

# --- driver -------------------------------------------------------------

echo "omarchy-hide-window tests"
for t in t_reap_scratchpad t_reap_moved_out t_reap_gone \
         t_do_reap_closes t_do_reap_spares_retrieved \
         t_state_roundtrip \
         t_pick_newest t_pick_skips_stale t_pick_none \
         t_hide t_hide_no_window \
         t_hide_all t_hide_all_none t_hide_all_only_special \
         t_unhide t_unhide_nothing \
         t_source_guard; do
  run "$t"
done
bind_checks

p=$(grep -c P "$RESULTS"); f=$(grep -c F "$RESULTS")
echo
echo "  $p passed, $f failed"
[ "$f" -eq 0 ]
