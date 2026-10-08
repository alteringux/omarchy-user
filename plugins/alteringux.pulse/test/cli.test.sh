#!/usr/bin/env bash
# Black-box checks for the pulse CLI's shared activity log.
#
#   OMARCHY_PULSE_BIN=... bash test/cli.test.sh
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CLI="${OMARCHY_PULSE_BIN:-$REPO/local-bin/omarchy-pulse}"
PULSE_DIR="${OMARCHY_PULSE_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export OMARCHY_STATE_DIR="$WORK"
export OMARCHY_PULSE_DIR="$PULSE_DIR"
export OMARCHY_PULSE_QUIET=1

pass=0
fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }

# Each log prunes the append-only file. The append and prune must share one
# transaction or a stale prune snapshot can replace a newer append.
expected=24
for i in $(seq 1 "$expected"); do
  "$CLI" log alteringux.test "concurrent-$i" &
done
wait

actual="$(jq -s 'length' "$WORK/alteringux-activity.jsonl")"
messages="$(jq -rs '[.[].message] | map(select(startswith("concurrent-"))) | length' "$WORK/alteringux-activity.jsonl")"
[ "$actual" = "$expected" ] && ok "concurrent logs retain every event" \
  || bad "concurrent logs" "expected $expected events, got $actual"
[ "$messages" = "$expected" ] && ok "retained events preserve their messages" \
  || bad "concurrent messages" "expected $expected messages, got $messages"

# Exercise the exact argv emitted by Panel.qml's clearOne / clearAll buttons.
"$CLI" attention alteringux.one --label "one" >/dev/null
"$CLI" attention alteringux.two --label "two" >/dev/null
"$CLI" clear alteringux.one
if [ "$(jq -r '.items["alteringux.one"] // empty' "$WORK/alteringux-attention.json")" = "" ] \
  && [ "$(jq -r '.items["alteringux.two"].label' "$WORK/alteringux-attention.json")" = "two" ]; then
  ok "clearOne removes only the selected alert"
else
  bad "clearOne mutation" "$(cat "$WORK/alteringux-attention.json")"
fi
"$CLI" clear --all
if [ "$(jq -r '.items | length' "$WORK/alteringux-attention.json")" = "0" ]; then
  ok "clearAll removes every alert"
else
  bad "clearAll mutation" "$(cat "$WORK/alteringux-attention.json")"
fi

cat > "$WORK/usage.json" <<'JSON'
{"version":1,"generatedAt":1700000000000,"thresholdDays":30,"plugins":[
  {"id":"alteringux.cold","label":"Cold","source":"user","enabled":true,"tracked":true,"uses":1,"lastAt":1,"daysIdle":42,"neverUsed":false},
  {"id":"alteringux.untracked","label":"Untracked","source":"packaged","enabled":true,"tracked":false,"uses":0,"lastAt":0,"daysIdle":null,"neverUsed":false}
],"summary":{"tracked":1,"untracked":1,"neverUsed":0,"stale":1}}
JSON
cat > "$WORK/plugin-usage" <<'SH'
#!/usr/bin/env bash
cat "$OMARCHY_PLUGIN_USAGE_SOURCE"
SH
chmod +x "$WORK/plugin-usage"
export OMARCHY_PLUGIN_USAGE_BIN="$WORK/plugin-usage"
export OMARCHY_PLUGIN_USAGE_SOURCE="$WORK/usage.json"

"$CLI" status > "$WORK/status.json"
[ "$(jq -r '.usage.summary.stale' "$WORK/status.json")" = "1" ] && ok "status reports stale plugin usage" \
  || bad "status usage" "stale summary missing"
[ "$(jq -r --arg key plugin-usage '.items[$key].label' "$WORK/alteringux-attention.json")" = "Plugin usage stale: alteringux.cold (42d idle)" ] \
  && ok "stale usage attention names plugin and idle days" \
  || bad "usage attention" "$(jq -c --arg key plugin-usage '.items[$key]' "$WORK/alteringux-attention.json")"
"$CLI" get > "$WORK/get.json"
[ "$(jq -r '.usage.summary.stale' "$WORK/get.json")" = "1" ] \
  && ok "get exposes the usage batch" \
  || bad "get usage" "usage missing from get response"

"$CLI" status >/dev/null
[ "$(jq -r --arg key plugin-usage '(.items[$key] != null)' "$WORK/alteringux-attention.json")" = "true" ] \
  && ok "usage attention remains deduplicated" \
  || bad "usage dedupe" "$(cat "$WORK/alteringux-attention.json")"

"$CLI" clear --all
"$CLI" status >/dev/null
[ "$(jq -r --arg key plugin-usage '(.items[$key] != null)' "$WORK/alteringux-attention.json")" = "false" ] \
  && ok "clearing stale usage remains clear across refresh" \
  || bad "usage acknowledgement" "$(cat "$WORK/alteringux-attention.json")"

jq --argjson at "$((1700345600000 - 31 * 86400000))" \
  '.plugins[0].uses=2 | .plugins[0].lastAt=$at' "$WORK/usage.json" > "$WORK/.usage"
mv "$WORK/.usage" "$WORK/usage.json"
"$CLI" status >/dev/null
[ "$(jq -r --arg key plugin-usage '(.items[$key] != null)' "$WORK/alteringux-attention.json")" = "true" ] \
  && ok "newer stale usage re-alerts" \
  || bad "newer usage acknowledgement" "$(cat "$WORK/alteringux-attention.json")"

jq -n '{version:1,items:{"plugin-usage":{label:"manual",level:"critical",action:"user-command",actionLabel:"Manual",ts:1}}}' \
  > "$WORK/alteringux-attention.json"
"$CLI" status >/dev/null
"$CLI" clear plugin-usage
[ "$(jq -r '.items["plugin-usage"].action' "$WORK/alteringux-attention.json")" = "user-command" ] \
  && ok "clearing usage preserves manual attention" \
  || bad "manual attention preservation" "$(cat "$WORK/alteringux-attention.json")"
"$CLI" status >/dev/null
[ "$(jq -r '.items["plugin-usage"].action' "$WORK/alteringux-attention.json")" = "user-command" ] \
  && ok "manual attention survives repeated stale refresh" \
  || bad "manual attention refresh" "$(cat "$WORK/alteringux-attention.json")"

# A pre-existing user item at the stable key is merged, not overwritten, and
# is restored when the stale condition clears.
jq -n '{version:1,items:{"plugin-usage":{label:"manual",level:"critical",action:"user-command",actionLabel:"Manual",ts:1}}}' \
  > "$WORK/alteringux-attention.json"
"$CLI" status >/dev/null
[ "$(jq -r --arg key plugin-usage '.items[$key].action' "$WORK/alteringux-attention.json")" = "user-command" ] \
  && ok "user plugin-usage action is preserved" \
  || bad "user attention merge" "$(cat "$WORK/alteringux-attention.json")"
cat > "$WORK/usage.json" <<'JSON'
{"version":1,"generatedAt":1700000000000,"thresholdDays":30,"plugins":[
  {"id":"alteringux.recent","label":"Recent","source":"user","enabled":true,"tracked":true,"uses":2,"lastAt":1700000000000,"daysIdle":0,"neverUsed":false}
],"summary":{"tracked":1,"untracked":0,"neverUsed":0,"stale":0}}
JSON
"$CLI" status >/dev/null
[ "$(jq -r --arg key plugin-usage '.items[$key].label // empty' "$WORK/alteringux-attention.json")" = "manual" ] \
  && ok "user plugin-usage item survives stale clear" \
  || bad "user attention restore" "$(cat "$WORK/alteringux-attention.json")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
