#!/bin/bash
FONT_NAME=$1
echo "- $(date '+%Y-%m-%d %H:%M') — Font changed to \`$FONT_NAME\`" >> "$HOME/Documents/omarchy-changelog.md"
