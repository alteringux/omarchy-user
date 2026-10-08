#!/usr/bin/env bash
# Black-box tests for ~/.local/bin/omarchy-grip — the daemon + state engine that
# owns grip-state.json / grip-tasks.json. The alteringux.grip widget is a thin
# watch+exec view (docs/adr/0006-cli-first-plugins.md).
#
# OMARCHY_GRIP_NO_DAEMON=1 stubs the systemd-run / systemctl calls; QUIET=1
# silences notify-send. Time-sensitive branches are exercised by hand-editing
# lastPromptMs / dismissStreak in the state file between calls.
#
#   bash test/cli.test.sh
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
export OMARCHY_GRIP_DIR="$REPO/plugins/alteringux.grip"
CLI="${OMARCHY_GRIP_BIN:-$REPO/local-bin/omarchy-grip}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export OMARCHY_STATE_DIR="$WORK"
export OMARCHY_GRIP_NO_DAEMON=1
export OMARCHY_GRIP_QUIET=1
STATE="$WORK/grip-state.json"
TASKS="$WORK/grip-tasks.json"
CFG="$WORK/grip-config.json"

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }
gs()  { jq -r "$1" "$STATE"; }
now_ms() { date +%s%3N; }

# ── config seeding ─────────────────────────────────────────────────────────
"$CLI" status >/dev/null
[ -f "$CFG" ] && ok "any verb seeds grip-config.json" || bad "config seed" "missing"
[ "$(jq -r '.baseIntervalMin' "$CFG")" = "20" ] && ok "seeded config defaults baseIntervalMin=20" || bad "config default" "$(cat "$CFG" 2>&1)"

# ── add / get / list ─────────────────────────────────────────────────────
id1="$("$CLI" add "call the dentist" | awk '{print $2}')"
"$CLI" add "email the landlord" >/dev/null
[ "$(jq -r '.tasks | length' "$TASKS")" = "2" ] && ok "add appends tasks" || bad "add count" "$(cat "$TASKS")"
[ "$(jq -r '.tasks[0].source' "$TASKS")" = "typed" ] && ok "added task source is 'typed'" || bad "add source" "$(cat "$TASKS")"
[ "$(jq -r '.tasks[0].done' "$TASKS")" = "false" ] && ok "added task starts open" || bad "add done" "$(cat "$TASKS")"
"$CLI" list | grep -q "call the dentist" && ok "list shows an open task" || bad "list" "$("$CLI" list)"

# ── --due rolls a stale HH:MM to tomorrow ──────────────────────────────
"$CLI" add "gym" --due 00:01 >/dev/null
gymdue="$(jq -r '.tasks[-1].due' "$TASKS")"
[ "$gymdue" -gt "$(now_ms)" ] && ok "a stale HH:MM --due rolls forward to tomorrow" || bad "due rollforward" "due=$gymdue now=$(now_ms)"

# ── done / drop ─────────────────────────────────────────────────────────
"$CLI" done "$id1" >/dev/null
[ "$(jq -r --arg i "$id1" '.tasks[] | select(.id==$i) | .done' "$TASKS")" = "true" ] && ok "done marks a task complete" || bad "done" "$(cat "$TASKS")"
"$CLI" drop "$id1" >/dev/null
[ "$(jq -r --arg i "$id1" '[.tasks[] | select(.id==$i)] | length' "$TASKS")" = "0" ] && ok "drop removes a task" || bad "drop" "$(cat "$TASKS")"

# ── on / off ───────────────────────────────────────────────────────────
"$CLI" on >/dev/null
[ "$(gs .enabled)" = "true" ] && ok "on enables the engine" || bad "on" "$(cat "$STATE")"
"$CLI" off >/dev/null
[ "$(gs .enabled)" = "false" ] && ok "off disables the engine" || bad "off" "$(cat "$STATE")"
[ "$(gs .prompt)" = "null" ] && ok "off clears any pending prompt" || bad "off prompt" "$(cat "$STATE")"

