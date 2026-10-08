-- Extra autostart processes.
-- o.launch_on_start("my-service")


-- Networking is opt-in per session. The Wi-Fi + Proton VPN binding turns the
-- radio back on explicitly after this startup baseline.
o.exec_on_start("nmcli radio wifi off")
-- Speak incoming notifications aloud (Piper TTS). Toggle with SUPER+ALT+V.
o.launch_on_start("omarchy-speak-notifications")

-- Read the weekly "next steps" recap aloud at login (Piper TTS).
-- Toggle the boot readout with `omarchy-speak-recap-toggle`; SUPER+ALT+W
-- speaks it on demand. --boot => obeys the on/off state + waits for audio.
o.exec_on_start("omarchy-speak-recap --boot")

-- Turn on the recall trainer (~/.local/bin/omarchy-recall): spaced-repetition
-- lessons/quizzes (memory techniques, trivia, English vocabulary), reviewed
-- with SUPER SHIFT ALT + R. `on` is idempotent and spins up its own transient
-- systemd --user daemon, which does NOT survive reboot on its own -- hence
-- re-asserting it here every login.
o.exec_on_start("omarchy-recall on")

-- Run post-boot hooks after the graphical session is ready.
o.exec_on_start("sleep 2 && omarchy-hook post-boot")

-- Refresh the multi-sector morning brief after every graphical login.
o.exec_on_start("sleep 15 && systemctl --user start --no-block omarchy-morning-brief.service")
