#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/skills/demo" "$ROOT/state"
printf '%s\n' '---' 'name: demo' '---' > "$ROOT/skills/demo/SKILL.md"
export HOME="$ROOT/home" OMARCHY_SKILL_ROOTS="$ROOT/skills" OMARCHY_STATE_DIR="$ROOT/state" OMARCHY_SKILL_USAGE_DIR="$ROOT/state/usage"
mkdir -p "$HOME"
path="$($HERE/local-bin/omarchy-skill-refresh)"
test "$path" = "$ROOT/state/skill-dashboard.json"
test "$(jq -r '.version' "$path")" = 1
printf 'ok - omarchy-skill-refresh\n'
