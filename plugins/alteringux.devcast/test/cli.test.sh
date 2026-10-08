#!/usr/bin/env bash
# Focused black-box coverage for replay replacement and stale indexing.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CLI="${OMARCHY_DEVCAST_BIN:-$REPO/local-bin/omarchy-devcast}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
export OMARCHY_STATE_DIR="$WORK/state"
export CLAUDE_PROJECTS_DIR="$WORK/projects"
export OMARCHY_DEVCAST_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export OMARCHY_DEVCAST_QUIET=1
mkdir -p "$HOME" "$OMARCHY_STATE_DIR/devcasts" "$CLAUDE_PROJECTS_DIR/project"

sid="devcast-regression"
tx="$CLAUDE_PROJECTS_DIR/project/$sid.jsonl"
printf '%s\n' \
  '{"type":"user","sessionId":"devcast-regression","timestamp":"2026-09-18T10:00:00Z","message":{"content":"build it"}}' \
  '{"type":"assistant","sessionId":"devcast-regression","timestamp":"2026-09-18T10:00:01Z","message":{"content":[{"type":"text","text":"done"}]}}' \
  > "$tx"

"$CLI" build "$tx" >/dev/null
old_dir="$(find "$OMARCHY_STATE_DIR/devcasts" -mindepth 1 -maxdepth 1 -type d -print)"
old_html_hash="$(sha256sum "$old_dir/replay.html" | cut -d' ' -f1)"
old_hash="$(sha256sum "$old_dir/cast.json" | cut -d' ' -f1)"

# A parse failure must not remove the previously completed replay.
printf '%s\n' '{"type":"system","sessionId":"devcast-regression"}' > "$tx"
if "$CLI" build "$tx" >/dev/null 2>&1; then
  echo "expected invalid replacement to fail" >&2
  exit 1
fi
[ "$(find "$OMARCHY_STATE_DIR/devcasts" -mindepth 1 -maxdepth 1 -type d -print | wc -l)" -eq 1 ]
[ "$(sha256sum "$old_dir/replay.html" | cut -d' ' -f1)" = "$old_html_hash" ]

# A replay whose source grew is labeled stale and omitted from current casts.
touch -d "@$(($(date +%s) + 10))" "$tx"
"$CLI" catalog >/dev/null
jq -e '.sessions[] | select(.sessionId == "devcast-regression") | (.stale == true and .built == null)' "$OMARCHY_STATE_DIR/devcast-catalog.json" >/dev/null
jq -e '.count == 0 and .latest == null and (.casts | length == 0)' "$OMARCHY_STATE_DIR/devcast-index.json" >/dev/null
if "$CLI" latest >/dev/null 2>&1; then
  echo "stale replay was returned as latest" >&2
  exit 1
fi
if [ "$("$CLI" list --json | jq 'length')" -ne 0 ]; then
  echo "stale replay was returned by list" >&2
  exit 1
fi

echo "devcast CLI regressions passed"
