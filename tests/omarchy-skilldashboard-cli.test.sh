#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"; ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/skills/product-teardown" "$ROOT/state" "$ROOT/home"
printf '%s\n' '---' 'name: product-teardown' 'description: Product analysis' '---' > "$ROOT/skills/product-teardown/SKILL.md"
export HOME="$ROOT/home" OMARCHY_STATE_DIR="$ROOT/state" OMARCHY_SKILL_ROOTS="$ROOT/skills"
"$HERE/local-bin/omarchy-skilldashboard" refresh
test "$(jq -r '.skills[0].id' "$ROOT/state/skilldashboard.json")" = product-teardown
printf 'ok - standalone skilldashboard CLI\n'
