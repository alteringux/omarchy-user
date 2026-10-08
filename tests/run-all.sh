#!/usr/bin/env bash
# Runs repository shell suites, the Kit QML compile guard, the inventory
# contract, and every plugin JS, shell, and Python test.
#
#   bash ~/.config/omarchy/tests/run-all.sh            # everything
#   bash ~/.config/omarchy/tests/run-all.sh stopwatch  # only suites matching "stopwatch"
#   bash ~/.config/omarchy/tests/run-all.sh --portable # CI without an Omarchy desktop
#
# Exit status is non-zero if any suite fails. Each suite is expected to print
# its own detail and exit non-zero on failure.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
PLUGINS="$REPO/plugins"
PORTABLE=0
if [ "${1:-}" = "--portable" ]; then
  PORTABLE=1
  shift
fi
FILTER="${1:-}"

if [ -z "$FILTER" ]; then
  for dependency in node python3 jq; do
    command -v "$dependency" >/dev/null || {
      printf 'Missing test dependency: %s\n' "$dependency" >&2
      exit 2
    }
  done
fi

if [ "$PORTABLE" -eq 1 ]; then
  printf '%s\n' 'Portable checks; desktop release gates deferred:' \
    '  - live bar geometry and popup IPC' \
    '  - plugin QML component loading' \
    '  - Omarchy host manifest schema validation'
fi

pass=0
fail=0
failed_suites=()

run_suite() {
  local label=$1 ; shift
  if [ -n "$FILTER" ] && [[ "$label" != *"$FILTER"* ]]; then
    return
  fi
  printf '\n\033[1m# %s\033[0m\n' "$label"
  if "$@"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed_suites+=("$label")
  fi
}

# --- shell suites ---------------------------------------------------------
for f in "$HERE"/*.test.sh; do
  [ -e "$f" ] || continue
  if [ "$PORTABLE" -eq 1 ] && [ "${f##*/}" = "omarchy-bar-layout.test.sh" ]; then
    continue
  fi
  run_suite "sh  ${f##*/}" bash "$f"
done

# --- QML component compilation ---------------------------------------------
if [ "$PORTABLE" -eq 0 ]; then
  run_suite "qml all plugin components" python3 \
    "$HERE/../docs/prds/evidence/02-accessibility/run-plugin-load-probe.py"
fi

# --- repository inventory contracts ----------------------------------------
if [ "$PORTABLE" -eq 1 ]; then
  run_suite "py  omarchy-plugin-catalog.test.py" python3 \
    "$HERE/omarchy-plugin-catalog.test.py" PluginCatalogTest
else
  run_suite "py  omarchy-plugin-catalog.test.py" python3 \
    "$HERE/omarchy-plugin-catalog.test.py"
fi

# --- plugin logic and CLI tests --------------------------------------------
while IFS= read -r f; do
  [ -e "$f" ] || continue
  rel=${f#"$PLUGINS"/}
  case "$f" in
    *.test.js)  run_suite "js  ${rel}" node "$f" ;;
    *.test.sh)  run_suite "sh  ${rel}" bash "$f" ;;
    *.test.py|*_test.py) run_suite "py  ${rel}" python3 "$f" ;;
  esac
done < <(find "$PLUGINS" -type d -name node_modules -prune -o -type f \
          \( -name '*.test.js' -o -name '*.test.sh' -o -name '*.test.py' -o -name '*_test.py' \) \
          -print | sort)

# --- summary -----------------------------------------------------------
printf '\n\033[1m========================================\033[0m\n'
if [ "$fail" -eq 0 ]; then
  printf '\033[32mall %d suite(s) passed\033[0m\n' "$pass"
else
  printf '\033[31m%d suite(s) failed, %d passed\033[0m\n' "$fail" "$pass"
  printf '  \033[31m- %s\033[0m\n' "${failed_suites[@]}"
fi
[ "$fail" -eq 0 ]
