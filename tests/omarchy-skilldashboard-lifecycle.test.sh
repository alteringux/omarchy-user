#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$(cd "$HERE/.." && pwd)/local-bin/omarchy-skilldashboard"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export OMARCHY_STATE_DIR="$TMP/state"
export OMARCHY_SKILL_LIFECYCLE="$TMP/state/lifecycle.json"
export OMARCHY_SKILL_USAGE_DIR="$TMP/state/usage"
export OMARCHY_SKILL_TRASH_DIR="$TMP/state/trash"
export OMARCHY_SKILL_ROOTS="$HOME/.codex/skills"

SKILL="$OMARCHY_SKILL_ROOTS/demo-skill"
mkdir -p "$SKILL" "$OMARCHY_SKILL_USAGE_DIR"
printf '%s\n' 'name: Demo skill' 'description: lifecycle fixture' > "$SKILL/SKILL.md"
printf '%s\n' '{"uses":7,"lastAt":0}' > "$OMARCHY_SKILL_USAGE_DIR/demo-skill.json"

"$SCRIPT" refresh
jq -e '.summary.total == 1 and .summary.uses == 7' "$OMARCHY_STATE_DIR/skilldashboard.json" >/dev/null

"$SCRIPT" action remove demo-skill "$SKILL"
test ! -e "$SKILL"
jq -e '.summary.total == 0 and .summary.uses == 0 and
  ([.skills[] | select(.id == "demo-skill" and .status == "removed" and .owned)] | length) == 1' \
  "$OMARCHY_STATE_DIR/skilldashboard.json" >/dev/null

"$SCRIPT" action restore demo-skill
test -f "$SKILL/SKILL.md"
jq -e '.summary.total == 1 and .summary.uses == 7 and
  ([.skills[] | select(.id == "demo-skill" and .status == "active")] | length) == 1' \
  "$OMARCHY_STATE_DIR/skilldashboard.json" >/dev/null

OUTSIDE="$TMP/outside-skill"
mkdir -p "$OUTSIDE"
printf '%s\n' 'name: Outside' > "$OUTSIDE/SKILL.md"
if "$SCRIPT" action remove outside "$OUTSIDE" >/dev/null 2>&1; then
  echo "FAIL: removal accepted a path outside HOME" >&2
  exit 1
fi
test -f "$OUTSIDE/SKILL.md"

echo "Skill Dashboard lifecycle: remove, recoverable snapshot, restore, and ownership guard passed"
