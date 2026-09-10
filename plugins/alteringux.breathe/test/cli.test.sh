#!/usr/bin/env bash
# Tests for ~/.local/bin/omarchy-breathe — the breathing engine + daemon.
#
# Drives the real script against a throwaway OMARCHY_STATE_DIR with the daemon
# and every side effect stubbed out, so transitions, crediting and streak maths
# are exercised without spawning a unit or firing notifications. Run:
#   bash ~/.config/omarchy/plugins/alteringux.breathe/test/cli.test.sh

CLI="$HOME/.local/bin/omarchy-breathe"
export OMARCHY_BREATHE_NO_DAEMON=1 OMARCHY_BREATHE_QUIET=1

RESULTS=$(mktemp)
STATE_ROOT=$(mktemp -d)
trap 'rm -rf "$RESULTS" "$STATE_ROOT"' EXIT

ok()    { echo P >> "$RESULTS"; printf '  \033[32mok\033[0m   %s\n' "$1"; }
no()    { echo F >> "$RESULTS"; printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1"$'\n'"        want: [$3]"$'\n'"        got:  [$2]"; fi; }

# Each test gets a pristine state dir so nothing leaks between them.
fresh() {
  OMARCHY_STATE_DIR="$STATE_ROOT/$RANDOM$RANDOM"
  mkdir -p "$OMARCHY_STATE_DIR"
  export OMARCHY_STATE_DIR
}

b() { "$CLI" "$@"; }

# Fake elapsed time without waiting for it: park the session PAUSED at a chosen
# elapsed, which is exactly the state a real pause leaves behind.
park_at() {   # $1 = elapsedMs
  jq --argjson e "$1" --argjson n "$(date +%s%3N)" \
     '.state="PAUSED" | .elapsedMs=$e | .savedAtMs=$n' \
     "$OMARCHY_STATE_DIR/breathe-session.json" > "$OMARCHY_STATE_DIR/.s" \
    && mv "$OMARCHY_STATE_DIR/.s" "$OMARCHY_STATE_DIR/breathe-session.json"
}

# Read through the CLI's own readers rather than off disk: a file the CLI has
# had nothing to write yet legitimately does not exist, and `get`/`stats`/
# `history` are what print the defaults in that case.
sfield()    { b get     | jq -r "$1"; }
statfield() { b stats   | jq -r "$1"; }
histfield() { b history | jq -r "$1"; }

# ── config seeding ────────────────────────────────────────────────────
t_seeds_config() {
  fresh
  b get >/dev/null
  check "a fresh run seeds breathe-config.json" \
    "$([ -f "$OMARCHY_STATE_DIR/breathe-config.json" ] && echo yes)" yes
  check "seeded config carries the default technique" \
    "$(jq -r '.defaultTechniqueId' "$OMARCHY_STATE_DIR/breathe-config.json")" box
  check "seeded config carries the nudge block" \
    "$(jq -r '.nudge.everyMinutes' "$OMARCHY_STATE_DIR/breathe-config.json")" 90
}

t_config_never_mutated() {
  fresh
  b get >/dev/null
  local before after
  before=$(md5sum < "$OMARCHY_STATE_DIR/breathe-config.json")
  b start box --cycles 2 >/dev/null; park_at 40000; b stop >/dev/null; b reset >/dev/null
  after=$(md5sum < "$OMARCHY_STATE_DIR/breathe-config.json")
  check "the CLI never writes breathe-config.json (ADR-0006 rule 4)" "$after" "$before"
}

# ── state transitions ─────────────────────────────────────────────────
t_start() {
  fresh
  local out; out=$(b start box --cycles 3)
  check "start reports RUNNING"            "$(jq -r '.state' <<<"$out")" RUNNING
  check "start resolves the technique name" "$(jq -r '.techniqueName' <<<"$out")" Box
  check "start opens on the first phase"    "$(jq -r '.phaseKind' <<<"$out")" INHALE
  check "start computes the session length" "$(jq -r '.sessionDurationMs' <<<"$out")" 48000
  check "start records the cycle count"     "$(sfield '.cycles')" 3
  check "start stamps a session id"         "$([ -n "$(sfield '.sessionId')" ] && echo yes)" yes
}

t_start_defaults_from_config() {
  fresh
  b get >/dev/null
  jq '.defaultTechniqueId="coherent"' "$OMARCHY_STATE_DIR/breathe-config.json" > "$OMARCHY_STATE_DIR/.c" \
    && mv "$OMARCHY_STATE_DIR/.c" "$OMARCHY_STATE_DIR/breathe-config.json"
  check "a bare start uses the configured default technique" \
    "$(b start | jq -r '.techniqueId')" coherent
  check "a bare start uses the technique's own default cycles" "$(sfield '.cycles')" 12
}

t_pause_freezes() {
  fresh
  b start box --cycles 4 >/dev/null
  park_at 7000
  sleep 0.3
  check "a paused session does not advance with wall clock" "$(b status | jq -r '.elapsedMs')" 7000
  check "a paused session keeps its phase" "$(b status | jq -r '.phaseKind')" HOLD_IN
}

t_toggle_cycles_states() {
  fresh
  check "toggle from IDLE starts"        "$(b toggle | jq -r '.state')" RUNNING
  check "toggle from RUNNING pauses"     "$(b toggle | jq -r '.state')" PAUSED
  check "toggle from PAUSED resumes"     "$(b toggle | jq -r '.state')" RUNNING
  b stop >/dev/null
  check "toggle from DONE starts afresh" "$(b toggle | jq -r '.state')" RUNNING
  check "a restart zeroes the clock"     "$(sfield '.elapsedMs')" 0
}

t_pause_resume_are_idempotent() {
  fresh
  b start box >/dev/null
  b pause >/dev/null
  check "pausing twice stays paused"  "$(b pause | jq -r '.state')" PAUSED
  b resume >/dev/null
  check "resuming twice stays running" "$(b resume | jq -r '.state')" RUNNING
}

# ── crediting ─────────────────────────────────────────────────────────
t_stop_before_a_cycle_credits_nothing() {
  fresh
  b start box --cycles 4 >/dev/null
  park_at 9000                       # 9s of a 16s cycle: not one whole cycle
  b stop >/dev/null
  check "a part-cycle session is not credited to totals" "$(statfield '.totals.sessions')" 0
  check "a part-cycle session is not written to history" "$(histfield '.sessions | length')" 0
  check "a part-cycle session still lands in DONE"       "$(sfield '.state')" DONE
}

t_stop_after_a_cycle_credits() {
  fresh
  b start box --cycles 4 >/dev/null
  park_at 40000                      # 2 whole 16s cycles, part of a third
  b stop >/dev/null
  check "a credited session counts once"        "$(statfield '.totals.sessions')" 1
  check "only whole cycles are credited"        "$(statfield '.totals.cycles')" 2
  check "elapsed seconds are credited"          "$(statfield '.totals.seconds')" 40
  check "history gains the session"             "$(histfield '.sessions | length')" 1
  check "an early stop is not marked completed" "$(histfield '.sessions[0].completed')" false
  check "history records what was planned"      "$(histfield '.sessions[0].plannedCycles')" 4
  check "history records the technique"         "$(histfield '.sessions[0].techniqueId')" box
}

t_full_run_completes() {
  fresh
  b start box --cycles 2 >/dev/null
  park_at 32000                      # exactly the planned length
  b stop >/dev/null
  check "a full run is marked completed" "$(histfield '.sessions[0].completed')" true
  check "a full run credits every cycle" "$(statfield '.totals.cycles')" 2
}

t_overrun_is_clamped() {
  fresh
  b start box --cycles 2 >/dev/null
  park_at 999999                     # the daemon was asleep; wall clock ran on
  b stop >/dev/null
  check "an overrun credits only the planned cycles"  "$(statfield '.totals.cycles')" 2
  check "an overrun credits only the planned seconds" "$(statfield '.totals.seconds')" 32
}

# The daemon's own completion path, as opposed to the `stop` verb. Every other
# test stubs the daemon out, so this is the only place run_loop's finish is
# exercised — and it is the path a real unattended session actually takes.
t_daemon_completes_and_clamps() {
  fresh
  b get >/dev/null
  jq '.customTechniques=[{id:"custom-fast",name:"Fast",family:"custom",tone:"info",defaultCycles:3,
      phases:[{kind:"INHALE",seconds:1,label:"In"},{kind:"EXHALE",seconds:1,label:"Out"}]}]' \
    "$OMARCHY_STATE_DIR/breathe-config.json" > "$OMARCHY_STATE_DIR/.c" \
    && mv "$OMARCHY_STATE_DIR/.c" "$OMARCHY_STATE_DIR/breathe-config.json"
  b start custom-fast --cycles 3 >/dev/null          # 3 x 2s = 6s planned

  # Backdate savedAtMs so the wall clock has badly overrun the plan — a
  # suspend, a long pause, or a daemon that was not scheduled.
  jq --argjson n "$(( $(date +%s%3N) - 20000 ))" '.state="RUNNING" | .elapsedMs=0 | .savedAtMs=$n' \
    "$OMARCHY_STATE_DIR/breathe-session.json" > "$OMARCHY_STATE_DIR/.s" \
    && mv "$OMARCHY_STATE_DIR/.s" "$OMARCHY_STATE_DIR/breathe-session.json"

  timeout 20 "$CLI" __run >/dev/null 2>&1

  check "the daemon finishes an overrun session"        "$(sfield '.state')" DONE
  check "and clamps the clock to the planned length"    "$(sfield '.elapsedMs')" 6000
  check "crediting the planned seconds, not wall clock" "$(statfield '.totals.seconds')" 6
  check "and the planned cycles, not the overrun"       "$(statfield '.totals.cycles')" 3
  check "marked completed"                              "$(histfield '.sessions[0].completed')" true
}

