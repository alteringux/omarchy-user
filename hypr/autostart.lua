-- Extra autostart processes.
-- o.launch_on_start("my-service")

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

-- Start tmux on login. This boots the tmux server, which fires
-- tmux-continuum's auto-restore -> saved windows/panes come back, and
-- panes that were running `claude` relaunch via tmux-resurrect.
-- (Launcher already handles uwsm + the terminal, so no o.launch wrap.)
o.exec_on_start("omarchy-launch-terminal-tmux")
