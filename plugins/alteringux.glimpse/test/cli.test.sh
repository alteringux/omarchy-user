#!/usr/bin/env bash
# Black-box checks for manual check-in state persistence.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CLI="${OMARCHY_GLIMPSE_BIN:-$REPO/local-bin/omarchy-glimpse}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export OMARCHY_STATE_DIR="$WORK/state"
export OMARCHY_GLIMPSE_CACHE_DIR="$WORK/cache"
export OMARCHY_GLIMPSE_NO_DAEMON=1
export OMARCHY_GLIMPSE_NO_NET=1
export OMARCHY_GLIMPSE_QUIET=1
mkdir -p "$OMARCHY_STATE_DIR" "$OMARCHY_GLIMPSE_CACHE_DIR"

# Seed the normal config, then enable the feature without invoking `on` (which
# also performs a network/cache promotion in a real user environment).
"$CLI" get-config >/dev/null
jq '.enabled = true' "$OMARCHY_STATE_DIR/glimpse-config.json" > "$WORK/config.tmp" \
  && mv "$WORK/config.tmp" "$OMARCHY_STATE_DIR/glimpse-config.json"

cat > "$OMARCHY_STATE_DIR/glimpse-state.json" <<'EOF'
{"version":1,"prompt":null,"round":null,"session":{"type":"drill","level":3,"rounds":0,"hits":0,"misses":0,"startedAt":0},"dismissStreak":0,"lastPromptMs":0,"lastRoundMs":0,"roundsToday":0,"roundsTodayDate":"","pauseUntilMs":0,"streakDays":0,"lastActiveDate":"","lifetime":{"rounds":0,"accuracySum":0}}
EOF
cp "$OMARCHY_STATE_DIR/glimpse-state.json" "$WORK/clean-state.json"

jq -n '{version:1,cards:[
  {id:"s-valid",sceneId:"scene",mode:"change",level:3,changeCount:2,truth:[],createdAt:0,ease:2.5,intervalDays:0,dueAt:0,reps:0,lapses:0,lastGrade:null,shownAt:null,bestAccuracy:0}
]}' > "$OMARCHY_STATE_DIR/glimpse-cards.json"

if "$CLI" checkin >"$WORK/checkin.out" 2>"$WORK/checkin.err"; then
  prompt_kind="$(jq -r '.prompt.kind' "$OMARCHY_STATE_DIR/glimpse-state.json")"
  prompt_id="$(jq -r '.prompt.cardIds[0]' "$OMARCHY_STATE_DIR/glimpse-state.json")"
  prompt_reason="$(jq -r '.prompt.reason' "$OMARCHY_STATE_DIR/glimpse-state.json")"
  [ "$prompt_kind" = "checkin" ] \
    && [ "$prompt_id" = "s-valid" ] \
    && [ "$prompt_reason" = "manual" ] \
    && jq -e . "$OMARCHY_STATE_DIR/glimpse-state.json" >/dev/null \
    && echo "ok   - valid check-in ID persists a manual prompt" \
    || { echo "FAIL - valid check-in ID did not persist a manual prompt"; exit 1; }
else
  echo "FAIL - valid check-in ID command failed"
  cat "$WORK/checkin.err" >&2
  exit 1
fi

# Non-string IDs are rejected by the tolerant card parser. They must not make
# jq emit an invalid document or alter the existing state.
jq -n '{version:1,cards:[
  {id:null,sceneId:"null-id",dueAt:0},
  {id:42,sceneId:"number-id",dueAt:0},
  {id:{bad:true},sceneId:"object-id",dueAt:0},
  {id:"",sceneId:"empty-id",dueAt:0}
]}' > "$OMARCHY_STATE_DIR/glimpse-cards.json"
cp "$WORK/clean-state.json" "$OMARCHY_STATE_DIR/glimpse-state.json"
if "$CLI" checkin >"$WORK/malformed.out" 2>"$WORK/malformed.err"; then
  [ "$(cat "$WORK/malformed.out")" = "nothing due" ] \
    && cmp -s "$OMARCHY_STATE_DIR/glimpse-state.json" "$WORK/clean-state.json" \
    && jq -e . "$OMARCHY_STATE_DIR/glimpse-state.json" >/dev/null \
    && echo "ok   - malformed check-in IDs leave valid state untouched" \
    || { echo "FAIL - malformed check-in IDs changed state"; exit 1; }
else
  echo "FAIL - malformed check-in IDs failed unsafely"
  cat "$WORK/malformed.err" >&2
  exit 1
fi