# ── tick: an empty wall never prompts ─────────────────────────────────
jq -n '{version:1,tasks:[]}' > "$TASKS"
jq '.enabled=true | .prompt=null | .lastPromptMs=0' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" tick
[ "$(gs .prompt)" = "null" ] && ok "tick with no open tasks raises nothing" || bad "empty tick" "$(cat "$STATE")"

# ── tick: open tasks + interval elapsed → check-in ────────────────────
"$CLI" add "buy milk" >/dev/null
jq '.prompt=null | .lastPromptMs=0' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" tick
[ "$(gs '.prompt.kind')" = "checkin" ] && ok "tick raises a check-in when the interval has elapsed" || bad "checkin tick" "$(cat "$STATE")"

# a second tick must not overwrite the pending prompt
"$CLI" tick
[ "$(gs '.prompt.kind')" = "checkin" ] && ok "a pending prompt is left alone by the next tick" || bad "checkin idempotent" "$(cat "$STATE")"

# ── ack checkin (plain dismiss) ──────────────────────────────────────
before_streak="$(gs .dismissStreak)"
"$CLI" ack checkin >/dev/null
[ "$(gs .prompt)" = "null" ] && ok "ack clears the prompt" || bad "ack clear" "$(cat "$STATE")"
[ "$(gs .dismissStreak)" = "$((before_streak + 1))" ] && ok "a plain check-in dismissal bumps dismissStreak" || bad "ack streak" "$(gs .dismissStreak)"
[ "$(gs .lastPromptMs)" -gt 0 ] && ok "ack stamps lastPromptMs" || bad "ack lastPrompt" "$(gs .lastPromptMs)"

# ── ack checkin --did <id> engages (streak resets, task done) ────────
milk="$(jq -r '.tasks[] | select(.text=="buy milk") | .id' "$TASKS")"
jq '.prompt={kind:"checkin",since:1} | .dismissStreak=2' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" ack checkin --did "$milk" >/dev/null
[ "$(jq -r --arg i "$milk" '.tasks[] | select(.id==$i) | .done' "$TASKS")" = "true" ] && ok "ack --did completes the task" || bad "ack did done" "$(cat "$TASKS")"
[ "$(gs .dismissStreak)" = "0" ] && ok "ack --did resets dismissStreak" || bad "ack did streak" "$(gs .dismissStreak)"

# ── ack --snooze sets the pause window ──────────────────────────────
jq '.prompt={kind:"checkin",since:1} | .pauseUntilMs=0' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
t0="$(now_ms)"
"$CLI" ack checkin --snooze 15 >/dev/null
pu="$(gs .pauseUntilMs)"
[ "$pu" -ge "$((t0 + 890000))" ] && [ "$pu" -le "$((t0 + 960000))" ] && ok "ack --snooze 15 pauses ~15m" || bad "snooze window" "delta=$((pu - t0))"

# ── ack takeover (bare) is the 10-minute escape hatch ──────────────
jq '.prompt={kind:"takeover",since:1} | .pauseUntilMs=0 | .dismissStreak=5' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
t0="$(now_ms)"
"$CLI" ack takeover >/dev/null
pu="$(gs .pauseUntilMs)"
[ "$pu" -ge "$((t0 + 560000))" ] && [ "$pu" -le "$((t0 + 660000))" ] && ok "a bare takeover ack pauses ~10m" || bad "takeover ack window" "delta=$((pu - t0))"
[ "$(gs .dismissStreak)" = "0" ] && ok "a takeover ack resets dismissStreak (you engaged)" || bad "takeover ack streak" "$(gs .dismissStreak)"

# ── pause / resume ─────────────────────────────────────────────────
jq -n '{version:1,tasks:[{id:"z1",text:"overdue thing",source:"typed",due:1,hard:false,done:false,created:0}]}' > "$TASKS"
"$CLI" pause 2h >/dev/null
[ "$(gs .prompt)" = "null" ] && ok "pause clears a pending prompt" || bad "pause prompt" "$(cat "$STATE")"
[ "$("$CLI" status | jq -r '.tone')" = "paused" ] && ok "status tone is 'paused' during a pause" || bad "pause tone" "$("$CLI" status)"
"$CLI" tick
[ "$(gs .prompt)" = "null" ] && ok "a tick during a pause raises nothing" || bad "pause tick" "$(cat "$STATE")"
"$CLI" resume >/dev/null
[ "$(gs .pauseUntilMs)" = "0" ] && ok "resume clears the pause window" || bad "resume" "$(gs .pauseUntilMs)"

