#!/usr/bin/env bash
# Black-box tests for ~/.local/bin/omarchy-pomodoro — the daemon + state engine
# that owns pomodoro-session.json / -stats.json / -history.json now that
# alteringux.pomodoro is a thin watch+exec widget (docs/adr/0006-cli-first-plugins.md).
#
# OMARCHY_POMODORO_NO_DAEMON=1 stubs out the systemd-run / systemctl calls so
# only the pure state transitions are exercised here.
#
#   bash test/cli.test.sh
set -uo pipefail

CLI="${OMARCHY_POMODORO_BIN:-$HOME/.local/bin/omarchy-pomodoro}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export OMARCHY_STATE_DIR="$WORK"
export OMARCHY_POMODORO_NO_DAEMON=1
export OMARCHY_POMODORO_QUIET=1   # no notify-send / sound during tests
SESS="$WORK/pomodoro-session.json"
STATS="$WORK/pomodoro-stats.json"
HIST="$WORK/pomodoro-history.json"
CFG="$WORK/pomodoro-config.json"

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }
sj() { jq -r "$1" "$SESS"; }
today="$(date +%F)"
yesterday="$(date -d yesterday +%F)"

# ── config seeding ───────────────────────────────────────────────────────
"$CLI" get >/dev/null
[ -f "$CFG" ] && ok "any verb seeds pomodoro-config.json" || bad "config seed" "missing"
[ "$(jq -r '.workMinutes' "$CFG")" = "25" ] && ok "seeded config defaults workMinutes to 25" || bad "config default" "$(cat "$CFG" 2>&1)"
[ "$(jq -r '.dailyGoalMinutes' "$CFG")" = "480" ] && ok "seeded config defaults daily goal to 8 hours" || bad "daily goal default" "$(cat "$CFG" 2>&1)"

# ── toggle from IDLE starts WORK ─────────────────────────────────────────
"$CLI" toggle
[ "$(sj .phase)" = "WORK" ] && ok "toggle from IDLE enters WORK" || bad "start phase" "$(sj .phase)"
[ "$(sj .running)" = "true" ] && ok "WORK starts running" || bad "start running" "$(sj .running)"
[ "$(sj .remainingMs)" = "1500000" ] && ok "WORK remaining = 25*60000" || bad "start remaining" "$(sj .remainingMs)"
[ "$(sj .savedAtMs)" -gt 0 ] && ok "savedAtMs is stamped" || bad "start savedAt" "$(sj .savedAtMs)"

# ── toggle pauses / resumes ─────────────────────────────────────────────
"$CLI" toggle
[ "$(sj .running)" = "false" ] && ok "toggle while running pauses" || bad "pause" "$(sj .running)"
[ "$(sj .phase)" = "WORK" ] && ok "pause keeps the phase" || bad "pause phase" "$(sj .phase)"
"$CLI" toggle
[ "$(sj .running)" = "true" ] && ok "toggle while paused resumes" || bad "resume" "$(sj .running)"

# ── resume verb on an already-running session is a no-op ────────────────
# Regression: cmd_resume used to unconditionally re-stamp savedAtMs to now
# while leaving remainingMs anchored to the old savedAtMs, silently gifting
# the phase whatever time had elapsed since that anchor.
before_rem="$(sj .remainingMs)"
before_saved="$(sj .savedAtMs)"
sleep 1.1
"$CLI" resume
[ "$(sj .running)" = "true" ] && ok "resume on a running session stays running" || bad "resume-running state" "$(sj .running)"
[ "$(sj .remainingMs)" = "$before_rem" ] && ok "resume on a running session doesn't touch remainingMs" || bad "resume-running remainingMs" "$before_rem -> $(sj .remainingMs)"
[ "$(sj .savedAtMs)" = "$before_saved" ] && ok "resume on a running session doesn't re-stamp savedAtMs" || bad "resume-running savedAtMs" "$before_saved -> $(sj .savedAtMs)"

