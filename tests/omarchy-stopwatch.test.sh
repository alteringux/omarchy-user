#!/usr/bin/env bash
# Tests for ~/.local/bin/omarchy-stopwatch's speak() gate and output_muted().
#
# No framework, no sound server: `pactl` is a fixture mock in ./mocks, and
# `pw-play` / `paplay` are a mock that only logs that playback was attempted.
# The script is sourced (its `main` is guarded) so speak() can be called
# directly. Run:  bash ~/.config/omarchy/tests/omarchy-stopwatch.test.sh
#
# Covers the "bell rings while the machine is muted" bug: the interval cue —
# bell or spoken — must stay silent whenever the default output is muted or at
# zero volume, while a missing/broken pactl must fail open (still play) and the
# OMARCHY_STOPWATCH_IGNORE_SYSTEM_MUTE escape hatch must still ring.

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$REPO/local-bin/omarchy-stopwatch"
export PATH="$HERE/mocks:$PATH"

RESULTS=$(mktemp)
trap 'rm -f "$RESULTS"' EXIT

ok()    { echo P >> "$RESULTS"; printf '  \033[32mok\033[0m   %s\n' "$1"; }
no()    { echo F >> "$RESULTS"; printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1"$'\n'"        want: [$3]"$'\n'"        got:  [$2]"; fi; }

played() { [ -s "$MOCK_PLAY_LOG" ] && echo played || echo silent; }

# run <body-fn>: isolated HOME + XDG_RUNTIME_DIR, fresh play log, script sourced
# once per test so each body starts from a clean speak() environment.
run() {
  local fn=$1 tmp
  tmp=$(mktemp -d)
  (
    set +eu
    export HOME="$tmp"
    export XDG_RUNTIME_DIR="$tmp"
    export MOCK_PLAY_LOG="$tmp/play.log"
    : > "$MOCK_PLAY_LOG"
    mkdir -p "$tmp/.local/bin" "$tmp/omarchy-stopwatch"
    # stub piper so the spoken-path cache miss doesn't shell out to the real one
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/.local/bin/piper"
    chmod +x "$tmp/.local/bin/piper"
    # a guaranteed bell file so the bell path doesn't depend on system sounds
    export OMARCHY_STOPWATCH_BELL="$tmp/bell.oga"
    : > "$OMARCHY_STOPWATCH_BELL"
    # sane defaults; individual tests override before calling speak()
    export MOCK_SINK_MUTE=no MOCK_SINK_VOLUME=75
    # shellcheck disable=SC1090
    source "$SCRIPT"
    # the script re-enables `set -euo pipefail`; drop it again so a test can call
    # output_muted() directly and read its non-zero "not muted" return.
    set +eu
    "$fn" "$tmp"
  )
  rm -rf "$tmp"
}

# --- speak(): system mute suppresses every interval cue --------------------

t_muted_bell_silent() {
  export MOCK_SINK_MUTE=yes
  : > "$STATE_DIR/chime"
  speak "one minute."
  check "speak: muted output + bell mode -> no playback" "$(played)" silent
}

t_muted_voice_silent() {
  export MOCK_SINK_MUTE=yes
  speak "one minute."
  check "speak: muted output + voice mode -> no playback" "$(played)" silent
}

t_zero_volume_silent() {
  export MOCK_SINK_MUTE=no MOCK_SINK_VOLUME=0
  : > "$STATE_DIR/chime"
  speak "one minute."
  check "speak: output turned all the way down -> no playback" "$(played)" silent
}

# --- speak(): audible output still plays ----------------------------------

t_unmuted_bell_rings() {
  export MOCK_SINK_MUTE=no MOCK_SINK_VOLUME=75
  : > "$STATE_DIR/chime"
  speak "one minute."
  check "speak: audible output + bell mode -> bell plays" "$(played)" played
}

t_unmuted_voice_speaks() {
  export MOCK_SINK_MUTE=no MOCK_SINK_VOLUME=42
  speak "one minute."
  check "speak: audible output + voice mode -> announcement plays" "$(played)" played
}

# --- speak(): fail-open + escape hatch + existing voice-mute marker -------

t_pactl_broken_fails_open() {
  export MOCK_PACTL_FAIL=1 MOCK_SINK_MUTE=yes
  : > "$STATE_DIR/chime"
  speak "one minute."
  check "speak: pactl missing/broken -> plays anyway (never silenced for good)" "$(played)" played
}

t_ignore_flag_overrides_mute() {
  export OMARCHY_IGNORE_SYSTEM_MUTE=1 MOCK_SINK_MUTE=yes
  : > "$STATE_DIR/chime"
  speak "one minute."
  check "speak: IGNORE_SYSTEM_MUTE=1 -> rings through a muted output" "$(played)" played
}

t_legacy_ignore_flag_still_honoured() {
  export OMARCHY_STOPWATCH_IGNORE_SYSTEM_MUTE=1 MOCK_SINK_MUTE=yes
  : > "$STATE_DIR/chime"
  speak "one minute."
  check "speak: legacy OMARCHY_STOPWATCH_IGNORE_SYSTEM_MUTE=1 still works" "$(played)" played
}

t_voice_mute_marker_still_respected() {
  export MOCK_SINK_MUTE=no MOCK_SINK_VOLUME=75
  printf 'muted\n' > "$STATE_DIR/voice-muted"
  speak "one minute."
  check "speak: voice-muted marker still suppresses the spoken time" "$(played)" silent
}

# output_muted()'s own truth table lives in omarchy-audio-lib.test.sh — the
# helper is shared now, so it's tested where it's defined.

# --- source guard -------------------------------------------------------

t_source_guard() {
  check "source guard: sourcing the script starts nothing / plays nothing" "$(played)" silent
}

echo "omarchy-stopwatch tests"
for t in t_muted_bell_silent t_muted_voice_silent t_zero_volume_silent \
         t_unmuted_bell_rings t_unmuted_voice_speaks \
         t_pactl_broken_fails_open t_ignore_flag_overrides_mute \
         t_legacy_ignore_flag_still_honoured \
         t_voice_mute_marker_still_respected \
         t_source_guard; do
  run "$t"
done

p=$(grep -c P "$RESULTS"); f=$(grep -c F "$RESULTS")
echo
echo "  $p passed, $f failed"
[ "$f" -eq 0 ]