# ── escalation: a hard task at/after its due time → takeover, now ──
now="$(now_ms)"
jq -n --argjson d "$((now - 10000))" '{version:1,tasks:[{id:"hard1",text:"file the taxes",source:"typed",due:$d,hard:true,done:false,created:0}]}' > "$TASKS"
jq '.enabled=true | .prompt=null | .pauseUntilMs=0 | .lastPromptMs='"$now" "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" tick
[ "$(gs '.prompt.kind')" = "takeover" ] && ok "a hard deadline fires a takeover immediately, ignoring the interval" || bad "deadline takeover" "$(cat "$STATE")"

# ── escalation: dismissed-streak → takeover once the interval is up ─
now="$(now_ms)"
jq -n '{version:1,tasks:[{id:"s1",text:"soft thing",source:"typed",due:null,hard:false,done:false,created:0}]}' > "$TASKS"
jq '.enabled=true | .prompt=null | .pauseUntilMs=0 | .dismissStreak=4 | .lastPromptMs='"$((now - 3600000))" "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" tick
[ "$(gs '.prompt.kind')" = "takeover" ] && ok "too many dismissals escalates a due prompt to a takeover" || bad "dismiss takeover" "$(cat "$STATE")"

# ── routines: seeded on a new day, preserved mid-day ──────────────
jq '.routines=[{"id":"meds","text":"Take meds"},{"id":"inbox","text":"Inbox zero"}]' "$CFG" > "$WORK/x" && mv "$WORK/x" "$CFG"
jq -n '{version:1,tasks:[]}' > "$TASKS"
jq '.enabled=true | .routinesDate="1970-01-01"' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" tick
rc="$(jq -r '[.tasks[] | select(.source=="routine")] | length' "$TASKS")"
[ "$rc" = "2" ] && ok "tick seeds one task per configured routine on a new day" || bad "routine seed" "$(cat "$TASKS")"
[ "$(gs .routinesDate)" = "$(date +%F)" ] && ok "routinesDate advances to today" || bad "routine date" "$(gs .routinesDate)"
medsid="$(jq -r '.tasks[] | select(.source=="routine" and (.text=="Take meds")) | .id' "$TASKS")"
"$CLI" done "$medsid" >/dev/null
"$CLI" tick
[ "$(jq -r --arg i "$medsid" '.tasks[] | select(.id==$i) | .done' "$TASKS")" = "true" ] && ok "a ticked routine stays ticked through a same-day re-tick" || bad "routine preserve" "$(cat "$TASKS")"

# ── tolerance: a malformed state file degrades to defaults ────────
echo 'not json at all' > "$STATE"
out="$("$CLI" status)"
[ "$(jq -r '.enabled' <<<"$out")" = "false" ] && ok "a malformed state file is read as the disabled default" || bad "malformed state" "$out"

# ── status fields ───────────────────────────────────────────────
jq -n '{version:1,tasks:[{id:"o1",text:"a",source:"typed",due:1,hard:false,done:false,created:0},{id:"o2",text:"b",source:"typed",due:null,hard:false,done:false,created:0}]}' > "$TASKS"
printf '%s\n' '{"version":1,"enabled":true,"prompt":null,"dismissStreak":0,"lastPromptMs":0,"pauseUntilMs":0,"routinesDate":""}' > "$STATE"
st="$("$CLI" status)"
[ "$(jq -r '.open' <<<"$st")" = "2" ] && ok "status counts open tasks" || bad "status open" "$st"
[ "$(jq -r '.overdue' <<<"$st")" = "1" ] && ok "status counts overdue tasks" || bad "status overdue" "$st"
[ "$(jq -r '.nextIntervalMs' <<<"$st")" != "null" ] && ok "status reports nextIntervalMs" || bad "status interval" "$st"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
