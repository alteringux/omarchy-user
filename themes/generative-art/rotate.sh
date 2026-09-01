#!/bin/bash
# Generate one fresh piece and rotate the wallpaper to it, keeping the
# backgrounds/ directory capped so it doesn't grow unbounded. Meant to be
# run periodically (see the generative-art-rotate systemd user timer) —
# cheap enough (numpy path: 1-20s depending on the fractal parameter) to run
# every few minutes without being intrusive.
set -euo pipefail
THEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PICTURES_DIR="$HOME/Pictures/omarchy-generative-art"
KEEP=12

NEW_BG="$(python3 "$THEME_DIR/generate.py" --single random --print-path)"

# Prune down to the newest $KEEP timestamped pieces (fractal-*, flow-field-*,
# attractor-*) in both the theme cache and its ~/Pictures mirror; the three
# fixed-name defaults (fractal.png etc.) are left alone so
# `omarchy theme set generative-art` always has a baseline.
for dir in "$THEME_DIR/backgrounds" "$PICTURES_DIR"; do
    mapfile -t OLD < <(
        find "$dir" -maxdepth 1 -type f \
            \( -name 'fractal-*.png' -o -name 'flow-field-*.png' -o -name 'attractor-*.png' \) \
            -printf '%T@ %p\n' 2>/dev/null | sort -rn | tail -n +$((KEEP + 1)) | cut -d' ' -f2-
    )
    for f in "${OLD[@]:-}"; do
        [ -n "$f" ] && rm -f "$f"
    done
done

if [ "$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)" = "generative-art" ]; then
    omarchy theme bg set "$NEW_BG" >/dev/null 2>&1 || true
fi
