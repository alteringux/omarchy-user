-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- Remap every PRINT-based default binding onto F4 (same modifiers).
hl.unbind("PRINT")
hl.unbind("ALT + PRINT")
hl.unbind("SUPER + PRINT")
hl.unbind("SUPER + CTRL + PRINT")
o.bind("F4", "Screenshot", "omarchy-capture-screenshot")
o.bind("ALT + F4", "Screenrecording", "omarchy-capture-screenrecording --stop-recording || omarchy-menu toggle trigger.capture.screenrecord")
o.bind("SUPER + F4", "Color picker", "pkill hyprpicker || hyprpicker -a")
o.bind("SUPER + CTRL + F4", "Extract text (OCR) from screenshot", "omarchy-capture-text")
o.bind("SUPER + CTRL + ALT + F4", "Narrate screenshot (OCR + TTS, press again to stop)", "omarchy-narrate-screenshot")

-- Pomodoro plugin (alteringux.pomodoro): -q so a keybinding no-ops
-- silently instead of erroring when the shell isn't running.
o.bind("SUPER + ALT + P", "Pomodoro start/pause", "omarchy-shell -q alteringux.pomodoro togglePause")
o.bind("SUPER + ALT + S", "Pomodoro skip phase", "omarchy-shell -q alteringux.pomodoro skipPhase")
o.bind("SUPER + ALT + R", "Pomodoro reset session", "omarchy-shell -q alteringux.pomodoro resetSession")

-- Countdown plugin (alteringux.countdown): multi-entry "days until <event>"
-- tracker. One key toggles the add/list overlay; the overlay takes a day
-- count + a label and the bar shows a scrolling marquee of every countdown.
o.bind("SUPER + ALT + C", "Countdowns: open panel", "omarchy-shell -q alteringux.countdown toggle")

-- Panel-open shortcuts for the remaining alteringux.* shell plugins, so every
-- one built so far has a desktop keybind. Pomodoro (P/S/R) and Countdown (C)
-- above already carry their own; Dictionary is on SUPER + D further down.
-- Dashboard has no IpcHandler of its own, so it rides the generic
-- `shell toggle <id>` route (works because its bar widget exposes open/close/opened).
o.bind("SUPER + ALT + J", "Pomodoro: open panel", "omarchy-shell -q alteringux.pomodoro toggle")
o.bind("SUPER + ALT + O", "Score: open panel", "omarchy-shell -q alteringux.score toggle")
o.bind("SUPER + ALT + L", "Stocks: open panel", "omarchy-shell -q alteringux.stocks toggle")
o.bind("SUPER + ALT + U", "Stopwatch: open panel", "omarchy-shell -q alteringux.stopwatch toggle")
o.bind("SUPER + ALT + H", "Dashboard: open panel", "omarchy-shell -q shell toggle alteringux.dashboard")
o.bind("SUPER + SHIFT + ALT + K", "Recall: open panel", "omarchy-shell -q alteringux.recall toggle")

-- Conductor plugin (alteringux.conductor): runs whole "rituals" -- ordered
-- sequences of every other alteringux plugin's CLI verb -- and shows a live
-- cockpit of all of them. All on the SUPER+CTRL+ALT layer (SUPER+ALT is fully
-- saturated): C opens the panel, F/G/H fire a ritual headless via
-- ~/.local/bin/omarchy-conductor. Verified free against `hyprctl binds`.
o.bind("SUPER + CTRL + ALT + C", "Conductor: open panel", "omarchy-shell -q alteringux.conductor toggle")
o.bind("SUPER + CTRL + ALT + F", "Conductor: run Focus ritual", "omarchy-conductor run focus")
o.bind("SUPER + CTRL + ALT + G", "Conductor: run Morning ritual", "omarchy-conductor run morning")
o.bind("SUPER + CTRL + ALT + H", "Conductor: run Wind-down ritual", "omarchy-conductor run winddown")

-- Narrator: read selected/copied text aloud (press again to stop)
o.bind("SUPER + ALT + N", "Narrate selection", "omarchy-narrate")