# Phase cues must fire once per boundary and never stack. The daemon kills the
# previous blip before starting the next, so a player slower than the phase (the
# shim sleeps 1.5s inside 1s phases) is cut off rather than left to pile up and
# stutter. Runs the real daemon with a shimmed player on PATH and cues enabled.
t_phase_cues_fire_once_and_do_not_stack() {
  fresh
  local shim="$OMARCHY_STATE_DIR/shim" log="$OMARCHY_STATE_DIR/cues.log"
  mkdir -p "$shim"
  cat > "$shim/pw-play" <<EOF
#!/usr/bin/env bash
echo "START" >> "$log"
sleep 1.5
echo "END" >> "$log"
EOF
  chmod +x "$shim/pw-play"
  : > "$log"

  b get >/dev/null
  jq '.customTechniques=[{id:"cue-fast",name:"CueFast",family:"custom",tone:"info",defaultCycles:6,
      phases:[{kind:"INHALE",seconds:1,label:"In"},{kind:"EXHALE",seconds:1,label:"Out"}]}]' \
    "$OMARCHY_STATE_DIR/breathe-config.json" > "$OMARCHY_STATE_DIR/.c" \
    && mv "$OMARCHY_STATE_DIR/.c" "$OMARCHY_STATE_DIR/breathe-config.json"
  b start cue-fast --cycles 6 >/dev/null            # 6 x 2s = 12s, a boundary every 1s

  PATH="$shim:$PATH" OMARCHY_BREATHE_QUIET=0 OMARCHY_IGNORE_SYSTEM_MUTE=1 \
    timeout 8 "$CLI" __run >/dev/null 2>&1

  # grep -c prints a count but exits 1 on zero matches; keep just the number.
  local blips ends
  blips=$(grep -c START "$log" 2>/dev/null || true)
  ends=$(grep -c END "$log" 2>/dev/null || true)
  check "phase cues actually fire"                   "$([ "${blips:-0}" -ge 3 ] && echo yes)" yes
  check "a slow prior cue is cut off, not stacked"   "$([ "${ends:-0}" -lt "${blips:-0}" ] && echo yes)" yes
}

