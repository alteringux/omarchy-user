#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
FILE="$ROOT/alteringux.example.json"
for i in $(seq 1 24); do
  "$HERE/local-bin/omarchy-usage-record" "$FILE" activate "$((1700000000000 + i))" &
done
wait
count="$(jq -r '.actions.activate.count' "$FILE")"
[ "$count" = 24 ]
printf 'ok - concurrent usage records retain every action\n'
[ "$(jq -r '.actions.activate.recent | length' "$FILE")" = 20 ]
printf 'ok - concurrent usage records retain recency\n'