# ── skip: transition without crediting ─────────────────────────────────
echo '{"version":1,"sessions":[]}' > "$HIST"
"$CLI" skip
[ "$(sj .phase)" = "SHORT_BREAK" ] && ok "skip from WORK (0 done) -> SHORT_BREAK" || bad "skip phase" "$(sj .phase)"
[ "$(sj .ready)" = "true" ] && ok "skipped-into phase is 'ready'" || bad "skip ready" "$(sj .ready)"
[ "$(sj .running)" = "false" ] && ok "skipped-into phase is not running" || bad "skip running" "$(sj .running)"
[ "$(sj .completedPomodorosThisSession)" = "0" ] && ok "skip does not count a pomodoro" || bad "skip count" "$(sj .completedPomodorosThisSession)"
[ "$(jq -r '.sessions[-1].completed' "$HIST")" = "false" ] && ok "skip records an interrupted WORK session" || bad "skip history" "$(cat "$HIST")"
[ "$(jq -r '.sessions[-1].minutes' "$HIST")" = "25" ] && ok "history session carries the configured minutes" || bad "skip minutes" "$(cat "$HIST")"

# ── complete: transition + credit ─────────────────────────────────────
echo '{"version":1,"streak":2,"lastActiveDate":"'"$yesterday"'","daily":{}}' > "$STATS"
echo '{"version":1,"sessions":[]}' > "$HIST"
jq '.phase="WORK" | .running=false | .ready=false | .completedPomodorosThisSession=3 | .focusedMs=1500000 | .savedAtMs=(now*1000|floor)' "$SESS" > "$WORK/x" && mv "$WORK/x" "$SESS"
"$CLI" complete
[ "$(sj .phase)" = "LONG_BREAK" ] && ok "complete of the 4th WORK -> LONG_BREAK" || bad "complete phase" "$(sj .phase)"
[ "$(sj .completedPomodorosThisSession)" = "4" ] && ok "complete counts the pomodoro" || bad "complete count" "$(sj .completedPomodorosThisSession)"
[ "$(jq -r --arg d "$today" '.daily[$d].completed' "$STATS")" = "1" ] && ok "complete credits today's completed count" || bad "credit completed" "$(cat "$STATS")"
[ "$(jq -r --arg d "$today" '.daily[$d].focusedMs' "$STATS")" = "1500000" ] && ok "complete credits focusedMs" || bad "credit focused" "$(cat "$STATS")"
[ "$(jq -r '.streak' "$STATS")" = "3" ] && ok "streak increments when yesterday was the last active day" || bad "streak inc" "$(jq -r '.streak' "$STATS")"
[ "$(jq -r '.lastActiveDate' "$STATS")" = "$today" ] && ok "lastActiveDate advances to today" || bad "lastActive" "$(cat "$STATS")"
[ "$(jq -r '.sessions[-1].completed' "$HIST")" = "true" ] && ok "complete records a finished WORK session" || bad "complete history" "$(cat "$HIST")"

# ── streak: same-day repeat holds, gap resets ─────────────────────────
echo '{"version":1,"streak":5,"lastActiveDate":"'"$today"'","daily":{}}' > "$STATS"
jq '.phase="WORK" | .running=true | .ready=false | .completedPomodorosThisSession=0' "$SESS" > "$WORK/x" && mv "$WORK/x" "$SESS"
"$CLI" complete
[ "$(jq -r '.streak' "$STATS")" = "5" ] && ok "a second completion the same day does not bump the streak" || bad "streak hold" "$(jq -r '.streak' "$STATS")"
echo '{"version":1,"streak":9,"lastActiveDate":"2020-01-01","daily":{}}' > "$STATS"
jq '.phase="WORK" | .running=true | .ready=false | .completedPomodorosThisSession=0' "$SESS" > "$WORK/x" && mv "$WORK/x" "$SESS"
"$CLI" complete
[ "$(jq -r '.streak' "$STATS")" = "1" ] && ok "a gap in activity resets the streak to 1" || bad "streak reset" "$(jq -r '.streak' "$STATS")"

# ── reset ────────────────────────────────────────────────────────────
echo '{"version":1,"sessions":[]}' > "$HIST"
jq '.phase="WORK" | .running=true | .ready=false' "$SESS" > "$WORK/x" && mv "$WORK/x" "$SESS"
"$CLI" reset
[ "$(sj .phase)" = "IDLE" ] && ok "reset returns to IDLE" || bad "reset phase" "$(sj .phase)"
[ "$(sj .running)" = "false" ] && ok "reset clears running" || bad "reset running" "$(sj .running)"
[ "$(sj .completedPomodorosThisSession)" = "0" ] && ok "reset clears the session pomodoro count" || bad "reset count" "$(sj .completedPomodorosThisSession)"
[ "$(jq -r '.sessions[-1].completed' "$HIST")" = "false" ] && ok "reset out of a live WORK phase records it as interrupted" || bad "reset history" "$(cat "$HIST")"

