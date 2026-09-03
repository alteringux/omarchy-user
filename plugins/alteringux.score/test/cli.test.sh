#!/usr/bin/env bash
# Black-box tests for ~/.local/bin/omarchy-score — the CLI that owns
# score-state.json now that alteringux.score is a thin watch+exec widget
# (see docs/adr/0006-cli-first-plugins.md).
#
#   bash test/cli.test.sh
set -uo pipefail

CLI="${OMARCHY_SCORE_BIN:-$HOME/.local/bin/omarchy-score}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export OMARCHY_STATE_DIR="$WORK"

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }

score() { jq -r '.score' "$WORK/score-state.json"; }
hlen()  { jq -r '.history | length' "$WORK/score-state.json"; }
hlast() { jq -r ".history[-1].$1" "$WORK/score-state.json"; }

# ── config seeding ───────────────────────────────────────────────────────
"$CLI" get >/dev/null
[ -f "$WORK/score-config.json" ] \
  && ok "get seeds score-config.json" \
  || bad "config seed" "file missing"
[ "$(jq -r '.step' "$WORK/score-config.json")" = "1" ] \
  && ok "seeded config defaults step to 1" \
  || bad "config step" "$(cat "$WORK/score-config.json" 2>&1)"

# ── increment / decrement ────────────────────────────────────────────────
"$CLI" increment
[ "$(score)" = "1" ] && ok "increment: 0 -> 1" || bad "increment" "score=$(score)"
[ "$(hlast action)" = "increment" ] && ok "increment logs a history entry" || bad "increment history" "action=$(hlast action)"
[ "$(hlast value)" = "1" ] && ok "history entry carries the step" || bad "increment value" "value=$(hlast value)"
[ "$(hlast timestamp)" != "null" ] && ok "history entry carries a timestamp" || bad "increment timestamp" "null"

jq '.step = 5' "$WORK/score-config.json" > "$WORK/c" && mv "$WORK/c" "$WORK/score-config.json"
"$CLI" increment
[ "$(score)" = "6" ] && ok "increment honours config step 5" || bad "step" "score=$(score)"

"$CLI" decrement
[ "$(score)" = "1" ] && ok "decrement subtracts the step" || bad "decrement" "score=$(score)"

# ── reset ────────────────────────────────────────────────────────────────
"$CLI" reset
[ "$(score)" = "0" ] && ok "reset returns to initialValue 0" || bad "reset" "score=$(score)"
[ "$(hlast action)" = "reset" ] && ok "reset logs a history entry" || bad "reset action" "$(hlast action)"
[ "$(hlast from)" = "1" ] && ok "reset records the pre-reset score in .from" || bad "reset from" "from=$(hlast from)"

# ── undo ─────────────────────────────────────────────────────────────────
"$CLI" undo
[ "$(score)" = "1" ] && ok "undo of reset restores the pre-reset score" || bad "undo reset" "score=$(score)"
"$CLI" undo
[ "$(score)" = "6" ] && ok "undo of decrement adds the delta back" || bad "undo decrement" "score=$(score)"
"$CLI" undo
[ "$(score)" = "1" ] && ok "undo of increment subtracts the delta" || bad "undo increment" "score=$(score)"
"$CLI" undo
[ "$(score)" = "0" ] && ok "undo walks back to the first increment" || bad "undo increment 2" "score=$(score)"
[ "$(hlen)" = "0" ] && ok "history is empty after undoing everything" || bad "undo history" "len=$(hlen)"
"$CLI" undo
[ "$(score)" = "0" ] && ok "undo on empty history is a no-op" || bad "undo noop" "score=$(score)"

# ── set ──────────────────────────────────────────────────────────────────
"$CLI" set 42
[ "$(score)" = "42" ] && ok "set overrides the score" || bad "set" "score=$(score)"
[ "$(hlen)" = "0" ] && ok "set does not log history" || bad "set history" "len=$(hlen)"

# back to a step of 1 for the remaining cases
jq '.step = 1' "$WORK/score-config.json" > "$WORK/c" && mv "$WORK/c" "$WORK/score-config.json"

# ── tolerance: a garbled stored score is treated as 0 ─────────────────────
echo '{"score":"corrupt","history":[]}' > "$WORK/score-state.json"
"$CLI" increment
[ "$(score)" = "1" ] && ok "a non-numeric stored score is coerced to 0 before the delta" || bad "coerce score" "score=$(score)"

# ── tolerance: a malformed file degrades to defaults ──────────────────────
echo '<not json' > "$WORK/score-state.json"
"$CLI" reset
[ "$(score)" = "0" ] && ok "a malformed state file degrades to defaults" || bad "malformed" "score=$(score)"

# ── history cap ──────────────────────────────────────────────────────────
echo '{"score":0,"history":[]}' > "$WORK/score-state.json"
for _ in $(seq 1 60); do "$CLI" increment; done
[ "$(hlen)" = "50" ] && ok "history is capped at 50 entries" || bad "history cap" "len=$(hlen)"

# ── status ───────────────────────────────────────────────────────────────
st="$("$CLI" status)"
[ "$(jq -r '.score' <<<"$st")" = "60" ] && ok "status reports the score" || bad "status score" "$st"
[ "$(jq -r '.canUndo' <<<"$st")" = "true" ] && ok "status reports canUndo" || bad "status canUndo" "$st"
[ "$(jq -r '.config.step' <<<"$st")" = "1" ] && ok "status embeds the config" || bad "status config" "$st"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
