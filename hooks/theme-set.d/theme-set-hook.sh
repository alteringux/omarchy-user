#!/bin/bash
# Only act when switching TO the generative-art theme.
THEME_SLUG=$1
if [ "$THEME_SLUG" = "generative-art" ]; then
    "$HOME/.config/omarchy/themes/generative-art/generate.py" >/dev/null 2>&1
fi
