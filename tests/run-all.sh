#!/usr/bin/env bash
# Runs every omarchy test suite: the shell suites in this directory
# (*.test.sh) and every plugin's node logic tests (plugins/*/test*/*.test.js).
#
#   bash ~/.config/omarchy/tests/run-all.sh            # everything
#   bash ~/.config/omarchy/tests/run-all.sh stopwatch  # only suites matching "stopwatch"
#
# Exit status is non-zero if any suite fails. Each suite is expected to print
# its own detail and exit non-zero on failure.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGINS="$HOME/.config/omarchy/plugins"
FILTER="${1:-}"

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
  run_suite "sh  ${f##*/}" bash "$f"
done

# --- QML component compilation ---------------------------------------------
run_suite "qml alteringux.kit" python3 \
  "$HERE/../docs/prds/evidence/02-accessibility/run-plugin-load-probe.py" \
  --package alteringux.kit

# --- plugin node logic tests ------------------------------------------------
if command -v node >/dev/null 2>&1; then
  while IFS= read -r f; do
    [ -e "$f" ] || continue
    rel=${f#"$PLUGINS"/}
    run_suite "js  ${rel}" node "$f"
  done < <(find "$PLUGINS" -type d -name node_modules -prune -o \
             -type f -name '*.test.js' -print | sort)
else
  printf '\n\033[33mnode not found — skipping plugin logic tests\033[0m\n'
fi

# --- summary -----------------------------------------------------------
printf '\n\033[1m========================================\033[0m\n'
if [ "$fail" -eq 0 ]; then
  printf '\033[32mall %d suite(s) passed\033[0m\n' "$pass"
else
  printf '\033[31m%d suite(s) failed, %d passed\033[0m\n' "$fail" "$pass"
  printf '  \033[31m- %s\033[0m\n' "${failed_suites[@]}"
fi
[ "$fail" -eq 0 ]