# A fake HOME carrying a stub piper + voice model, so the voice path is exercised
# without the real Piper install. VOICE_MODEL / PIPER_BIN are $HOME-relative.
_voice_home() {   # $1 = dir, $2 = "with-piper" | "no-piper"
  local fh="$1"
  mkdir -p "$fh/.local/bin" "$fh/.local/share/piper-voices"
  if [ "$2" = "with-piper" ]; then
    printf 'model' > "$fh/.local/share/piper-voices/en_US-lessac-medium.onnx"
    cat > "$fh/.local/bin/piper" <<'EOF'
#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do [ "$1" = "--output_file" ] && { out="$2"; shift; }; shift; done
[ -n "$out" ] && printf 'wav' > "$out"
EOF
    chmod +x "$fh/.local/bin/piper"
  fi
}

t_spoken_cues_play_words_not_the_chime() {
  fresh
  local shim="$OMARCHY_STATE_DIR/shim" log="$OMARCHY_STATE_DIR/plays.log" fh="$OMARCHY_STATE_DIR/home"
  mkdir -p "$shim"
  printf '#!/usr/bin/env bash\necho "$1" >> "%s"\n' "$log" > "$shim/pw-play"
  chmod +x "$shim/pw-play"
  : > "$log"
  _voice_home "$fh" with-piper

  b get >/dev/null
  jq '.cueVoice=true' "$OMARCHY_STATE_DIR/breathe-config.json" > "$OMARCHY_STATE_DIR/.c" \
    && mv "$OMARCHY_STATE_DIR/.c" "$OMARCHY_STATE_DIR/breathe-config.json"
  b start box --cycles 3 >/dev/null                 # In / Hold / Out / Hold

  PATH="$shim:$PATH" HOME="$fh" OMARCHY_BREATHE_QUIET=0 OMARCHY_IGNORE_SYSTEM_MUTE=1 \
    timeout 12 "$CLI" __run >/dev/null 2>&1

  local voiced chimed
  voiced=$(grep -c 'breathe-voice' "$log" 2>/dev/null || true)
  chimed=$(grep -c '\.oga' "$log" 2>/dev/null || true)
  check "spoken cues play the rendered words" "$([ "${voiced:-0}" -ge 2 ] && echo yes)" yes
  check "and never the chime"                 "${chimed:-0}" 0
  check "the words were rendered to the cache" \
    "$([ -s "$OMARCHY_STATE_DIR/breathe-voice/Hold.wav" ] && echo yes)" yes
}

