#!/usr/bin/env bash
# Black-box tests for ~/.local/bin/omarchy-timers — the CLI that owns
# timers.json + timers-history.json now that alteringux.timers is a thin
# watch+exec widget (see docs/adr/0006-cli-first-plugins.md).
#
#   bash test/cli.test.sh
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CLI="${OMARCHY_TIMERS_BIN:-$REPO/local-bin/omarchy-timers}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export OMARCHY_STATE_DIR="$WORK"
S="$WORK/timers.json"
H="$WORK/timers-history.json"

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }
n()      { jq -r '.entries | length' "$S"; }
e()      { jq -r ".entries[$1].$2" "$S"; }
hn()     { jq -r '.completed | length' "$H"; }

# ── add ──────────────────────────────────────────────────────────────────
"$CLI" add "draft the report"
[ "$(n)" = "1" ] && ok "add creates an entry" || bad "add" "count=$(n)"
[ "$(e 0 label)" = "draft the report" ] && ok "add stores the trimmed label" || bad "add label" "$(e 0 label)"
[[ "$(e 0 id)" =~ ^t[0-9]+-[a-z0-9]{6}$ ]] && ok "add mints a t<ms>-<rand> id" || bad "add id" "$(e 0 id)"
[ "$(e 0 accumulatedMs)" = "0" ] && ok "new entry starts with 0 banked ms" || bad "add banked" "$(e 0 accumulatedMs)"
[ "$(e 0 runningSince)" = "$(e 0 createdAt)" ] && ok "new entry is running from createdAt" || bad "add running" "rs=$(e 0 runningSince) c=$(e 0 createdAt)"

"$CLI" add "   review PR   "
[ "$(n)" = "2" ] && ok "add appends a second entry" || bad "add 2" "count=$(n)"
[ "$(e 0 label)" = "review PR" ] && ok "newest entry is first (prepended)" || bad "prepend" "$(e 0 label)"

"$CLI" add "     "
[ "$(n)" = "2" ] && ok "add ignores a whitespace-only label" || bad "add blank" "count=$(n)"

# ── rename ───────────────────────────────────────────────────────────────
id1="$(e 1 id)"
"$CLI" rename "$id1" "draft the Q3 report"
[ "$(jq -r --arg i "$id1" '.entries[] | select(.id==$i) | .label' "$S")" = "draft the Q3 report" ] \
  && ok "rename changes the label" || bad "rename" "$(cat "$S")"
"$CLI" rename "$id1" "   "
[ "$(jq -r --arg i "$id1" '.entries[] | select(.id==$i) | .label' "$S")" = "draft the Q3 report" ] \
  && ok "rename to blank is a no-op" || bad "rename blank" "$(cat "$S")"
"$CLI" rename "nonexistent" "whatever"
[ "$(n)" = "2" ] && ok "rename of an unknown id is harmless" || bad "rename unknown" "count=$(n)"

# ── pause / resume ───────────────────────────────────────────────────────
# a legacy entry running for ~10s: createdAt in the past, no runningSince key
now="$(date +%s%3N)"
jq --argjson t "$((now - 10000))" '.entries = [{id:"tlegacy-abc123", label:"old", createdAt:$t}]' "$S" > "$WORK/x" && mv "$WORK/x" "$S"
"$CLI" pause-toggle "tlegacy-abc123"
[ "$(e 0 runningSince)" = "0" ] && ok "pause clears runningSince" || bad "pause rs" "$(e 0 runningSince)"
[ "$(e 0 accumulatedMs)" -ge 9000 ] && ok "pause banks the elapsed span (~10s)" || bad "pause bank" "$(e 0 accumulatedMs)"
banked="$(e 0 accumulatedMs)"
"$CLI" pause-toggle "tlegacy-abc123"
[ "$(e 0 runningSince)" -gt 0 ] && ok "resume opens a fresh running span" || bad "resume rs" "$(e 0 runningSince)"
[ "$(e 0 accumulatedMs)" = "$banked" ] && ok "resume keeps the banked ms" || bad "resume bank" "$(e 0 accumulatedMs) != $banked"

# ── remove folds into history ────────────────────────────────────────────
echo '{"version":1,"entries":[],"__pad":0}' > "$S"
"$CLI" add "kit-selftest"
rid="$(e 0 id)"
"$CLI" remove "$rid"
[ "$(n)" = "0" ] && ok "remove drops the entry" || bad "remove" "count=$(n)"
[ "$(hn)" = "1" ] && ok "remove records a completion" || bad "remove history" "hn=$(hn)"
[ "$(jq -r '.completed[0].label' "$H")" = "kit-selftest" ] && ok "completion carries the label" || bad "completion label" "$(cat "$H")"
[ "$(jq -r '.completed[0].durationMs' "$H")" != "null" ] && ok "completion carries durationMs" || bad "completion dur" "$(cat "$H")"
"$CLI" remove "nope"
[ "$(hn)" = "1" ] && ok "remove of an unknown id records nothing" || bad "remove unknown" "hn=$(hn)"

