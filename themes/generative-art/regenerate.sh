#!/bin/bash
# Regenerate the generative-art wallpapers with a fresh random seed and,
# if this theme is the active one, restart the background so it's visible
# immediately.
set -euo pipefail
THEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 "$THEME_DIR/generate.py"

if [ "$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)" = "generative-art" ]; then
    omarchy theme set generative-art >/dev/null 2>&1 || true
fi
