#!/bin/bash
THEME_SLUG=$1
echo "- $(date '+%Y-%m-%d %H:%M') — Theme switched to \`$THEME_SLUG\`" >> "$HOME/Documents/omarchy-changelog.md"