-- Reframe: local Ollama gist + "seen differently" perspectives of the
-- selection, spoken via Piper TTS. Offline; press again to stop.
o.bind("SUPER + SHIFT + ALT + N", "Reframe selection (gist + other perspectives, TTS)", "omarchy-reframe")

-- Prompt Opt: classify the selected/copied rough requirement (code / debug /
-- research / writing / data), rewrite it with a context-specific system prompt
-- into a lean Task/Constraints/Context/Output prompt via NanoGPT, copy to
-- the clipboard, toast the detected context + before/after token estimate.
o.bind("SUPER + SEMICOLON", "Optimize selection into a lean prompt (clipboard)", "omarchy-promptopt")

-- Spoken notifications: toggle reading incoming notifications aloud (Piper TTS)
o.bind("SUPER + ALT + V", "Spoken notifications: toggle", "omarchy-speak-notifications-toggle")

-- Dictionary: highlight a word then press, or press with nothing selected
-- to type one.
o.bind("SUPER + D", "Dictionary lookup", "omarchy-dictionary-hotkey")

-- Wordstep: selected text, one Piper-synchronised word at a time.
o.bind("SUPER + CTRL + ALT + E", "Read selection word by word", "omarchy-wordstep-hotkey")

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Typing Trainer
o.bind("SUPER + SHIFT + T", "Typing Trainer", "omarchy-launch-webapp http://localhost:8765")

-- Voxtype: push-to-talk voice-to-text
o.bind("SUPER + H", "Voxtype: toggle dictation", "voxtype record toggle")

-- Voice assistant (~/.local/bin/omarchy-voice): speak a request, it either
-- performs a system action (brightness, volume, theme, night light, lock,
-- launch an app) or answers aloud. STT = whisper-cli, intent parsing +
-- chat = NanoGPT, reply = Piper TTS. Auto-stops on ~1.5s of silence.
-- SUPER+ALT+X = listen & act; a bare press with X again stops it talking.
o.bind("SUPER + ALT + X", "Voice assistant: listen & act", "omarchy-voice")
o.bind("SUPER + SHIFT + ALT + V", "Voice assistant: stop talking", "omarchy-voice --stop")

-- Toggle the clock widget in the Omarchy bar (shell.json hot-reloads)
o.bind("SUPER + ALT + T", "Toggle bar clock", "omarchy-toggle-clock")

-- Hide/show the top bar. The bottom news bar watches the same `bar-off` flag,
-- so it hides and shows along with the top bar.
hl.unbind("SUPER + SHIFT + B")
o.bind("SUPER + SHIFT + B", "Toggle bar (top + bottom)", "omarchy-toggle-bar")

