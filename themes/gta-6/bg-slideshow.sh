#!/bin/bash
# Cycle the gta-6 wallpaper on a timer, for as long as gta-6 is the active
# Omarchy theme. Driven by the gta-6-bg-slideshow systemd user service.
#
# It only ADVANCES the rotation (`omarchy theme bg next`) over the same pool the
# background switcher uses: the theme's own backgrounds/ dir plus
# ~/.config/omarchy/backgrounds/gta-6/ (filled by fetch-wallpaper.sh).
#
# While any other theme is active it just sleeps, so the service can be left
# enabled permanently. Change the cadence with:
#   systemctl --user edit gta-6-bg-slideshow.service
#   -> [Service] Environment=GTA_6_SLIDESHOW_INTERVAL=<seconds>
set -uo pipefail

INTERVAL="${GTA_6_SLIDESHOW_INTERVAL:-15}"
THEME_NAME_FILE="$HOME/.local/state/omarchy/current/theme.name"

# Give the graphical session / omarchy-shell a moment to come up on login.
sleep 5

while :; do
  if [[ "$(cat "$THEME_NAME_FILE" 2>/dev/null)" == "gta-6" ]]; then
    omarchy-theme-bg-next >/dev/null 2>&1 || true
    sleep "$INTERVAL"
  else
    # Not our theme -- idle cheaply until it is.
    sleep 15
  fi
done
