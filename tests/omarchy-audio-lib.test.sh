#!/usr/bin/env bash
# Tests for ~/.local/bin/omarchy-audio-lib — the shared omarchy_output_muted()
# helper used by omarchy-stopwatch, omarchy-countdown and the speak-* family.
#
# `pactl` is a fixture mock in ./mocks driven by MOCK_* env. Run:
#   bash ~/.config/omarchy/tests/omarchy-audio-lib.test.sh

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LIB="$REPO/local-bin/omarchy-audio-lib"
export PATH="$HERE/mocks:$PATH"

RESULTS=$(mktemp)
trap 'rm -f "$RESULTS"' EXIT

ok()    { echo P >> "$RESULTS"; printf '  \033[32mok\033[0m   %s\n' "$1"; }
no()    { echo F >> "$RESULTS"; printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1"$'\n'"        want: [$3]"$'\n'"        got:  [$2]"; fi; }

# muted <fn>: fresh env, lib sourced, body run with errexit off so it can read
# omarchy_output_muted's non-zero "not muted" return.
run() {
  local fn=$1
  (
    set +eu
    unset OMARCHY_IGNORE_SYSTEM_MUTE OMARCHY_STOPWATCH_IGNORE_SYSTEM_MUTE
    export MOCK_SINK_MUTE=no MOCK_SINK_VOLUME=75
    unset MOCK_PACTL_FAIL
    # shellcheck disable=SC1090
    source "$LIB"
    "$fn"
  )
}

rc() { omarchy_output_muted; echo $?; }

t_muted_sink() {
  export MOCK_SINK_MUTE=yes
  check "muted sink -> muted (rc 0)" "$(rc)" 0
}
t_unmuted_volume_up() {
  export MOCK_SINK_MUTE=no MOCK_SINK_VOLUME=75
  check "unmuted, volume up -> not muted (rc 1)" "$(rc)" 1
}
t_zero_volume() {
  export MOCK_SINK_MUTE=no MOCK_SINK_VOLUME=0
  check "every channel at 0% -> muted (rc 0)" "$(rc)" 0
}
t_low_but_nonzero() {
  export MOCK_SINK_MUTE=no MOCK_SINK_VOLUME=3
  check "quiet but audible (3%) -> not muted (rc 1)" "$(rc)" 1
}
t_pactl_broken() {
  export MOCK_PACTL_FAIL=1 MOCK_SINK_MUTE=yes
  check "pactl broken -> fail open, not muted (rc 1)" "$(rc)" 1
}
t_pactl_absent() {
  export PACTL=definitely-not-a-real-command MOCK_SINK_MUTE=yes
  check "pactl absent -> fail open, not muted (rc 1)" "$(rc)" 1
}
t_override_canonical() {
  export OMARCHY_IGNORE_SYSTEM_MUTE=1 MOCK_SINK_MUTE=yes
  check "OMARCHY_IGNORE_SYSTEM_MUTE=1 -> forced not muted (rc 1)" "$(rc)" 1
}
t_override_legacy() {
  export OMARCHY_STOPWATCH_IGNORE_SYSTEM_MUTE=1 MOCK_SINK_MUTE=yes
  check "legacy OMARCHY_STOPWATCH_IGNORE_SYSTEM_MUTE=1 -> forced not muted (rc 1)" "$(rc)" 1
}
t_override_zero_is_noop() {
  export OMARCHY_IGNORE_SYSTEM_MUTE=0 MOCK_SINK_MUTE=yes
  check "OMARCHY_IGNORE_SYSTEM_MUTE=0 -> still honours the real mute (rc 0)" "$(rc)" 0
}
t_sourcing_is_quiet() {
  # sourcing the lib must not emit anything or run any command
  local out
  out=$( source "$LIB" 2>&1 )
  check "sourcing the lib prints nothing" "$out" ""
}

echo "omarchy-audio-lib tests"
for t in t_muted_sink t_unmuted_volume_up t_zero_volume t_low_but_nonzero \
         t_pactl_broken t_pactl_absent \
         t_override_canonical t_override_legacy t_override_zero_is_noop \
         t_sourcing_is_quiet; do
  run "$t"
done

p=$(grep -c P "$RESULTS"); f=$(grep -c F "$RESULTS")
echo
echo "  $p passed, $f failed"
[ "$f" -eq 0 ]