t_spoken_cues_fall_back_to_chime_without_tts() {
  fresh
  local shim="$OMARCHY_STATE_DIR/shim" log="$OMARCHY_STATE_DIR/plays.log" fh="$OMARCHY_STATE_DIR/home"
  mkdir -p "$shim"
  printf '#!/usr/bin/env bash\necho "$1" >> "%s"\n' "$log" > "$shim/pw-play"
  chmod +x "$shim/pw-play"
  : > "$log"
  _voice_home "$fh" no-piper                        # HOME with no piper binary

  b get >/dev/null
  jq '.cueVoice=true' "$OMARCHY_STATE_DIR/breathe-config.json" > "$OMARCHY_STATE_DIR/.c" \
    && mv "$OMARCHY_STATE_DIR/.c" "$OMARCHY_STATE_DIR/breathe-config.json"
  b start box --cycles 2 >/dev/null

  PATH="$shim:$PATH" HOME="$fh" OMARCHY_BREATHE_QUIET=0 OMARCHY_IGNORE_SYSTEM_MUTE=1 \
    timeout 8 "$CLI" __run >/dev/null 2>&1

  check "voice on but no TTS still cues, via the chime" \
    "$([ "$(grep -c '\.oga' "$log" 2>/dev/null || true)" -ge 1 ] && echo yes)" yes
}

# The invariant that matters, enforced where the record is written: no session
# may ever credit more time than the exercise actually lasts, whichever path
# got there.
t_never_credits_more_than_planned() {
  fresh
  b start box --cycles 4 >/dev/null                    # 4 x 16s = 64s planned
  park_at 500000                                       # absurd overrun
  b stop >/dev/null
  check "an absurd overrun still credits only the plan" "$(statfield '.totals.seconds')" 64
  check "and only the planned cycles"                   "$(statfield '.totals.cycles')" 4
}

t_reset_credits_nothing() {
  fresh
  b start box --cycles 4 >/dev/null
  park_at 40000
  b reset >/dev/null
  check "reset abandons without crediting" "$(statfield '.totals.sessions')" 0
  check "reset returns to IDLE"            "$(sfield '.state')" IDLE
  check "reset clears the technique"       "$(sfield '.techniqueId')" ""
}

# ── streaks ───────────────────────────────────────────────────────────
credit_one() {   # a whole credited box session in the current state dir
  b start box --cycles 2 >/dev/null; park_at 32000; b stop >/dev/null
}

