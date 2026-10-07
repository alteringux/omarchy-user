#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/home/skill" "$ROOT/state"
printf '%s\n' '---' 'name: demo' '---' > "$ROOT/home/skill/SKILL.md"
export HOME="$ROOT/home" OMARCHY_SKILL_LIFECYCLE="$ROOT/state/lifecycle.json"
python3 "$HERE/local-bin/omarchy_skill_action.py" deprecate demo --path "$ROOT/home/skill" >/dev/null
python3 "$HERE/local-bin/omarchy_skill_action.py" remove demo --path "$ROOT/home/skill" >/dev/null
test ! -d "$ROOT/home/skill"
backup="$(python3 -c 'import json; print(json.load(open("'"$ROOT/state/lifecycle.json"'"))["skills"]["demo"]["backup"])')"
python3 "$HERE/local-bin/omarchy_skill_action.py" restore demo --path "$ROOT/home/skill" >/dev/null
test -d "$ROOT/home/skill" && test ! -d "$backup"
mkdir -p "$ROOT/system/skill"
printf '%s\n' '---' 'name: system' '---' > "$ROOT/system/skill/SKILL.md"
if python3 "$HERE/local-bin/omarchy_skill_action.py" remove system --path "$ROOT/system/skill" >/dev/null 2>&1; then
  echo 'packaged skill was removed' >&2
  exit 1
fi
printf 'ok - omarchy-skill-action\n'
