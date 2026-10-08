#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"; ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/home/skills/product-teardown" "$ROOT/state"
printf '%s\n' '---' 'name: product-teardown' 'description: Product analysis' '---' > "$ROOT/home/skills/product-teardown/SKILL.md"
export HOME="$ROOT/home" OMARCHY_STATE_DIR="$ROOT/state" OMARCHY_SKILL_ROOTS="$ROOT/home/skills"
"$HERE/local-bin/omarchy-skilldashboard" refresh
test "$(jq -r '.skills[0].id' "$ROOT/state/skilldashboard.json")" = product-teardown
skill_path="$ROOT/home/skills/product-teardown"
"$HERE/local-bin/omarchy-skilldashboard" action remove product-teardown "$skill_path"
test ! -e "$skill_path"
test "$(jq -r '.skills["product-teardown"].status' "$ROOT/state/skilldashboard-lifecycle.json")" = removed
"$HERE/local-bin/omarchy-skilldashboard" action restore product-teardown
test -f "$skill_path/SKILL.md"
test "$(jq -r '.skills[0].status' "$ROOT/state/skilldashboard.json")" = active
printf 'ok - standalone skilldashboard CLI\n'
