#!/bin/bash
# Uses llm-blurb (Featherless) to grow the quote and affirmation pools in the
# style of whatever the user has liked so far, then prunes lines that have
# collected too many dislikes.
set -euo pipefail

BASE="$HOME/.config/omarchy/motivator"
cd "$BASE"

LLM_BLURB="$(command -v llm-blurb || echo "$HOME/.local/bin/llm-blurb")"

# grow KIND FLAVOUR-TEXT  -- KIND is "quotes" or "affirmations".
grow() {
  local kind=$1 flavour=$2 top
  top=$(python3 "$BASE/motivator.py" "top-affirmations" 8)
  [[ "$kind" == "quotes" ]] && top=$(python3 "$BASE/motivator.py" "top" 8)
  [[ -z "$top" ]] && return 0

  local prompt="Generate 5 new, original, short $flavour (one sentence each, no attribution, no numbering, no quotation marks, no markdown) in the same spirit as these favorites:
$top

Return only the 5 lines, one per line, nothing else."

  local result
  result=$("$LLM_BLURB" --max-tokens 300 --temp 0.9 "$prompt" 2>/dev/null || true)
  [[ -z "$result" ]] && return 0

  local added
  added=$(echo "$result" | python3 "$BASE/motivator.py" "add-$kind")
  echo "$(date): refreshed $kind, added ${added:-0} new" >> "$BASE/refresh.log"
}

grow quotes "motivational quotes"
grow affirmations "first-person affirmations starting with 'I' in present tense"

# Drop lines that have accumulated too many dislikes.
for target in "prune" "prune-affirmations"; do
  pruned=$(python3 "$BASE/motivator.py" "$target" -3)
  if [[ "${pruned:-0}" -gt 0 ]]; then
    echo "$(date): $target removed $pruned disliked" >> "$BASE/refresh.log"
  fi
done
