#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/skills/product-teardown" "$ROOT/skills/other" "$ROOT/state"
cat > "$ROOT/skills/product-teardown/SKILL.md" <<'EOF'
---
name: product-teardown
description: Analyze products
---
EOF
cat > "$ROOT/skills/other/SKILL.md" <<'EOF'
---
name: other
description: Other skill
---
EOF
cat > "$ROOT/state/product-teardown.json" <<'EOF'
{"uses":4,"lastAt":1700086400000}
EOF
export OMARCHY_SKILL_ROOTS="$ROOT/skills" OMARCHY_SKILL_USAGE_DIR="$ROOT/state"
report="$(python3 "$HERE/local-bin/omarchy_skill_usage.py" --json --days 3)"
REPORT="$report" python3 - <<'PY'
import json, os
r = json.loads(os.environ["REPORT"])
assert [s["id"] for s in r["skills"]] == ["product-teardown", "other"]
product = r["skills"][0]
assert product["uses"] == 4 and product["tracked"] and product["stale"]
assert r["summary"] == {"total": 2, "tracked": 1, "untracked": 1, "neverUsed": 0, "stale": 1, "uses": 4}
PY
printf 'ok - omarchy-skill-usage\n'
