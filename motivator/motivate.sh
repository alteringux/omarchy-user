#!/bin/bash
# Sends a random motivational quote/affirmation notification every few random
# minutes. The notification daemon reads notifications aloud on its own, so
# affirmations get spoken without this script touching TTS.
# Self-improving: 👍/👎 on each notification reweights future picks, and
# every REFRESH_EVERY sends it asks the local `claude` CLI to generate new
# quotes and affirmations in the style of whatever's been liked, then prunes
# disliked ones.
# Once per calendar day it also fires a "Today's Motivation" digest: a random
# list of several lines from the whole pool.

set -euo pipefail

BASE="$HOME/.config/omarchy/motivator"
MIN_MINUTES=2
MAX_MINUTES=10
REFRESH_EVERY=15
DAILY_LIST_SIZE=5
COUNTER_FILE="$BASE/.send-count"
DAILY_STAMP="$BASE/.last-daily"
ICON="$BASE/motivation.svg"

# Once-a-day digest: a random list from the whole pool.
maybe_daily_list() {
  local today last
  today=$(date +%F)
  last=""
  [[ -f "$DAILY_STAMP" ]] && last=$(cat "$DAILY_STAMP")
  [[ "$today" == "$last" ]] && return 0

  local list
  list=$(python3 "$BASE/motivator.py" daily-list "$DAILY_LIST_SIZE")
  [[ -z "$list" ]] && return 0

  echo "$today" > "$DAILY_STAMP"
  local body
  body=$(printf '%s\n' "$list" | sed 's/^/• /')
  notify-send "Today's Motivation" "$body" -i "$ICON" 2>/dev/null || true
}

count=0
[[ -f "$COUNTER_FILE" ]] && count=$(cat "$COUNTER_FILE")

while true; do
  maybe_daily_list

  QUOTE=$(python3 "$BASE/motivator.py" pick)

  if [[ -n "$QUOTE" ]]; then
    (
      ACTION=$(notify-send "Motivation" "$QUOTE" -i "$ICON" -A like="👍" -A dislike="👎" 2>/dev/null || true)
      case "$ACTION" in
        like) python3 "$BASE/motivator.py" feedback "$QUOTE" 1 ;;
        dislike) python3 "$BASE/motivator.py" feedback "$QUOTE" -1 ;;
      esac
    ) &

    count=$((count + 1))
    echo "$count" > "$COUNTER_FILE"

    if (( count % REFRESH_EVERY == 0 )); then
      "$BASE/refresh.sh" &
    fi
  fi

  RANGE=$(( (MAX_MINUTES - MIN_MINUTES + 1) * 60 ))
  SLEEP_SECONDS=$(( MIN_MINUTES * 60 + RANDOM % RANGE ))
  sleep "$SLEEP_SECONDS"
done