-- Toggle the bottom news bar's layout: press once to hide the left
-- (stories) half and let the news crawl fill the whole bar; press again
-- to go back to the 50/50 split.
-- (SUPER + SHIFT + N is Omarchy's Editor launcher, so this rides PERIOD.)
o.bind("SUPER + SHIFT + PERIOD", "News bar: toggle full-width news / split", "omarchy-shell -q alteringux.newsbar cycleHalves")

-- Speak the current time aloud (Piper TTS; press again to stop).
-- SUPER + ALT + T is taken by the bar-clock toggle above, so this lives on Y.
o.bind("SUPER + ALT + Y", "Speak the time", "omarchy-speak-time")

-- Speak a daily briefing aloud: date, weather, local happenings
-- (wttr.in + Anthropic web search; press again to stop).
o.bind("SUPER + ALT + B", "Speak daily briefing", "omarchy-speak-briefing")

-- AI briefing notification on demand: same script the post-boot hook runs,
-- via llm-blurb (hermes -> NanoGPT). Pops a desktop notification, no TTS.
-- (SUPER + ALT + B is the spoken briefing above; this text one lives on Q.)
o.bind("SUPER + ALT + Q", "AI briefing notification", "/home/alteringux/.config/omarchy/hooks/post-boot.d/briefing.sh")

-- Speak an AI briefing of how the Australian share market is doing today:
-- ASX 200 / All Ords / AUDUSD from Yahoo Finance (same keyless API as the
-- alteringux.stocks plugin), then the day's top 10 gainers and top 10
-- losers each with a one-line reason. Movers colour comes from a NanoGPT
-- tool-calling loop (llm-agent) searching the local SearXNG, not Anthropic.
-- Piper TTS; press again to stop. A re-press within 10 min replays.
-- Lives on CTRL+ALT+L (pairs with the Stocks panel on SUPER+ALT+L); the
-- old SUPER+ALT+F collided with Omarchy's default "Full width" action.
o.bind("SUPER + CTRL + ALT + L", "Speak ASX market briefing", "omarchy-speak-asx")

-- Open the local SearXNG metasearch (the searxng.service --user unit that
-- llm-agent's web_search also uses) in the default browser. No args = home
-- page, which is also where Zen offers "Add Search Engine" for the address
-- bar. S = Search, same modifier family as the ASX briefing on L.
o.bind("SUPER + CTRL + ALT + S", "Open SearXNG search", "omarchy-searxng")

-- Speak the day's 10 most interesting Reddit stories (Piper TTS; press again
-- to stop). Ranking self-tunes: subreddits you hear out float up, ones you
-- stop early on sink. State in ~/.local/state/omarchy-speak-reddit/.
o.bind("SUPER + ALT + I", "Speak top Reddit stories", "omarchy-speak-reddit")

-- Speak the weekly "next steps for self-improvement" recap aloud
-- (from ~/Documents/terminal-recap-7d.md; press again to stop).
-- Also runs at login unless disabled with omarchy-speak-recap-toggle.
o.bind("SUPER + ALT + W", "Speak weekly recap", "omarchy-speak-recap")

-- Open Executive thin client (omarchy-executive)
o.bind("SUPER + ALT + E", "Open Executive: chat", "omarchy-launch-or-focus-tui omarchy-executive repl")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- TTS dialogue overlay (~/Work/tts-dialogue-overlay): two synthetic voices
-- hold a conversation with each other. D = the overlay itself, G = its
-- settings panel, SHIFT+D = play/pause, SHIFT+ALT+D = skip a turn. The
-- play/pause + skip binds drop a two-line flag file (action + nonce) that
-- the running app polls; the app must already be up for those to do anything.
o.bind("SUPER + ALT + D", "TTS dialogue: toggle overlay", "tts-dialogue-overlay --toggle")
o.bind("SUPER + ALT + G", "TTS dialogue: settings panel", [[sh -c 'd="$XDG_RUNTIME_DIR/tts-dialogue-overlay"; mkdir -p "$d"; { echo toggle; date +%s%N; } > "$d/settings.flag"']])
o.bind("SUPER + SHIFT + D", "TTS dialogue: play/pause", [[sh -c 'd="$XDG_RUNTIME_DIR/tts-dialogue-overlay"; mkdir -p "$d"; { echo toggle; date +%s%N; } > "$d/control.flag"']])
o.bind("SUPER + SHIFT + ALT + D", "TTS dialogue: skip turn", [[sh -c 'd="$XDG_RUNTIME_DIR/tts-dialogue-overlay"; mkdir -p "$d"; { echo skip; date +%s%N; } > "$d/control.flag"']])

-- TTS roleplay overlay (~/Work/tts-roleplay-overlay): two synthetic voices act
-- out a scene you set. Each character has a one-line role instruction on the
-- card; the main input is the scene setter. A = show/hide the card (the scene
-- keeps running in the background either way), ALT+CTRL+A = its settings panel,
-- SHIFT+A = play/pause, SHIFT+CTRL+A = skip a turn, CTRL+ALT+SHIFT+A =
-- push-to-talk (speak a line into the scene). The flag-file binds need the
-- app already running to do anything.
o.bind("SUPER + ALT + A", "TTS roleplay: show/hide overlay", "tts-roleplay-overlay --visibility")
-- The flag payload MUST be written in one shot (printf, not `{ echo; date; }`)
-- so the app's file watcher never sees a half-written `cmd\n` — a split write
-- makes it fire twice per press and cancel itself out.
o.bind("SUPER + ALT + CTRL + A", "TTS roleplay: settings panel", [[sh -c 'd="$XDG_RUNTIME_DIR/tts-roleplay-overlay"; mkdir -p "$d"; printf "toggle\n%s\n" "$(date +%s%N)" > "$d/settings.flag"']])
o.bind("SUPER + SHIFT + A", "TTS roleplay: play/pause", [[sh -c 'd="$XDG_RUNTIME_DIR/tts-roleplay-overlay"; mkdir -p "$d"; printf "toggle\n%s\n" "$(date +%s%N)" > "$d/control.flag"']])
o.bind("SUPER + SHIFT + CTRL + A", "TTS roleplay: skip turn", [[sh -c 'd="$XDG_RUNTIME_DIR/tts-roleplay-overlay"; mkdir -p "$d"; printf "skip\n%s\n" "$(date +%s%N)" > "$d/control.flag"']])
o.bind("SUPER + CTRL + ALT + SHIFT + A", "TTS roleplay: push-to-talk", [[sh -c 'd="$XDG_RUNTIME_DIR/tts-roleplay-overlay"; mkdir -p "$d"; printf "talk\n%s\n" "$(date +%s%N)" > "$d/control.flag"']])

-- Work showcase (~/Work/showcase/index.html): carousel intro of every
-- project built so far. Single self-contained HTML file, opened app-mode.
-- (SUPER+ALT+K is a preinstalled Omarchy binding for the Tmux keybindings
-- cheatsheet, so this lives on Z.)
o.bind("SUPER + ALT + Z", "Work showcase", "omarchy-launch-webapp file:///home/alteringux/Work/showcase/index.html")

-- Video Shuffler (~/Work/video-shuffler): slice a video into fixed-length
-- chunks and play them back in a random order; with Loop on it re-shuffles
-- every restart. Single-instance -- a second press focuses the open window.
o.bind("SUPER + ALT + M", "Video Shuffler", "/home/alteringux/Work/video-shuffler/video-shuffler")

-- Background noise (~/.local/bin/bg-noise-toggle): play an .m4a from
-- ~/Music/random on an infinite loop, no window, detached. Press again to
-- stop. State is a PID file at $XDG_RUNTIME_DIR/bg-noise.pid.
o.bind("SUPER + CTRL + ALT + M", "Background noise: loop/stop", "bg-noise-toggle")

-- There is no "reopen a closed app with its state" in Hyprland -- once the
-- process exits its unsaved state is gone -- so SUPER + W now HIDES the window
-- instead: it is parked in the scratchpad special workspace, process and all
-- state alive. SUPER + SHIFT + S pulls the most recently hidden window back to
-- the current workspace and focuses it. A hidden window auto-closes 5 minutes
-- later unless retrieved by then (see ~/.local/bin/omarchy-hide-window).
-- The real "Close window" action lives on SUPER + SHIFT + W.
hl.unbind("SUPER + W")
hl.unbind("SUPER + SHIFT + W") -- was: Omawrite (preinstalled webapp binding)
hl.unbind("SUPER + SHIFT + S") -- was: Google Maps (preinstalled webapp binding)
o.bind("SUPER + W", "Hide window (scratchpad, auto-close 5 min)", "omarchy-hide-window")
o.bind("SUPER + SHIFT + W", "Close window", hl.dsp.window.close())
o.bind("SUPER + SHIFT + S", "Unhide last hidden window", "omarchy-hide-window --unhide")

-- SUPER + ALT + DELETE hides every window at once -- same scratchpad-park +
-- 5-min auto-close as SUPER + W, one reaper per window, then drop onto a clean
-- workspace 1. Restore them one at a time with SUPER + SHIFT + S.
-- (CTRL + ALT + DELETE keeps its Omarchy default: really close all windows.)
-- This laptop's apple-spi-keyboard sends BackSpace for the key labelled
-- "delete" (Delete needs Fn), so bind the BACKSPACE twin too -- same trick
-- Omarchy uses for SUPER+CTRL+Delete / SUPER+CTRL+BACKSPACE.
o.bind("SUPER + ALT + DELETE", "Hide all windows (scratchpad, auto-close 5 min)", "omarchy-hide-window --hide-all")
o.bind("SUPER + ALT + BACKSPACE", "Hide all windows (scratchpad, auto-close 5 min)", "omarchy-hide-window --hide-all")

-- Toggle lid-close suspend (~/.local/bin/lid-suspend-toggle). "OFF" holds a
-- user-session handle-lid-switch block inhibitor so closing the lid no longer
-- suspends -- the screen still locks + the internal panel blanks. Clears on
-- reboot. SUPER+CTRL+L is Omarchy's Lock and SUPER+L its layout toggle, so
-- this rides SHIFT.
o.bind("SUPER + SHIFT + L", "Toggle lid-close suspend", "lid-suspend-toggle")

-- Recall (~/.local/bin/omarchy-recall): opens a terminal running the
-- interactive review session -- unseen lessons, then due quiz/vocab cards,
-- self-graded again/hard/good/easy (SM-2 spaced repetition).
o.bind("SUPER + SHIFT + ALT + R", "Recall: review now", "omarchy-launch-terminal omarchy-recall review")

-- God's Eye View (~/Work/gods-eye-view): real-time 3D globe intelligence
-- console. Runs keyless off a gev-server.service --user unit (survives reboot).
-- G opens/focuses it in a dedicated Chromium app window that also exposes the
-- DevTools port the voice bridge drives.
o.bind("SUPER + SHIFT + ALT + G", "God's Eye View: open / focus", "gev-open")
-- E = push-to-talk voice control. Tap once to start recording, tap again to
-- send: whisper-cli transcribes, gev-agent (Claude + GEV's own tool schema,
-- over CDP) drives the globe, Piper speaks the reply. There is no Anthropic
-- equivalent of GEV's built-in OpenAI Realtime voice, so this is the stand-in.
o.bind("SUPER + SHIFT + ALT + E", "God's Eye View: voice command (tap twice)", "gev-voice")

-- Wi-Fi + Proton VPN (~/.local/bin/omarchy-wifi-vpn). Networking is opt-in per
-- session (hypr/autostart.lua kills the Wi-Fi radio on every login). This
-- brings it back in the right order: radio on -> wait for a real wifi link ->
-- protonvpn-rotate connect. Toggle -- press again to drop the VPN and radio.
-- (SUPER+CTRL+ALT+W is Omarchy's "Toggle weather", so this rides N = oNline.)
o.bind("SUPER + CTRL + ALT + N", "Wi-Fi + Proton VPN: toggle online/offline", "omarchy-wifi-vpn toggle")

-- Breathe plugin (alteringux.breathe): guided breathing. -q so a keybinding
-- no-ops silently instead of erroring when the shell isn't running.
-- SUPER + ALT is fully allocated, so these sit in the SUPER + CTRL + ALT space.
o.bind("SUPER + CTRL + ALT + B", "Breathe: start/pause session", "omarchy-shell -q alteringux.breathe toggle")
o.bind("SUPER + SHIFT + ALT + B", "Breathe: open panel", "omarchy-shell -q alteringux.breathe panel")
-- The panic button: one physiological sigh is the fastest way down from a
-- spike, and it wants to be reachable without picking anything.
o.bind("SUPER + CTRL + ALT + Q", "Breathe: quick calming sigh", "omarchy-shell -q alteringux.breathe start physiological-sigh")

-- Font showcase: open Omarchy's searchable font preview picker directly.
o.bind("SUPER + CTRL + SHIFT + F", "Font showcase", "omarchy menu summon style.font")
