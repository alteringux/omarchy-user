#!/usr/bin/env bash
# Black-box tests for ~/.local/bin/omarchy-recall — the daemon + SRS/intrusion
# engine that owns recall-cards.json / recall-state.json. The alteringux.recall
# widget is a thin watch+exec view (docs/adr/0006-cli-first-plugins.md).
#
# OMARCHY_RECALL_NO_DAEMON=1 stubs the systemd-run / systemctl calls; QUIET=1
# silences notify-send. Time-sensitive branches are exercised by hand-editing
# lastPromptMs / dismissStreak / dueAt in the state/cards files between calls.
#
#   bash test/cli.test.sh
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CLI="${OMARCHY_RECALL_BIN:-$REPO/local-bin/omarchy-recall}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export OMARCHY_STATE_DIR="$WORK"
export OMARCHY_RECALL_NO_DAEMON=1
export OMARCHY_RECALL_QUIET=1
STATE="$WORK/recall-state.json"
CARDS="$WORK/recall-cards.json"
CFG="$WORK/recall-config.json"

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }
gs()  { jq -r "$1" "$STATE"; }
now_ms() { date +%s%3N; }

# ── config + card seeding ────────────────────────────────────────────────
"$CLI" status >/dev/null
[ -f "$CFG" ] && ok "any verb seeds recall-config.json" || bad "config seed" "missing"
[ "$(jq -r '.dailyNewLessonCap' "$CFG")" = "1" ] && ok "seeded config defaults dailyNewLessonCap=1" || bad "config default" "$(cat "$CFG" 2>&1)"

"$CLI" get >/dev/null
[ -f "$CARDS" ] && ok "get seeds recall-cards.json" || bad "cards seed" "missing"
seeded="$(jq '.cards | length' "$CARDS")"
[ "$seeded" -gt 10 ] && ok "seed deck has lessons + trivia ($seeded cards)" || bad "seed count" "$seeded"
[ "$(jq '[.cards[] | select(.kind=="lesson")] | length' "$CARDS")" -gt 0 ] && ok "seed deck includes lesson cards" || bad "seed lessons" "$(cat "$CARDS")"

# ── add-quiz / add-lesson / drop ─────────────────────────────────────────
id1="$("$CLI" add-quiz "2+2=?" "4" --category custom | awk '{print $2}')"
[ "$(jq -r --arg i "$id1" '.cards[] | select(.id==$i) | .front' "$CARDS")" = "2+2=?" ] && ok "add-quiz appends a quiz card" || bad "add-quiz" "$(cat "$CARDS")"
[ "$(jq -r --arg i "$id1" '.cards[] | select(.id==$i) | .dueAt' "$CARDS")" = "0" ] && ok "a brand-new quiz card is due immediately (dueAt=0)" || bad "add-quiz due" "$(cat "$CARDS")"

lid="$("$CLI" add-lesson "Test Lesson" "slide one" "slide two" | awk '{print $2}')"
slides="$(jq -c --arg i "$lid" '.cards[] | select(.id==$i) | .slides' "$CARDS")"
[ "$slides" = '["slide one","slide two"]' ] && ok "add-lesson stores slides in order" || bad "add-lesson slides" "$slides"

"$CLI" drop "$id1" >/dev/null
[ "$(jq -r --arg i "$id1" '[.cards[] | select(.id==$i)] | length' "$CARDS")" = "0" ] && ok "drop removes a card" || bad "drop" "$(cat "$CARDS")"

# ── grade ────────────────────────────────────────────────────────────────
qid="$(jq -r '.cards[] | select(.kind=="quiz") | .id' "$CARDS" | head -1)"
"$CLI" grade "$qid" good >/dev/null
[ "$(jq -r --arg i "$qid" '.cards[] | select(.id==$i) | .reps' "$CARDS")" = "1" ] && ok "grade good increments reps" || bad "grade reps" "$(cat "$CARDS")"
duea="$(jq -r --arg i "$qid" '.cards[] | select(.id==$i) | .dueAt' "$CARDS")"
[ "$duea" -gt "$(now_ms)" ] && ok "grade good pushes dueAt into the future" || bad "grade due" "$duea"

# ── on / off ─────────────────────────────────────────────────────────────
"$CLI" on >/dev/null
[ "$(jq -r '.enabled' "$CFG")" = "true" ] && ok "on enables the engine" || bad "on" "$(cat "$CFG")"
"$CLI" off >/dev/null
[ "$(jq -r '.enabled' "$CFG")" = "false" ] && ok "off disables the engine" || bad "off" "$(cat "$CFG")"
[ "$(gs .prompt)" = "null" ] && ok "off clears any pending prompt" || bad "off prompt" "$(cat "$STATE")"