set_last_active() {   # $1 = date
  jq --arg d "$1" '.lastActiveDate=$d' "$OMARCHY_STATE_DIR/breathe-stats.json" > "$OMARCHY_STATE_DIR/.st" \
    && mv "$OMARCHY_STATE_DIR/.st" "$OMARCHY_STATE_DIR/breathe-stats.json"
}

t_streak_starts_at_one() {
  fresh; credit_one
  check "the first ever session starts a streak of 1" "$(statfield '.streak')" 1
  check "best streak tracks it"                       "$(statfield '.bestStreak')" 1
  check "last active date is today"                   "$(statfield '.lastActiveDate')" "$(date +%F)"
}

t_streak_same_day_idempotent() {
  fresh; credit_one; credit_one; credit_one
  check "three sessions in one day is still a 1-day streak" "$(statfield '.streak')" 1
  check "but all three are counted"                         "$(statfield '.totals.sessions')" 3
}

t_streak_consecutive_day() {
  fresh; credit_one
  set_last_active "$(date -d yesterday +%F)"
  credit_one
  check "a session the day after extends the streak" "$(statfield '.streak')" 2
}

t_streak_gap_resets() {
  fresh; credit_one
  jq '.streak=9 | .bestStreak=9' "$OMARCHY_STATE_DIR/breathe-stats.json" > "$OMARCHY_STATE_DIR/.st" \
    && mv "$OMARCHY_STATE_DIR/.st" "$OMARCHY_STATE_DIR/breathe-stats.json"
  set_last_active "$(date -d '5 days ago' +%F)"
  credit_one
  check "a gap restarts the streak at 1"     "$(statfield '.streak')" 1
  check "but the best streak is not lost"    "$(statfield '.bestStreak')" 9
}

# ── caps ──────────────────────────────────────────────────────────────
t_history_cap() {
  fresh
  b get >/dev/null
  # 305 synthetic records, then one real credited session pushes past the cap.
  jq -n '{version:1, sessions: [range(305) | {id:"x", techniqueId:"box", startedAtMs:1, seconds:10, cycles:1, plannedCycles:1, completed:true}]}' \
    > "$OMARCHY_STATE_DIR/breathe-history.json"
  credit_one
  check "history is capped at 300" "$(histfield '.sessions | length')" 300
  check "the cap keeps the newest record" "$(histfield '.sessions[-1].seconds')" 32
}

t_daily_cap() {
  fresh
  b get >/dev/null
  jq -n '{version:1, streak:0, bestStreak:0, lastActiveDate:"", totals:{sessions:0,seconds:0,cycles:0},
          daily: ([range(120) | {key: ("2020-01-01" | strptime("%Y-%m-%d") | mktime + (. * 86400) | strftime("%Y-%m-%d")), value:{sessions:1,seconds:60,cycles:4}}] | from_entries)}' \
    --args > "$OMARCHY_STATE_DIR/breathe-stats.json" 2>/dev/null \
    || jq -n '{version:1,streak:0,bestStreak:0,lastActiveDate:"",totals:{sessions:0,seconds:0,cycles:0},daily:{}}' \
       > "$OMARCHY_STATE_DIR/breathe-stats.json"
  # Build 120 distinct days the portable way.
  local d
  for i in $(seq 1 120); do
    d=$(date -d "$i days ago" +%F)
    jq --arg d "$d" '.daily[$d]={sessions:1,seconds:60,cycles:4}' "$OMARCHY_STATE_DIR/breathe-stats.json" \
      > "$OMARCHY_STATE_DIR/.st" && mv "$OMARCHY_STATE_DIR/.st" "$OMARCHY_STATE_DIR/breathe-stats.json"
  done
  credit_one
  check "daily stats are capped at 90 days" "$(statfield '.daily | length')" 90
  check "today survives the prune" "$(statfield ".daily[\"$(date +%F)\"].sessions")" 1
}