# ── restore: a WORK block that ran out while the shell was down ────────
echo '{"version":1,"streak":0,"lastActiveDate":"","daily":{}}' > "$STATS"
echo '{"version":1,"sessions":[]}' > "$HIST"
past=$(( $(date +%s%3N) - 60000 ))
jq -n --argjson p "$past" '{version:1, phase:"WORK", running:true, ready:false, remainingMs:1000, elapsedReadyMs:0, completedPomodorosThisSession:0, savedAtMs:$p}' > "$SESS"
"$CLI" restore
[ "$(sj .phase)" = "SHORT_BREAK" ] && ok "restore lands in the next phase for a block that expired offline" || bad "restore phase" "$(sj .phase)"
[ "$(sj .ready)" = "true" ] && ok "restore marks the next phase ready" || bad "restore ready" "$(sj .ready)"
[ "$(sj .completedPomodorosThisSession)" = "1" ] && ok "restore credits the offline pomodoro" || bad "restore count" "$(sj .completedPomodorosThisSession)"
[ "$(jq -r --arg d "$today" '.daily[$d].completed' "$STATS")" = "1" ] && ok "restore credits stats for the offline block" || bad "restore stats" "$(cat "$STATS")"
[ "$(jq -r '.sessions[-1].completed' "$HIST")" = "true" ] && ok "restore records the offline block in history" || bad "restore history" "$(cat "$HIST")"

# ── restore: still-running block just loses the downtime ──────────────
now3=$(date +%s%3N)
jq -n --argjson n "$((now3 - 5000))" '{version:1, phase:"WORK", running:true, ready:false, remainingMs:600000, elapsedReadyMs:0, completedPomodorosThisSession:2, savedAtMs:$n}' > "$SESS"
"$CLI" restore
[ "$(sj .phase)" = "WORK" ] && ok "restore keeps a block that still has time left" || bad "restore keep phase" "$(sj .phase)"
[ "$(sj .running)" = "true" ] && ok "restore keeps it running" || bad "restore keep running" "$(sj .running)"
rem="$(sj .remainingMs)"
[ "$rem" -ge 590000 ] && [ "$rem" -le 599000 ] && ok "restore subtracts the downtime (~5s)" || bad "restore downtime" "remaining=$rem"

# ── daily-stats retention (90 days) ─────────────────────────────────
jq -n '{version:1, streak:1, lastActiveDate:"", daily:( [range(0;95) | {("2020-01-" + (.+1|tostring)): {completed:1, focusedMs:1}}] | add )}' > "$STATS"
jq '.phase="WORK" | .running=true | .ready=false | .completedPomodorosThisSession=0' "$SESS" > "$WORK/x" && mv "$WORK/x" "$SESS"
"$CLI" complete
[ "$(jq -r '.daily | length' "$STATS")" -le 90 ] && ok "daily buckets are trimmed to the 90-day window" || bad "daily trim" "$(jq -r '.daily|length' "$STATS")"

# ── history retention (200) ────────────────────────────────────────
jq -n '{version:1, sessions:[range(0;205) | {minutes:25, completed:true, date:"2020-01-01"}]}' > "$HIST"
jq '.phase="WORK" | .running=true | .ready=false | .completedPomodorosThisSession=0' "$SESS" > "$WORK/x" && mv "$WORK/x" "$SESS"
"$CLI" skip
[ "$(jq -r '.sessions | length' "$HIST")" = "200" ] && ok "session history is capped at 200" || bad "history cap" "$(jq -r '.sessions|length' "$HIST")"

# ── tolerance ──────────────────────────────────────────────────────
echo 'not json' > "$SESS"
"$CLI" toggle
[ "$(sj .phase)" = "WORK" ] && ok "a malformed session file degrades to IDLE before the verb" || bad "malformed" "$(cat "$SESS")"

# ── status ────────────────────────────────────────────────────────
st="$("$CLI" status)"
[ "$(jq -r '.phase' <<<"$st")" = "WORK" ] && ok "status reports the phase" || bad "status phase" "$st"
[ "$(jq -r '.remainingMs' <<<"$st")" != "null" ] && ok "status reports a live remainingMs" || bad "status remaining" "$st"
[ "$(jq -r '.dailyGoalMs' <<<"$st")" = "28800000" ] && ok "status reports the configured daily goal" || bad "status daily goal" "$st"
[ "$(jq -r '.goalRemainingMs' <<<"$st")" != "null" ] && ok "status reports remaining daily focus" || bad "status goal remaining" "$st"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
