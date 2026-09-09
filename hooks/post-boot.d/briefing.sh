#!/bin/bash
# AI startup greeting + daily briefing.
#
# Runs as a post-boot hook (omarchy-hook post-boot) and on SUPER+ALT+Q. Asks
# `claude -p` -- via ~/.local/bin/llm-blurb -- for a short personalised greeting
# and shows it as a desktop notification. Featherless has been removed from this
# box; llm-blurb is now a thin wrapper over the claude CLI.
#
# Optional overrides in ~/.config/omarchy/ai-briefing/env:
#   BRIEFING_MODEL   sonnet | haiku | opus (default: llm-blurb's own default)
#   LLM_BLURB_BIN    path to the llm-blurb helper

set -euo pipefail

ENV_FILE="$HOME/.config/omarchy/ai-briefing/env"
LOG_FILE="$HOME/.config/omarchy/ai-briefing/last-briefing.log"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

LLM_BLURB_BIN="${LLM_BLURB_BIN:-$(command -v llm-blurb || echo "$HOME/.local/bin/llm-blurb")}"

HOUR=$(date +%H)
DAY=$(date +"%A, %B %d")

if [[ $HOUR -lt 12 ]]; then
  GREETING="Good morning"
elif [[ $HOUR -lt 18 ]]; then
  GREETING="Good afternoon"
else
  GREETING="Good evening"
fi

PROMPT="It is ${HOUR}:00 on ${DAY}. Write a short, warm, one-to-two sentence morning briefing for a Linux desktop user logging in. Include a light bit of dev humor or a one-line tip. No markdown, no greeting like \"Hello\" — just the message itself, plain text."

model_args=()
[[ -n "${BRIEFING_MODEL:-}" ]] && model_args+=(--model "$BRIEFING_MODEL")

if [[ ! -x "$LLM_BLURB_BIN" ]]; then
  notify-send "$GREETING" "It's $DAY. (llm-blurb not found — install it or set LLM_BLURB_BIN in ~/.config/omarchy/ai-briefing/env.)" -i weather-clear
  exit 0
fi

# llm-blurb wraps `claude -p`; if it still comes back empty we degrade to a
# plain dateline rather than an error toast.
TEXT=$("$LLM_BLURB_BIN" --max-tokens 120 --timeout 30 "${model_args[@]}" "$PROMPT" 2>>"$LOG_FILE") || TEXT=""
TEXT=$(printf '%s' "$TEXT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

if [[ -z "$TEXT" ]]; then
  echo "$(date): (empty — llm-blurb failed, see stderr above)" >> "$LOG_FILE"
  notify-send "$GREETING" "It's $DAY. Have a good one." -i weather-clear
  exit 0
fi

echo "$(date): $TEXT" >> "$LOG_FILE"
notify-send "$GREETING" "$TEXT" -i weather-clear
