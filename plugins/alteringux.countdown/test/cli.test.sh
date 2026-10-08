#!/usr/bin/env bash
# Black-box tests for ~/.local/bin/omarchy-countdowns — the CLI that owns
# countdowns.json + countdown-history.json now that alteringux.countdown is a
# thin watch+exec widget (see docs/adr/0006-cli-first-plugins.md).
#
#   bash test/cli.test.sh
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CLI="${OMARCHY_COUNTDOWNS_BIN:-$REPO/local-bin/omarchy-countdowns}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export OMARCHY_STATE_DIR="$WORK"
S="$WORK/countdowns.json"
H="$WORK/countdown-history.json"

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }
n()  { jq -r '.entries | length' "$S"; }
e()  { jq -r ".entries[$1].$2" "$S"; }
hn() { jq -r '.added | length' "$H"; }

TOMORROW="$(date -d tomorrow +%F)"
TODAY="$(date +%F)"
YESTERDAY="$(date -d yesterday +%F)"

# ── add <days> <label...> ────────────────────────────────────────────────
"$CLI" add 21 Disneyland trip
[ "$(n)" = "1" ] && ok "add creates an entry" || bad "add" "count=$(n)"
[ "$(e 0 label)" = "Disneyland trip" ] && ok "add joins the rest of argv as the label" || bad "add label" "$(e 0 label)"
[[ "$(e 0 id)" =~ ^c[0-9]+-[a-z0-9]{6}$ ]] && ok "add mints a c<ms>-<rand> id" || bad "add id" "$(e 0 id)"
[ "$(e 0 targetEpoch)" -gt "$(date +%s000)" ] && ok "targetEpoch is in the future" || bad "add target" "$(e 0 targetEpoch)"
[ "$(hn)" = "1" ] && ok "add records into the history log" || bad "add history" "hn=$(hn)"
[ "$(jq -r '.added[0].days' "$H")" = "21" ] && ok "history remembers the day count" || bad "history days" "$(cat "$H")"

sd="$("$CLI" status | jq -r '.soonestDays')"
[ "$sd" = "21" ] && ok "status.soonestDays derives 21 whole days from the target" || bad "soonestDays" "got $sd"

"$CLI" add 90 Move house
[ "$(e 0 label)" = "Move house" ] && ok "newest entry is first (prepended)" || bad "prepend" "$(e 0 label)"
[ "$(n)" = "2" ] && ok "second add appends" || bad "add 2" "count=$(n)"

"$CLI" add 0 zero days
[ "$(n)" = "2" ] && ok "add with days < 1 is a no-op" || bad "add zero" "count=$(n)"
"$CLI" add 5
[ "$(n)" = "2" ] && ok "add with no label is a no-op" || bad "add nolabel" "count=$(n)"

# ── add-at <yyyy-mm-dd> <label...> ───────────────────────────────────────
"$CLI" add-at "$TOMORROW" Dentist appointment
[ "$(n)" = "3" ] && ok "add-at with a future date creates an entry" || bad "add-at" "count=$(n)"
[ "$(e 0 label)" = "Dentist appointment" ] && ok "add-at stores the label" || bad "add-at label" "$(e 0 label)"
[ "$("$CLI" status | jq -r '.soonestDays')" = "1" ] && ok "add-at tomorrow reads as 1 day" || bad "add-at days" "$("$CLI" status)"
"$CLI" add-at "$TODAY" Today no good
[ "$(n)" = "3" ] && ok "add-at today is rejected (not strictly future)" || bad "add-at today" "count=$(n)"
"$CLI" add-at "$YESTERDAY" In the past
[ "$(n)" = "3" ] && ok "add-at a past date is rejected" || bad "add-at past" "count=$(n)"

# ── rename ───────────────────────────────────────────────────────────────
id="$(e 2 id)"
"$CLI" rename "$id" Disneyland with the kids
[ "$(jq -r --arg i "$id" '.entries[]|select(.id==$i)|.label' "$S")" = "Disneyland with the kids" ] \
  && ok "rename changes the label" || bad "rename" "$(cat "$S")"
"$CLI" rename "$id" "   "
[ "$(jq -r --arg i "$id" '.entries[]|select(.id==$i)|.label' "$S")" = "Disneyland with the kids" ] \
  && ok "rename to blank is a no-op" || bad "rename blank" "$(cat "$S")"
"$CLI" rename bogus whatever
[ "$(n)" = "3" ] && ok "rename of an unknown id is harmless" || bad "rename unknown" "count=$(n)"

# ── remove ───────────────────────────────────────────────────────────────
before_hn="$(hn)"
"$CLI" remove "$id"
[ "$(n)" = "2" ] && ok "remove drops the entry" || bad "remove" "count=$(n)"
[ "$(hn)" = "$before_hn" ] && ok "remove does not touch the history log" || bad "remove history" "hn=$(hn)"
"$CLI" remove nope
[ "$(n)" = "2" ] && ok "remove of an unknown id is harmless" || bad "remove unknown" "count=$(n)"

# ── forget <label...> ───────────────────────────────────────────────────
echo '{"version":1,"added":[
  {"label":"Gym","days":1,"addedAt":1},
  {"label":"gym","days":2,"addedAt":2},
  {"label":"Trip","days":10,"addedAt":3}]}' > "$H"
"$CLI" forget GYM
[ "$(hn)" = "1" ] && ok "forget drops every matching label (case-insensitive)" || bad "forget" "$(cat "$H")"
[ "$(jq -r '.added[0].label' "$H")" = "Trip" ] && ok "forget keeps the non-matching labels" || bad "forget keep" "$(cat "$H")"

# ── clear ────────────────────────────────────────────────────────────────
"$CLI" clear
[ "$(n)" = "0" ] && ok "clear empties the active list" || bad "clear" "count=$(n)"
[ "$(hn)" = "1" ] && ok "clear does not touch the history log" || bad "clear history" "hn=$(hn)"

# ── history cap 200 ─────────────────────────────────────────────────────
jq -n '{version:1, added:[range(0;205) | {label:"x", days:1, addedAt:1}]}' > "$H"
"$CLI" add 3 capped
[ "$(hn)" = "200" ] && ok "history is capped at 200" || bad "history cap" "hn=$(hn)"

# ── tolerance ─────────────────────────────────────────────────────────────
echo 'nope' > "$S"
"$CLI" add 4 recovered
[ "$(n)" = "1" ] && ok "a malformed countdowns.json degrades to empty before add" || bad "malformed" "$(cat "$S")"

rm -f "$S"
[ "$("$CLI" get | jq -r '.entries|length')" = "0" ] && ok "get on a missing file prints the empty default" || bad "get missing" "$("$CLI" get)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
