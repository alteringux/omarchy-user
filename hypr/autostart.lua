-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Force Wi-Fi radio OFF on every login. NetworkManager persists its last
-- radio state, so without this a reboot would restore Wi-Fi if it was on;
-- this re-asserts "off" each boot so networking is opt-in per session.
-- Turn it on when you want it: `nmcli radio wifi on` (or the Wi-Fi menu).
o.exec_on_start("nmcli radio wifi off")

-- Speak incoming notifications aloud (Piper TTS). Toggle with SUPER+ALT+V.
o.launch_on_start("omarchy-speak-notifications")

-- Read the weekly "next steps" recap aloud at login (Piper TTS).
-- Toggle the boot readout with `omarchy-speak-recap-toggle`; SUPER+ALT+W
-- speaks it on demand. --boot => obeys the on/off state + waits for audio.
o.exec_on_start("omarchy-speak-recap --boot")

-- Relaunch browsers on login so their own "restore previous session"
-- setting brings tabs back. Workspace placement is in hypr/hyprland.lua.
o.launch_on_start("zen-browser")
o.launch_on_start("chromium")

-- Turn on the recall trainer (~/.local/bin/omarchy-recall): spaced-repetition
-- lessons/quizzes (memory techniques, trivia, English vocabulary), reviewed
-- with SUPER SHIFT ALT + R. `on` is idempotent and spins up its own transient
-- systemd --user daemon, which does NOT survive reboot on its own -- hence
-- re-asserting it here every login.
o.exec_on_start("omarchy-recall on")

-- Start tmux on login. This boots the tmux server, which fires
-- tmux-continuum's auto-restore -> saved windows/panes come back, and
-- panes that were running `claude` relaunch via tmux-resurrect.
-- (Launcher already handles uwsm + the terminal, so no o.launch wrap.)
o.exec_on_start("omarchy-launch-terminal-tmux")
