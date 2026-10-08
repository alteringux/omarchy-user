#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/user/one" "$ROOT/user/two" "$ROOT/user/bad" "$ROOT/packaged/core" "$ROOT/usage"
cat >"$ROOT/user/one/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"user.one","name":"One","kinds":["bar-widget"],"entryPoints":{}}
JSON
cat >"$ROOT/user/two/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"user.two","name":"Two","kinds":["bar-widget"],"entryPoints":{}}
JSON
printf '{malformed' >"$ROOT/user/bad/manifest.json"
cat >"$ROOT/packaged/core/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"omarchy.core","name":"Core","kinds":["panel"],"entryPoints":{}}
JSON
cat >"$ROOT/user/one/unused.json" <<'JSON'
{}
JSON
cat >"$ROOT/shell.json" <<'JSON'
{"bar":{"layout":{"left":[{"id":"user.one"}]}},"plugins":[],"disabledPlugins":["omarchy.core"]}
JSON
cat >"$ROOT/usage/user.one.json" <<'JSON'
{"version":1,"firstAt":1700000000000,"actions":{"open":{"count":4,"lastAt":1700086400000,"recent":[]}}}
JSON
cat >"$ROOT/usage/user.two.json" <<'JSON'
not-json
JSON

export PYTHONPATH="$HERE/local-bin"
export OMARCHY_PLUGIN_USER_DIR="$ROOT/user"
export OMARCHY_PLUGIN_PACKAGED_DIR="$ROOT/packaged"
export OMARCHY_PLUGIN_USAGE_DIR="$ROOT/usage"
export OMARCHY_PLUGIN_SHELL_CONFIG="$ROOT/shell.json"
export OMARCHY_PLUGIN_USAGE_NOW_MS=1700345600000
report="$("$HERE/local-bin/omarchy-plugin-usage" --json --days 3)"
REPORT="$report" python3 - <<'PY'
import json, os
r = json.loads(os.environ["REPORT"])
assert [p["id"] for p in r["plugins"]] == ["user.one", "omarchy.core", "user.two"]
one, core, two = r["plugins"]
assert one["uses"] == 4 and one["tracked"] and one["daysIdle"] == 3 and one["enabled"]
assert core["tracked"] is False and not core["neverUsed"] and core["uses"] == 0 and not core["enabled"]
assert two["tracked"] and two["neverUsed"] and two["uses"] == 0 and two["daysIdle"] is None
assert r["summary"] == {"tracked": 2, "untracked": 1, "neverUsed": 1, "stale": 2}
PY

# OMARCHY_PATH is the packaged-root source of truth when no explicit override
# is supplied (development installs use this instead of /usr/share/omarchy).
mkdir -p "$ROOT/dev-omarchy/shell/plugins/dev"
cat >"$ROOT/dev-omarchy/shell/plugins/dev/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"omarchy.dev","name":"Dev packaged","kinds":["panel"],"entryPoints":{}}
JSON
unset OMARCHY_PLUGIN_PACKAGED_DIR
export OMARCHY_PATH="$ROOT/dev-omarchy"
dynamic="$("$HERE/local-bin/omarchy-plugin-usage" --json --days 3)"
REPORT="$dynamic" python3 - <<'PY'
import json, os
r = json.loads(os.environ["REPORT"])
packaged = [p for p in r["plugins"] if p["id"] == "omarchy.dev"]
assert len(packaged) == 1 and packaged[0]["source"] == "packaged"
PY
printf 'ok - OMARCHY_PATH packaged root\n'
printf 'ok - omarchy-plugin-usage\n'
