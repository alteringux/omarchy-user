#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
tmp=$(mktemp -d)
runtime="$tmp/runtime"
home="$tmp/home"
tag=alteringux-wordstep-1000-1
job_pid=

cleanup() {
  if [[ -n "$job_pid" ]] && kill -0 "$job_pid" 2>/dev/null; then
    "$REPO/local-bin/piper-tts" --stop --tag "$tag" >/dev/null 2>&1 || true
    wait "$job_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$runtime/piper-tts" "$tmp/bin" "$home/.local/bin" \
  "$home/Work/bin" "$tmp/voices"
ln -s "$REPO/local-bin/piper-tts" "$home/.local/bin/piper-tts"
printf 'fixture\n' > "$tmp/voices/fixture.onnx"
printf '{"audio":{"sample_rate":22050}}\n' > "$tmp/voices/fixture.onnx.json"

cat > "$tmp/bin/piper" <<'SH'
#!/usr/bin/env bash
printf '\000\000\000\000'
SH
cat > "$tmp/bin/paplay" <<'SH'
#!/usr/bin/env bash
: > "$MOCK_PLAYER_STARTED"
cat "${@: -1}" >/dev/null
SH
cat > "$home/Work/bin/tts-player-ctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$MOCK_CTL_LOG"
SH
chmod +x "$tmp/bin/piper" "$tmp/bin/paplay" "$home/Work/bin/tts-player-ctl"

export HOME="$home"
export XDG_RUNTIME_DIR="$runtime"
export PATH="$tmp/bin:$PATH"
export PIPER_TTS_VOICE_DIR="$tmp/voices"
export PIPER_TTS_NOSTREAM0=1
export MOCK_PLAYER_STARTED="$tmp/player-started"
export MOCK_CTL_LOG="$tmp/ctl.log"

current="$runtime/piper-tts/current.json"
printf '{"tag":"other"}\n' > "$current"
exec {queue_fd}>"$runtime/piper-tts/queue.lock"
flock -x "$queue_fd"

"$REPO/local-bin/piper-tts" --tag "$tag" --voice fixture --workers 1 -- "Pause fixture." \
  >"$tmp/piper.log" 2>&1 &
job_pid=$!
for _ in {1..200}; do
  [[ -s "$runtime/piper-tts/$tag.pgid" ]] && break
  sleep 0.025
done
[[ -s "$runtime/piper-tts/$tag.pgid" ]] || {
  cat "$tmp/piper.log" >&2
  echo "FAIL: tagged Piper job did not reach its queue" >&2
  exit 1
}

"$REPO/local-bin/omarchy-wordstep-transport" pause "$tag"
[[ -e "$runtime/piper-tts/$tag.paused" ]]
flock -u "$queue_fd"

for _ in {1..200}; do
  if python3 - "$current" "$tag" <<'PY'
import json, sys
try:
    raise SystemExit(0 if json.load(open(sys.argv[1])).get("tag") == sys.argv[2] else 1)
except (OSError, ValueError):
    raise SystemExit(1)
PY
  then
    break
  fi
  sleep 0.025
done
sleep 0.15
[[ ! -e "$MOCK_PLAYER_STARTED" ]] || {
  echo "FAIL: queued speech started while paused" >&2
  exit 1
}

"$REPO/local-bin/omarchy-wordstep-transport" resume "$tag"
wait "$job_pid"
job_pid=
[[ ! -e "$runtime/piper-tts/$tag.paused" ]]
[[ -e "$MOCK_PLAYER_STARTED" ]]
echo "PASS: queued Wordstep speech stays silent until resumed"
