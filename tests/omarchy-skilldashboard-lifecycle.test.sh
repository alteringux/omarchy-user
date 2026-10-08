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

"$SCRIPT" action disable demo-skill "$SKILL"
jq -e '.skills["demo-skill"].status == "disabled"' "$OMARCHY_SKILL_LIFECYCLE" >/dev/null
"$SCRIPT" action enable demo-skill "$SKILL"
jq -e '.skills["demo-skill"].status == "active"' "$OMARCHY_SKILL_LIFECYCLE" >/dev/null

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

LINKED="$HOME/linked-root"
ln -s "$TMP" "$LINKED"
if "$SCRIPT" action remove outside "$LINKED/outside-skill" >/dev/null 2>&1; then
  echo "FAIL: removal escaped HOME through a symlinked parent" >&2
  exit 1
fi
test -f "$OUTSIDE/SKILL.md"

if "$SCRIPT" action remove ../escaped-skill "$SKILL" >/dev/null 2>&1; then
  echo "FAIL: skill ID escaped the trash directory" >&2
  exit 1
fi
test -f "$SKILL/SKILL.md"

"$SCRIPT" action remove demo-skill "$SKILL"
mkdir -p "$SKILL"
printf '%s\n' 'occupied destination' > "$SKILL/keep.txt"
if "$SCRIPT" action restore demo-skill >/dev/null 2>&1; then
  echo "FAIL: restore overwrote an occupied destination" >&2
  exit 1
fi
test -f "$SKILL/keep.txt"
test -f "$OMARCHY_SKILL_TRASH_DIR/demo-skill/SKILL.md"
rm "$SKILL/keep.txt"
rmdir "$SKILL"
ln -s "$HOME/missing-target" "$SKILL"
if "$SCRIPT" action restore demo-skill >/dev/null 2>&1; then
  echo "FAIL: restore overwrote a dangling destination symlink" >&2
  exit 1
fi
test -L "$SKILL"
test -f "$OMARCHY_SKILL_TRASH_DIR/demo-skill/SKILL.md"
rm "$SKILL"

FORGED="$OMARCHY_STATE_DIR/forged-backup"
mkdir -p "$FORGED"
printf '%s\n' 'name: Forged backup fixture' > "$FORGED/SKILL.md"
TEMP_STATE=$(mktemp)
jq --arg backup "$OMARCHY_SKILL_TRASH_DIR/../forged-backup" \
  '.skills["demo-skill"].trashPath=$backup' "$OMARCHY_SKILL_LIFECYCLE" > "$TEMP_STATE"
mv "$TEMP_STATE" "$OMARCHY_SKILL_LIFECYCLE"
if "$SCRIPT" action restore demo-skill >/dev/null 2>&1; then
  echo "FAIL: restore accepted a trash path outside its canonical root" >&2
  exit 1
fi
test -f "$FORGED/SKILL.md"
test ! -e "$SKILL"
"$SCRIPT" refresh
jq -e '([.skills[] | select(.id == "demo-skill")] | length) == 0' \
  "$OMARCHY_STATE_DIR/skilldashboard.json" >/dev/null

echo "Skill Dashboard lifecycle: enable, remove/restore, ownership and path guards passed"