# ── restore ───────────────────────────────────────────────────────────
t_restore_finished_while_offline() {
  fresh
  b start box --cycles 2 >/dev/null
  # A running session whose savedAtMs is far in the past: the machine was off.
  jq --argjson n "$(( $(date +%s%3N) - 600000 ))" '.state="RUNNING" | .elapsedMs=0 | .savedAtMs=$n' \
    "$OMARCHY_STATE_DIR/breathe-session.json" > "$OMARCHY_STATE_DIR/.s" \
    && mv "$OMARCHY_STATE_DIR/.s" "$OMARCHY_STATE_DIR/breathe-session.json"
  b restore >/dev/null
  check "a session that ran out offline is parked in DONE" "$(sfield '.state')" DONE
  check "and credited as completed"                        "$(histfield '.sessions[0].completed')" true
  check "at its planned length, not the wall-clock gap"    "$(statfield '.totals.seconds')" 32
}

t_restore_still_live() {
  fresh
  b start box --cycles 20 >/dev/null      # 320s of session
  jq --argjson n "$(( $(date +%s%3N) - 5000 ))" '.state="RUNNING" | .elapsedMs=0 | .savedAtMs=$n' \
    "$OMARCHY_STATE_DIR/breathe-session.json" > "$OMARCHY_STATE_DIR/.s" \
    && mv "$OMARCHY_STATE_DIR/.s" "$OMARCHY_STATE_DIR/breathe-session.json"
  b restore >/dev/null
  check "a still-live session stays RUNNING"   "$(sfield '.state')" RUNNING
  check "and is not credited by the restore"   "$(statfield '.totals.sessions')" 0
}

t_restore_missing_technique() {
  fresh
  b start box --cycles 2 >/dev/null
  jq '.techniqueId="deleted-thing"' "$OMARCHY_STATE_DIR/breathe-session.json" > "$OMARCHY_STATE_DIR/.s" \
    && mv "$OMARCHY_STATE_DIR/.s" "$OMARCHY_STATE_DIR/breathe-session.json"
  b restore >/dev/null
  check "a session whose technique vanished resets rather than wedging" "$(sfield '.state')" IDLE
}

t_restore_on_idle_is_a_noop() {
  fresh
  b restore >/dev/null
  check "restore on a fresh install leaves IDLE" "$(sfield '.state')" IDLE
}

# ── techniques ────────────────────────────────────────────────────────
t_techniques() {
  fresh
  check "the catalogue has the twelve built-ins" "$(b techniques | jq 'length')" 12
  check "every technique has phases"             "$(b techniques | jq '[.[] | select((.phases|length) == 0)] | length')" 0
  check "ids are unique"                         "$(b techniques | jq '[.[].id] | (length - (unique | length))')" 0
}

t_custom_techniques() {
  fresh
  b get >/dev/null
  jq '.customTechniques=[{id:"custom-slow", name:"Slow", family:"custom", tone:"info",
      defaultCycles:3, phases:[{kind:"INHALE",seconds:6,label:"In"},{kind:"EXHALE",seconds:10,label:"Out"}]}]' \
    "$OMARCHY_STATE_DIR/breathe-config.json" > "$OMARCHY_STATE_DIR/.c" \
    && mv "$OMARCHY_STATE_DIR/.c" "$OMARCHY_STATE_DIR/breathe-config.json"
  check "a custom technique joins the catalogue" "$(b techniques | jq 'length')" 13
  check "and is startable by id"                 "$(b start custom-slow | jq -r '.techniqueName')" Slow
  check "with its own cycle length"              "$(b status | jq -r '.sessionDurationMs')" 48000
}

t_unknown_technique_refused() {
  fresh
  local out rc
  out=$(b start not-a-technique 2>&1); rc=$?
  check "an unknown technique exits non-zero" "$rc" 2
  check "and says so"                         "$(grep -c 'unknown technique' <<<"$out")" 1
  check "without starting anything"           "$(sfield '.state')" IDLE
}

t_bad_cycles_refused() {
  fresh
  local rc
  b start box --cycles 0 >/dev/null 2>&1; rc=$?
  check "zero cycles is refused" "$rc" 2
  b start box --cycles abc >/dev/null 2>&1; rc=$?
  check "a non-numeric cycle count is refused" "$rc" 2
}

