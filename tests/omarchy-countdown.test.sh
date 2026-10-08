#!/usr/bin/env bash
# Tests for ~/.local/bin/omarchy-countdown's speak() system-mute gate.
#
# No framework, no sound server: `pactl` is a fixture mock in ./mocks and
# `pw-play` is a mock that only logs that playback was attempted. The script is
# sourced (its `main` is guarded) so speak() can be called directly. Run:
#   bash ~/.config/omarchy/tests/omarchy-countdown.test.sh

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$REPO/local-bin/omarchy-countdown"
export PATH="$HERE/mocks:$PATH"

RESULTS=$(mktemp)
trap 'rm -f "$RESULTS"' EXIT

ok()    { echo P >> "$RESULTS"; printf '  \033[32mok\033[0m   %s\n' "$1"; }
no()    { echo F >> "$RESULTS"; printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1"$'\n'"        want: [$3]"$'\n'"        got:  [$2]"; fi; }

played() { [ -s "$MOCK_PLAY_LOG" ] && echo played || echo silent; }

run() {
  local fn=$1 tmp
  tmp=$(mktemp -d)
  (
    set +eu
    export HOME="$tmp"
    export XDG_RUNTIME_DIR="$tmp"
    export MOCK_PLAY_LOG="$tmp/play.log"
    : > "$MOCK_PLAY_LOG"
    mkdir -p "$tmp/.local/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/.local/bin/piper"
    chmod +x "$tmp/.local/bin/piper"
    export MOCK_SINK_MUTE=no MOCK_SINK_VOLUME=75
    unset OMARCHY_IGNORE_SYSTEM_MUTE OMARCHY_STOPWATCH_IGNORE_SYSTEM_MUTE MOCK_PACTL_FAIL
    # shellcheck disable=SC1090
    source "$SCRIPT"
    set +eu   # script re-enables errexit; drop it for the test bodies
    "$fn" "$tmp"
  )
  rm -rf "$tmp"
}

t_muted_silent() {
  export MOCK_SINK_MUTE=yes
  speak "10 seconds remaining."
  check "speak: muted output -> no playback" "$(played)" silent
}

t_zero_volume_silent() {
  export MOCK_SINK_MUTE=no MOCK_SINK_VOLUME=0
  speak "10 seconds remaining."
  check "speak: output turned all the way down -> no playback" "$(played)" silent
}

t_audible_speaks() {
  export MOCK_SINK_MUTE=no MOCK_SINK_VOLUME=60
  speak "10 seconds remaining."
  check "speak: audible output -> announcement plays" "$(played)" played
}

t_pactl_broken_fails_open() {
  export MOCK_PACTL_FAIL=1 MOCK_SINK_MUTE=yes
  speak "10 seconds remaining."
  check "speak: pactl missing/broken -> plays anyway" "$(played)" played
}

t_ignore_flag_overrides_mute() {
  export OMARCHY_IGNORE_SYSTEM_MUTE=1 MOCK_SINK_MUTE=yes
  speak "10 seconds remaining."
  check "speak: OMARCHY_IGNORE_SYSTEM_MUTE=1 -> speaks through a muted output" "$(played)" played
}

t_source_guard() {
  check "source guard: sourcing the script starts nothing / plays nothing" "$(played)" silent
}

echo "omarchy-countdown tests"
for t in t_muted_silent t_zero_volume_silent t_audible_speaks \
         t_pactl_broken_fails_open t_ignore_flag_overrides_mute \
         t_source_guard; do
  run "$t"
done

p=$(grep -c P "$RESULTS"); f=$(grep -c F "$RESULTS")
echo
echo "  $p passed, $f failed"
[ "$f" -eq 0 ]