# ── clear folds every entry ──────────────────────────────────────────────
echo '{"version":1,"entries":[]}' > "$S"
echo '{"version":1,"completed":[]}' > "$H"
"$CLI" add a; "$CLI" add b; "$CLI" add c
"$CLI" clear
[ "$(n)" = "0" ] && ok "clear empties the active list" || bad "clear" "count=$(n)"
[ "$(hn)" = "3" ] && ok "clear records a completion per entry" || bad "clear history" "hn=$(hn)"

# ── forget drops matching history entries ────────────────────────────────
echo '{"version":1,"entries":[]}' > "$S"
jq -n '{version:1, completed:[
  {label:"Kit",         startedAt:1, endedAt:2, durationMs:1},
  {label:"kit-selftest",startedAt:1, endedAt:2, durationMs:1},
  {label:"review PR",   startedAt:1, endedAt:2, durationMs:1}
]}' > "$H"
"$CLI" forget "  Kit "
[ "$(hn)" = "2" ] && ok "forget drops every matching entry (case- and space-insensitive)" || bad "forget" "$(cat "$H")"
[ "$(jq -r '[.completed[].label] | sort | join(",")' "$H")" = "kit-selftest,review PR" ] \
  && ok "forget keeps the non-matching entries" || bad "forget keeps" "$(cat "$H")"
"$CLI" forget "   "
[ "$(hn)" = "2" ] && ok "forget of a blank label is a no-op" || bad "forget blank" "$(cat "$H")"
"$CLI" forget "missing"
[ "$(hn)" = "2" ] && ok "forget of an unmatched label is a no-op" || bad "forget unmatched" "$(cat "$H")"

# ── history cap 200 ──────────────────────────────────────────────────────
jq -n '{version:1, completed:[range(0;205) | {label:"x", startedAt:1, endedAt:2, durationMs:1}]}' > "$H"
echo '{"version":1,"entries":[]}' > "$S"
"$CLI" add tail
"$CLI" remove "$(e 0 id)"
[ "$(hn)" = "200" ] && ok "history is capped at 200" || bad "history cap" "hn=$(hn)"

# ── tolerance ────────────────────────────────────────────────────────────
echo 'not json' > "$S"
"$CLI" add "recovered"
[ "$(n)" = "1" ] && ok "a malformed timers.json degrades to empty before add" || bad "malformed" "$(cat "$S")"

# ── valid JSON with malformed entry arrays sanitizes safely ───────────────
jq -n --argjson t "$now" '{version:1, entries:[
  null, "bad", {label:"valid", createdAt:$t},
  {label:"", createdAt:$t}, {label:"missing timestamp"}
]}' > "$S"
[ "$("$CLI" status | jq -r '.count')" = "1" ] \
  && ok "malformed entry array members are dropped" || bad "malformed entries" "$("$CLI" status)"
"$CLI" add "after malformed entries"
[ "$(n)" = "2" ] && ok "add survives a malformed-but-valid entry list" || bad "malformed add" "$(cat "$S")"

# ── same-ID removes serialize and record one completion ──────────────────
echo '{"version":1,"entries":[{"id":"same-id","label":"once","createdAt":1,"accumulatedMs":0,"runningSince":0}]}' > "$S"
echo '{"version":1,"completed":[]}' > "$H"
for _ in $(seq 1 8); do "$CLI" remove same-id & done
wait
[ "$(n)" = "0" ] && ok "concurrent same-ID removes leave no live timer" || bad "same-ID remove state" "$(cat "$S")"
[ "$(hn)" = "1" ] && ok "concurrent same-ID removes record once" || bad "same-ID remove history" "$(cat "$H")"

# ── clear/add share one transaction and preserve both effects ─────────────
echo '{"version":1,"entries":[{"id":"a","label":"a","createdAt":1},{"id":"b","label":"b","createdAt":1}]}' > "$S"
echo '{"version":1,"completed":[]}' > "$H"
"$CLI" clear & clear_pid=$!
"$CLI" add raced & add_pid=$!
wait "$clear_pid"
wait "$add_pid"
total=$(( $(n) + $(hn) ))
[ "$total" = "3" ] && ok "clear/add transaction preserves every timer effect" || bad "clear/add race" "active=$(n) history=$(hn)"

# ── get on a missing file ────────────────────────────────────────────────
rm -f "$S"
[ "$("$CLI" get | jq -r '.entries | length')" = "0" ] && ok "get on a missing file prints the empty default" || bad "get missing" "$("$CLI" get)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
