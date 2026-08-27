#!/bin/bash
# Shared helpers for the dashboard bin/ scripts (refresh, note, track).
# Meant to be sourced, not executed.

STATE_DIR="$HOME/.local/state/omarchy"
STATE_FILE="$STATE_DIR/dashboard.json"
LOCK_FILE="$STATE_DIR/dashboard.lock"

# Canonical empty-state seed — one definition so refresh/note/track can't
# drift into subtly different shapes (they previously carried three
# slightly different literals). Model.parseState tolerates older files
# missing the engagement/digest keys, so seeding them here is harmless.
DASHBOARD_SEED='{"version":1,"notes":{"items":[]},"news":{"updatedAt":null,"items":[]},"system":{"updatedAt":null,"items":[]},"engagement":{"news":{}},"digest":{"text":"","updatedAt":null}}'

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

ensure_state_file() {
  mkdir -p "$STATE_DIR"
  [[ -f "$STATE_FILE" ]] || printf '%s\n' "$DASHBOARD_SEED" >"$STATE_FILE"
}