# ── resilience ────────────────────────────────────────────────────────
t_garbage_state_files() {
  fresh
  b get >/dev/null
  for f in breathe-session breathe-stats breathe-history; do
    echo '{{{ not json' > "$OMARCHY_STATE_DIR/$f.json"
  done
  check "a torn session file recovers to IDLE"  "$(b get | jq -r '.state')" IDLE
  check "status still answers over garbage"     "$(b status | jq -r '.state')" IDLE
  check "stats still answer over garbage"       "$(b stats | jq -r '.streak')" 0
  check "history still answers over garbage"    "$(b history | jq -r '.sessions | length')" 0
  check "and a session can still be started"    "$(b start box | jq -r '.state')" RUNNING
}

t_garbage_config() {
  fresh
  echo 'not json at all' > "$OMARCHY_STATE_DIR/breathe-config.json"
  check "a torn config is reseeded" "$(b start | jq -r '.techniqueId')" box
}

t_status_shape() {
  fresh
  b start relaxing478 --cycles 2 >/dev/null
  local out; out=$(b status)
  for key in state techniqueId techniqueName cycles phaseKind phaseLabel phaseRemainingMs \
             cycleIndex cycleCount sessionDurationMs sessionFraction done streak todaySeconds; do
    check "status exposes $key" "$(jq -r "has(\"$key\")" <<<"$out")" true
  done
  check "status reports a sane fraction" "$(jq -r '.sessionFraction <= 1 and .sessionFraction >= 0' <<<"$out")" true
}

t_silent_flag() {
  fresh
  b start box --silent >/dev/null
  check "--silent is recorded on the session" "$(sfield '.silent')" true
}

# ── loop ──────────────────────────────────────────────────────────────
t_loop_flag() {
  fresh
  b start box --loop >/dev/null
  check "--loop is recorded on the session"   "$(sfield '.loop')" true
  check "a fresh loop session has skipped nothing" "$(sfield '.skipMs')" 0
}

t_loop_defaults_from_config() {
  fresh
  b get >/dev/null
  jq '.loop=true' "$OMARCHY_STATE_DIR/breathe-config.json" > "$OMARCHY_STATE_DIR/.c" \
    && mv "$OMARCHY_STATE_DIR/.c" "$OMARCHY_STATE_DIR/breathe-config.json"
  b start box >/dev/null
  check "a bare start inherits the configured loop default" "$(sfield '.loop')" true
}

t_stop_ends_a_looping_session() {
  fresh
  b start box --cycles 2 --loop >/dev/null
  park_at 32000                       # exactly one planned pass
  b stop >/dev/null
  check "stop ends a looped session rather than rolling it" "$(sfield '.state')" DONE
  check "and the finished pass is still credited"           "$(statfield '.totals.sessions')" 1
}

t_loop_verb_toggles_the_running_session() {
  fresh
  b start box --cycles 4 >/dev/null
  check "a session starts un-looped"  "$(sfield '.loop')" false
  b loop >/dev/null
  check "the loop verb flips it on"   "$(sfield '.loop')" true
  b loop >/dev/null
  check "and flips it back off"       "$(sfield '.loop')" false
}

t_loop_verb_is_a_noop_when_idle() {
  fresh
  b loop >/dev/null
  check "the loop verb does nothing with no session" "$(sfield '.state')" IDLE
  check "and sets no stray flag"                     "$(sfield '.loop')" false
}

# The daemon's own roll path: a loop session that reaches its planned length
# while the daemon is live is credited and kept RUNNING, not parked in DONE.
# Start the clock just short of one pass with a fresh heartbeat (so `restore`
# leaves it live), then let the real daemon tick past the boundary.
t_daemon_rolls_a_loop() {
  fresh
  b get >/dev/null
  jq '.customTechniques=[{id:"custom-fast",name:"Fast",family:"custom",tone:"info",defaultCycles:2,
      phases:[{kind:"INHALE",seconds:1,label:"In"},{kind:"EXHALE",seconds:1,label:"Out"}]}]' \
    "$OMARCHY_STATE_DIR/breathe-config.json" > "$OMARCHY_STATE_DIR/.c" \
    && mv "$OMARCHY_STATE_DIR/.c" "$OMARCHY_STATE_DIR/breathe-config.json"
  b start custom-fast --cycles 2 --loop >/dev/null      # 2 x 2s = 4s a pass

  jq --argjson n "$(date +%s%3N)" '.state="RUNNING" | .elapsedMs=3600 | .savedAtMs=$n' \
    "$OMARCHY_STATE_DIR/breathe-session.json" > "$OMARCHY_STATE_DIR/.s" \
    && mv "$OMARCHY_STATE_DIR/.s" "$OMARCHY_STATE_DIR/breathe-session.json"

  timeout 3 "$CLI" __run >/dev/null 2>&1

  check "a loop pass does not park the session in DONE" "$(sfield '.state')" RUNNING
  check "the finished pass was credited to history"     "$([ "$(histfield '.sessions | length')" -ge 1 ] && echo yes)" yes
  check "the rolled pass is marked completed"           "$(histfield '.sessions[0].completed')" true
  check "and the clock was dropped back for the next pass" "$([ "$(sfield '.elapsedMs')" -lt 3600 ] && echo yes)" yes
}

