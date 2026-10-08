#!/usr/bin/env bash
# Black-box tests for ~/.local/bin/omarchy-calendar — the CLI-first calendar
# (events/blocks, birthdays, holidays) that alteringux.calendar is a thin
# view over (docs/adr/0006-cli-first-plugins.md). Network calls (holiday
# sync) and desktop side effects (notify-send, the systemd unit install, the
# agenda-refresh ping) are stubbed via a fake PATH bin dir so this runs fully
# offline and never touches the real user's state.
#
#   bash test/cli.test.sh
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CLI="${OMARCHY_CALENDAR_BIN:-$REPO/local-bin/omarchy-calendar}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
BIN="$(mktemp -d)"
FAKEHOME="$(mktemp -d)"
trap 'rm -rf "$WORK" "$BIN" "$FAKEHOME"' EXIT

export OMARCHY_STATE_DIR="$WORK/state"
export OMARCHY_CALENDAR_DIR="$WORK/calendars"
export OMARCHY_CONFIG_DIR="$WORK/config"
export PATH="$BIN:$PATH"
CALLS="$WORK/calls.log"
: > "$CALLS"

# ── stub side-effecting binaries ─────────────────────────────────────────
cat > "$BIN/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CALLS"
exit 0
EOF
cat > "$BIN/omarchy-shell" <<EOF
#!/usr/bin/env bash
printf 'omarchy-shell %s\n' "\$*" >> "$CALLS"
exit 0
EOF
# Canned Nager.Date-shaped response for any year/country asked.
cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    *publicholidays/2026/*) echo '[{"date":"2026-01-01","localName":"New Year'"'"'s Day","name":"New Year'"'"'s Day"},{"date":"2026-12-25","localName":"Christmas Day","name":"Christmas Day"}]'; exit 0 ;;
    *publicholidays/2027/*) echo '[{"date":"2027-01-01","localName":"New Year'"'"'s Day","name":"New Year'"'"'s Day"}]'; exit 0 ;;
  esac
done
exit 1
EOF
chmod +x "$BIN/notify-send" "$BIN/omarchy-shell" "$BIN/curl"

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "${2:-}"; fail=$((fail + 1)); }

# ── event: add / list / move / rm ────────────────────────────────────────
out="$("$CLI" event add "Dentist" 2026-09-10 09:30 10:00 --location "Clinic")"
[[ "$out" == *"Added event #1"* ]] && ok "event add prints the new id" || bad "event add" "$out"

json="$("$CLI" event list --json)"
echo "$json" | jq -e '.[0].title == "Dentist" and .[0].location == "Clinic"' >/dev/null \
  && ok "event list --json round-trips title/location" || bad "event list json" "$json"

"$CLI" event add "Bad" not-a-date >/dev/null 2>&1
[ "$?" != 0 ] && ok "event add rejects an invalid date" || bad "invalid date accepted"
[ "$(jq 'length' <<<"$("$CLI" event list --json)")" = "1" ] && ok "rejected add did not write a row" || bad "invalid add leaked a row"

"$CLI" event add "Bad time" 2026-09-10 25:99 >/dev/null 2>&1
[ "$?" != 0 ] && ok "event add rejects an invalid time" || bad "invalid time accepted"

"$CLI" block add 2026-09-10 14:00 15:00 "Gym" >/dev/null
[ "$(jq 'length' <<<"$("$CLI" block list --json)")" = "1" ] && ok "block add shows up in block list" || bad "block list"
[ "$(jq 'length' <<<"$("$CLI" event list --json)")" = "2" ] && ok "a block is also an entry in event list" || bad "block not in event list"

"$CLI" block add 2026-09-10 15:00 15:00 "Zero" >/dev/null 2>&1
[ "$?" != 0 ] && ok "block add rejects zero duration" || bad "zero-duration block accepted"
"$CLI" block add 2026-09-10 16:00 15:00 "Backwards" >/dev/null 2>&1
[ "$?" != 0 ] && ok "block add rejects an end before start" || bad "backwards block accepted"
[ "$(jq 'length' <<<"$("$CLI" block list --json)")" = "1" ] \
  && ok "rejected blocks do not leak rows" || bad "invalid block leaked a row"

"$CLI" event move 1 2026-09-11 11:00 11:30 >/dev/null
moved="$("$CLI" event list --json | jq -c '.[] | select(.id == 1)')"
echo "$moved" | jq -e '.date == "2026-09-11" and .start == "11:00" and .end == "11:30"' >/dev/null \
  && ok "event move updates date/start/end" || bad "event move" "$moved"

"$CLI" event move 999 2026-01-01 >/dev/null 2>&1
[ "$?" != 0 ] && ok "moving an unknown id fails" || bad "move unknown id succeeded"

"$CLI" event rm 2 >/dev/null
[ "$(jq 'length' <<<"$("$CLI" event list --json)")" = "1" ] && ok "event rm removes the row" || bad "event rm"
"$CLI" event rm 2 >/dev/null 2>&1
[ "$?" != 0 ] && ok "removing an already-gone id fails" || bad "double rm succeeded"

# ── birthdays ─────────────────────────────────────────────────────────
"$CLI" birthday add "Alice" 1990-09-10 >/dev/null
"$CLI" birthday add "Bob" 12-25 >/dev/null
"$CLI" birthday add "Nope" 13-40 >/dev/null 2>&1
[ "$?" != 0 ] && ok "birthday add rejects an invalid month/day" || bad "invalid birthday accepted"
bjson="$("$CLI" birthday list --json)"
[ "$(jq 'length' <<<"$bjson")" = "2" ] && ok "birthday list has exactly the two valid adds" || bad "birthday count" "$bjson"
echo "$bjson" | jq -e '.[0].month == 9 and .[0].day == 10 and .[0].year == 1990' >/dev/null \
  && ok "birthday keeps month/day/year" || bad "birthday fields" "$bjson"

# ── holidays (curl stubbed) ───────────────────────────────────────────
sync_out="$("$CLI" holiday sync --country AU --year 2026)"
[[ "$sync_out" == *"Synced AU"* ]] && ok "holiday sync reports success" || bad "holiday sync" "$sync_out"
hjson="$("$CLI" holiday list --json)"
echo "$hjson" | jq -e 'map(.date) | index("2026-01-01") != null' >/dev/null \
  && ok "synced holiday shows up in holiday list" || bad "holiday list" "$hjson"

# ── day / month views combine events + birthdays + holidays ───────────
dj="$("$CLI" day 2026-09-10 --json)"
echo "$dj" | jq -e '(.birthdays | length) == 1 and (.birthdays[0].age == 36)' >/dev/null \
  && ok "day view computes birthday age from the target year" || bad "day birthdays" "$dj"

mj="$("$CLI" month 2026-09 --json)"
echo "$mj" | jq -e '.days | length == 30' >/dev/null && ok "month --json has one entry per day" || bad "month days count" "$mj"
echo "$mj" | jq -e '.days[9].events == 0 and .days[9].birthdays == 1' >/dev/null \
  && ok "month --json still marks Sept 10 as Alice's birthday" || bad "month day marker (birthday)" "$mj"
echo "$mj" | jq -e '.days[10].events == 1 and .days[10].birthdays == 0' >/dev/null \
  && ok "month --json marks Sept 11 as having the moved event" || bad "month day marker (moved event)" "$mj"

month_txt="$("$CLI" month 2026-09)"
[[ "$month_txt" == *"September 2026"* ]] && ok "month text view prints the month title" || bad "month title" "$month_txt"

# ── free slots ───────────────────────────────────────────────────────
"$CLI" config set workStart 09:00 >/dev/null
"$CLI" config set workEnd 17:00 >/dev/null
"$CLI" block add 2026-09-15 09:00 12:00 "Deep work" >/dev/null
fj="$("$CLI" free 2026-09-15 --duration 60 --json)"
echo "$fj" | jq -e '.slots == [{"start":"12:00","end":"17:00"}]' >/dev/null \
  && ok "free slots excludes the busy morning block" || bad "free slots" "$fj"

fj2="$("$CLI" free 2026-09-16 --duration 30 --json)"
echo "$fj2" | jq -e '.slots == [{"start":"09:00","end":"17:00"}]' >/dev/null \
  && ok "an empty day is fully free within working hours" || bad "empty day free" "$fj2"

# ── status snapshot ─────────────────────────────────────────────────
"$CLI" status --write >/dev/null
[ -f "$OMARCHY_STATE_DIR/calendar-state.json" ] && ok "status --write creates calendar-state.json" || bad "state file missing"
st="$(cat "$OMARCHY_STATE_DIR/calendar-state.json")"
echo "$st" | jq -e 'has("today") and has("next")' >/dev/null && ok "state snapshot has today/next" || bad "state shape" "$st"
[ -f "$OMARCHY_CALENDAR_DIR/personal.ics" ] && [ -f "$OMARCHY_CALENDAR_DIR/birthdays.ics" ] && [ -f "$OMARCHY_CALENDAR_DIR/holidays.ics" ] \
  && ok "status rebuilds all three ICS exports for agenda" || bad "ICS exports missing"
grep -q "omarchy-shell alteringux.agenda refresh" "$CALLS" && ok "a mutation pings agenda to refresh" || bad "agenda not pinged"

# ── digest: idempotent per day, stubbed notify-send ────────────────────
# Add a birthday landing on *today* (whatever "today" is when this runs) so
# the assertion doesn't depend on the calendar date the suite happens to run on.
today_mmdd="$(date +%m-%d)"
"$CLI" birthday add "DigestTest" "$today_mmdd" >/dev/null

: > "$CALLS"
"$CLI" digest --force >/dev/null
grep -q "DigestTest's birthday" "$CALLS" && ok "digest fires today's birthday notification" || bad "digest birthday" "$(cat "$CALLS")"

: > "$CALLS"
"$CLI" digest >/dev/null   # no --force, same day -> should no-op via the marker
[ "$(wc -l < "$CALLS")" = "0" ] && ok "digest is a no-op the second time the same day" || bad "digest not idempotent" "$(cat "$CALLS")"

# ── config ───────────────────────────────────────────────────────────
"$CLI" config set holidayCountry NZ >/dev/null
[ "$("$CLI" config get holidayCountry)" = "NZ" ] && ok "config set/get round-trips" || bad "config roundtrip"

# ── install-timers writes real unit files, systemctl stubbed ──────────
cat > "$BIN/systemctl" <<EOF
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >> "$CALLS"
exit 0
EOF
chmod +x "$BIN/systemctl"
: > "$CALLS"
HOME="$FAKEHOME" "$CLI" install-timers >/dev/null
[ -f "$FAKEHOME/.config/systemd/user/omarchy-calendar-digest.timer" ] \
  && [ -f "$FAKEHOME/.config/systemd/user/omarchy-calendar-refresh.timer" ] \
  && ok "install-timers writes both timer units" || bad "timer units missing"
grep -q "OnCalendar=\*-\*-\* 08:00:00" "$FAKEHOME/.config/systemd/user/omarchy-calendar-digest.timer" \
  && ok "digest timer uses the configured digest time" || bad "digest time not applied"
grep -q "enable --now omarchy-calendar-digest.timer omarchy-calendar-refresh.timer" "$CALLS" \
  && ok "install-timers enables both timers" || bad "enable call missing" "$(cat "$CALLS")"
# ── Ask AI helper: success and backend failure stay observable ───────────
AI="${OMARCHY_CALENDAR_AI_BIN:-$REPO/local-bin/omarchy-calendar-ai}"
cat > "$BIN/hermes" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${AI_CALLS:?}"
printf 'Calendar helper reply\n'
EOF
chmod +x "$BIN/hermes"
AI_CALLS="$WORK/ai-calls"; export AI_CALLS
ai_out="$("$AI" "show Friday slots")"
[ "$ai_out" = "Calendar helper reply" ] && ok "Ask AI helper returns the backend answer" || bad "Ask AI helper answer" "$ai_out"
grep -q "show Friday slots" "$AI_CALLS" && ok "Ask AI helper forwards the prompt" || bad "Ask AI prompt forwarding"
cat > "$BIN/hermes" <<'EOF'
#!/usr/bin/env bash
echo "backend unavailable" >&2
exit 7
EOF
chmod +x "$BIN/hermes"
ai_err="$WORK/ai-error"
"$AI" "fail visibly" >/dev/null 2>"$ai_err"
[ "$?" != 0 ] && grep -q "hermes exited 7" "$ai_err" \
  && ok "Ask AI helper exposes backend failures" || bad "Ask AI failure visibility" "$(cat "$ai_err")"

# ── summary ─────────────────────────────────────────────────────────
echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
