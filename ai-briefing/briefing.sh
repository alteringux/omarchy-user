#!/bin/bash
# AI startup greeting + daily briefing
# Runs as a post-boot hook. Asks the Claude CLI for a short personalized
# greeting and shows it as a desktop notification.
#
# Uses the `claude` CLI (Claude Code), which authenticates with your existing
# Claude login — no ANTHROPIC_API_KEY needed. Optional overrides can go in
# ~/.config/omarchy/ai-briefing/env (e.g. BRIEFING_MODEL, CLAUDE_BIN).

set -euo pipefail

ENV_FILE="$HOME/.config/omarchy/ai-briefing/env"
LOG_FILE="$HOME/.config/omarchy/ai-briefing/last-briefing.log"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
BRIEFING_MODEL="${BRIEFING_MODEL:-haiku}"

if [[ -z "$CLAUDE_BIN" || ! -x "$CLAUDE_BIN" ]]; then
  notify-send "AI Briefing" "claude CLI not found on PATH — install it or set CLAUDE_BIN in ~/.config/omarchy/ai-briefing/env" -i dialog-information
  exit 0
fi

HOUR=$(date +%H)
DAY=$(date +"%A, %B %d")

PROMPT="It is ${HOUR}:00 on ${DAY}. Write a short, warm, one-to-two sentence morning briefing for a Linux desktop user logging in. Include a light bit of dev humor or a one-line tip. No markdown, no greeting like \"Hello\" — just the message itself, plain text."

TEXT=$(timeout 30 "$CLAUDE_BIN" -p "$PROMPT" --model "$BRIEFING_MODEL" 2>>"$LOG_FILE") || {
  notify-send "AI Briefing" "Couldn't get a briefing from the claude CLI (see last-briefing.log)." -i dialog-error
  exit 0
}

TEXT=$(printf '%s' "$TEXT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

if [[ -z "$TEXT" ]]; then
  notify-send "AI Briefing" "claude CLI returned an empty response (see last-briefing.log)." -i dialog-error
  exit 0
fi

echo "$(date): $TEXT" >> "$LOG_FILE"

if [[ $HOUR -lt 12 ]]; then
  GREETING="Good morning"
elif [[ $HOUR -lt 18 ]]; then
  GREETING="Good afternoon"
else
  GREETING="Good evening"
fi

notify-send "$GREETING" "$TEXT" -i weather-clear