# ── skip a hold ───────────────────────────────────────────────────────
t_skip_advances_a_hold() {
  fresh
  b start box --cycles 4 >/dev/null       # INHALE4 HOLD_IN4 EXHALE4 HOLD_OUT4
  park_at 5000                             # 1s into the HOLD_IN
  b skip >/dev/null
  check "skip jumps to the end of the hold"     "$(sfield '.elapsedMs')" 8000
  check "and banks the skipped milliseconds"    "$(sfield '.skipMs')" 3000
  check "the next phase is the exhale"          "$(b status | jq -r '.phaseKind')" EXHALE
}

t_skip_is_a_noop_outside_a_hold() {
  fresh
  b start box --cycles 4 >/dev/null
  park_at 1000                             # 1s into the INHALE
  local rc; b skip >/dev/null 2>&1; rc=$?
  check "skip outside a hold changes nothing" "$(sfield '.elapsedMs')" 1000
  check "and skips no time"                   "$(sfield '.skipMs')" 0
}

t_skip_refused_when_idle() {
  fresh
  b skip >/dev/null 2>&1
  check "skip on a fresh install stays IDLE" "$(sfield '.state')" IDLE
}

t_skipped_hold_time_is_not_credited_as_seconds() {
  fresh
  b start box --cycles 4 >/dev/null       # 4 x 16s = 64s planned
  park_at 4000                             # start of the HOLD_IN
  b skip >/dev/null                        # -> elapsed 8000, skipMs 4000
  park_at 40000                            # park_at preserves skipMs
  b stop >/dev/null
  check "skipped hold time is dropped from the seconds credited" "$(statfield '.totals.seconds')" 36
  check "but the cycles progressed through still count"          "$(statfield '.totals.cycles')" 2
}

for t in t_seeds_config t_config_never_mutated t_start t_start_defaults_from_config \
         t_pause_freezes t_toggle_cycles_states t_pause_resume_are_idempotent \
         t_stop_before_a_cycle_credits_nothing t_stop_after_a_cycle_credits \
         t_full_run_completes t_overrun_is_clamped t_daemon_completes_and_clamps \
         t_phase_cues_fire_once_and_do_not_stack \
         t_spoken_cues_play_words_not_the_chime t_spoken_cues_fall_back_to_chime_without_tts \
         t_never_credits_more_than_planned t_reset_credits_nothing \
         t_streak_starts_at_one t_streak_same_day_idempotent t_streak_consecutive_day \
         t_streak_gap_resets t_history_cap t_daily_cap \
         t_restore_finished_while_offline t_restore_still_live t_restore_missing_technique \
         t_restore_on_idle_is_a_noop t_techniques t_custom_techniques \
         t_unknown_technique_refused t_bad_cycles_refused \
         t_garbage_state_files t_garbage_config t_status_shape t_silent_flag \
         t_loop_flag t_loop_defaults_from_config t_stop_ends_a_looping_session \
         t_loop_verb_toggles_the_running_session t_loop_verb_is_a_noop_when_idle \
         t_daemon_rolls_a_loop t_skip_advances_a_hold t_skip_is_a_noop_outside_a_hold \
         t_skip_refused_when_idle t_skipped_hold_time_is_not_credited_as_seconds; do
  printf '\n\033[1m%s\033[0m\n' "${t#t_}"
  "$t"
done

P=$(grep -c P "$RESULTS" || true); F=$(grep -c F "$RESULTS" || true)
printf '\n%s passed, %s failed\n' "$P" "$F"
[ "$F" = 0 ]