# ── tick: an unseen lesson always wins, and always takes over ───────────
jq '.enabled=true' "$CFG" > "$WORK/x" && mv "$WORK/x" "$CFG"
jq '.prompt=null | .lastLessonMs=0 | .lessonsToday=0 | .lessonsTodayDate=""' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" tick
[ "$(gs '.prompt.kind')" = "lesson" ] && ok "tick raises a lesson takeover when one is unseen" || bad "lesson tick" "$(cat "$STATE")"
[ "$(gs '.lessonsToday')" = "1" ] && ok "raising a lesson bumps lessonsToday" || bad "lessonsToday" "$(gs .lessonsToday)"

# a second tick must not overwrite the pending prompt
"$CLI" tick
[ "$(gs '.prompt.kind')" = "lesson" ] && ok "a pending prompt is left alone by the next tick" || bad "lesson idempotent" "$(cat "$STATE")"

# ── lesson-seen spins up a linked companion quiz ─────────────────────────
first_lesson="$(gs '.prompt.cardIds[0]')"
"$CLI" lesson-seen "$first_lesson" >/dev/null
[ "$(jq -r --arg i "$first_lesson" '.cards[] | select(.linkedLessonId==$i) | .kind' "$CARDS")" = "quiz" ] && ok "lesson-seen creates a linked companion quiz card" || bad "companion card" "$(cat "$CARDS")"

# ── ack lesson (always engages: resets dismissStreak) ────────────────────
jq '.dismissStreak=3' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" ack lesson >/dev/null
[ "$(gs .prompt)" = "null" ] && ok "ack clears the prompt" || bad "ack clear" "$(cat "$STATE")"
[ "$(gs .dismissStreak)" = "0" ] && ok "ack lesson resets dismissStreak" || bad "ack lesson streak" "$(gs .dismissStreak)"
[ "$(gs .lastPromptMs)" -gt 0 ] && ok "ack stamps lastPromptMs" || bad "ack lastPrompt" "$(gs .lastPromptMs)"

# ── a second, cap-rationed lesson does not fire the same day ────────────
jq '.prompt=null' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" tick
[ "$(gs '.prompt')" != "null" ] && [ "$(gs '.prompt.kind')" = "lesson" ] && bad "lesson cap" "a second lesson fired same-day despite dailyNewLessonCap=1" || ok "dailyNewLessonCap rations lessons to one per day"

# ── ack checkin: plain dismiss bumps streak, --engaged resets it ────────
jq -n '{version:1,cards:[{id:"c1",kind:"quiz",category:"custom",title:null,slides:null,front:"f",back:"b",image:null,linkedLessonId:null,createdAt:0,ease:2.5,intervalDays:0,dueAt:0,reps:0,lapses:0,lastGrade:null,shownAt:null}]}' > "$CARDS"
jq '.prompt={kind:"checkin",cardIds:["c1"],reason:"due"} | .dismissStreak=0' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" ack checkin >/dev/null
[ "$(gs .dismissStreak)" = "1" ] && ok "a plain check-in dismissal bumps dismissStreak" || bad "ack streak" "$(gs .dismissStreak)"

jq '.prompt={kind:"checkin",cardIds:["c1"],reason:"due"} | .dismissStreak=2' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" ack checkin --engaged >/dev/null
[ "$(gs .dismissStreak)" = "0" ] && ok "ack --engaged resets dismissStreak" || bad "ack engaged streak" "$(gs .dismissStreak)"

# ── ack --snooze sets the pause window ──────────────────────────────────
jq '.prompt={kind:"checkin",cardIds:["c1"],reason:"due"} | .pauseUntilMs=0' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
t0="$(now_ms)"
"$CLI" ack checkin --snooze 15 >/dev/null
pu="$(gs .pauseUntilMs)"
[ "$pu" -ge "$((t0 + 890000))" ] && [ "$pu" -le "$((t0 + 960000))" ] && ok "ack --snooze 15 pauses ~15m" || bad "snooze window" "delta=$((pu - t0))"

# ── pause / resume ───────────────────────────────────────────────────────
"$CLI" pause 2h >/dev/null
[ "$(gs .prompt)" = "null" ] && ok "pause clears a pending prompt" || bad "pause prompt" "$(cat "$STATE")"
"$CLI" tick
[ "$(gs .prompt)" = "null" ] && ok "a tick during a pause raises nothing" || bad "pause tick" "$(cat "$STATE")"
"$CLI" resume >/dev/null
[ "$(gs .pauseUntilMs)" = "0" ] && ok "resume clears the pause window" || bad "resume" "$(gs .pauseUntilMs)"

