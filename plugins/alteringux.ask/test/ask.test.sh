#!/usr/bin/env bash
# Focused black-box coverage for omarchy-nanogpt-ask. The QML overlay clears
# its input between turns; this suite verifies the helper receives one current
# prompt at a time and replaces tagged speech before starting a new turn.
set -uo pipefail

ASK="${OMARCHY_ASK_BIN:-$HOME/.config/omarchy/local-bin/omarchy-nanogpt-ask}"
[ -x "$ASK" ] || { echo "not executable: $ASK" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN"
PROMPTS="$WORK/prompts"
EVENTS="$WORK/events"
TTS_TEXT="$WORK/tts-text"
export PROMPTS EVENTS TTS_TEXT

cat > "$BIN/llm-agent" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
prompt=""
seen_separator=false
for arg in "$@"; do
  if $seen_separator; then prompt="$arg"; break; fi
  [ "$arg" = "--" ] && seen_separator=true
done
printf '%s\n' "$prompt" >> "$PROMPTS"
printf 'llm\n' >> "$EVENTS"
printf 'answer for %s\n' "$prompt"
STUB

cat > "$BIN/piper-tts" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
if [[ " $* " == *" --stop "* ]]; then
  printf 'stop\n' >> "$EVENTS"
else
  cat > "$TTS_TEXT"
  printf 'speak\n' >> "$EVENTS"
fi
STUB
chmod +x "$BIN/llm-agent" "$BIN/piper-tts"
export PATH="$BIN:/usr/bin:/bin"

pass=0
fail=0
ok() { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }

first="$WORK/first.out"
second="$WORK/second.out"
"$ASK" --no-voice '  first   prompt  ' > "$first"
"$ASK" --no-voice 'second prompt' > "$second"

mapfile -t prompts < "$PROMPTS"
[ "${#prompts[@]}" -eq 2 ] && [ "${prompts[0]}" = 'first prompt' ] && [ "${prompts[1]}" = 'second prompt' ] \
  && ok "each turn sends only its normalized current prompt" \
  || bad "current prompts" "${prompts[*]-missing}"
[ "$(<"$first")" = 'answer for first prompt' ] && [ "$(<"$second")" = 'answer for second prompt' ] \
  && ok "answers remain associated with their current prompt" \
  || bad "answers" "first=$(<"$first") second=$(<"$second")"

: > "$EVENTS"
voice_out="$WORK/voice.out"
"$ASK" --voice 'voice prompt' > "$voice_out"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$TTS_TEXT" ] && break
  sleep 0.01
done
sleep 0.02
mapfile -t events < "$EVENTS"
[ "${events[0]-}" = stop ] && [ "${events[1]-}" = llm ] && [ "${events[2]-}" = speak ] \
  && ok "voice replacement stops the tagged speech before the new request" \
  || bad "voice lifecycle" "${events[*]-missing}"
[ "$(<"$TTS_TEXT")" = 'answer for voice prompt' ] && [ "$(<"$voice_out")" = 'answer for voice prompt' ] \
  && ok "voice speaks the current answer only" \
  || bad "voice answer" "tts=$(<"$TTS_TEXT") output=$(<"$voice_out")"

echo
echo "ask helper test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