# ── escalation: a stale, previously-graded card → takeover once due ─────
now="$(now_ms)"
jq -n --argjson d "$((now - 9 * 3600000))" \
  '{version:1,cards:[{id:"stale1",kind:"quiz",category:"custom",title:null,slides:null,front:"old",back:"b",image:null,linkedLessonId:null,createdAt:0,ease:2.5,intervalDays:5,dueAt:$d,reps:3,lapses:0,lastGrade:"good",shownAt:1}]}' > "$CARDS"
jq '.enabled=true | .overdueTakeoverHours=8' "$CFG" > "$WORK/x" && mv "$WORK/x" "$CFG"
jq '.prompt=null | .pauseUntilMs=0 | .dismissStreak=0 | .lastPromptMs=0 | .lastLessonMs=0 | .lessonsToday=99' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" tick
[ "$(gs '.prompt.kind')" = "takeover" ] && ok "a stale, previously-graded card escalates to a takeover" || bad "overdue takeover" "$(cat "$STATE")"

# ── regression: a brand-new due card never escalates to takeover alone ──
jq -n '{version:1,cards:[{id:"new1",kind:"quiz",category:"custom",title:null,slides:null,front:"new",back:"b",image:null,linkedLessonId:null,createdAt:0,ease:2.5,intervalDays:0,dueAt:0,reps:0,lapses:0,lastGrade:null,shownAt:null}]}' > "$CARDS"
jq '.prompt=null | .lastPromptMs=0 | .dismissStreak=0 | .lessonsToday=99' "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" tick
[ "$(gs '.prompt.kind')" = "checkin" ] && ok "a brand-new due card alone raises a check-in, not a takeover" || bad "new-card no-escalate" "$(cat "$STATE")"

# ── escalation: dismissed-streak → takeover once the interval is up ─────
jq -n '{version:1,cards:[{id:"s1",kind:"quiz",category:"custom",title:null,slides:null,front:"soft",back:"b",image:null,linkedLessonId:null,createdAt:0,ease:2.5,intervalDays:0,dueAt:0,reps:0,lapses:0,lastGrade:null,shownAt:null}]}' > "$CARDS"
now="$(now_ms)"
jq '.enabled=true | .prompt=null | .pauseUntilMs=0 | .dismissStreak=4 | .lessonsToday=99 | .lastPromptMs='"$((now - 3600000))" "$STATE" > "$WORK/x" && mv "$WORK/x" "$STATE"
"$CLI" tick
[ "$(gs '.prompt.kind')" = "takeover" ] && ok "too many dismissals escalates a due prompt to a takeover" || bad "dismiss takeover" "$(cat "$STATE")"

# ── seed-trivia: adds the curated set, idempotent on a second run ───────
jq -n '{version:1,cards:[]}' > "$CARDS"
out1="$("$CLI" seed-trivia)"
n1="$(jq '.cards | length' "$CARDS")"
echo "$out1" | grep -q "seeded $n1 new trivia" && ok "seed-trivia adds the curated trivia set" || bad "seed-trivia first run" "$out1 / count=$n1"
[ "$n1" -gt 0 ] && ok "seed-trivia populated a non-empty deck" || bad "seed-trivia count" "$n1"

out2="$("$CLI" seed-trivia)"
n2="$(jq '.cards | length' "$CARDS")"
[ "$n2" = "$n1" ] && ok "seed-trivia is a no-op on cards already present" || bad "seed-trivia idempotent count" "$n1 -> $n2"
echo "$out2" | grep -q "already fully present" && ok "seed-trivia reports nothing-to-add on a repeat run" || bad "seed-trivia repeat message" "$out2"

# a custom card with an unrelated id survives a reseed untouched
"$CLI" add-quiz "my own question" "my own answer" --category custom >/dev/null
"$CLI" seed-trivia >/dev/null
[ "$(jq '[.cards[] | select(.front=="my own question")] | length' "$CARDS")" = "1" ] && ok "seed-trivia never touches unrelated existing cards" || bad "seed-trivia preserves custom" "$(cat "$CARDS")"

# ── stats / list smoke ───────────────────────────────────────────────────
"$CLI" stats | jq -e '.totalCards >= 1' >/dev/null && ok "stats returns a usable summary" || bad "stats" "$("$CLI" stats)"
"$CLI" list >/dev/null && ok "list runs without error" || bad "list" "failed"

echo
echo "recall cli.test.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
