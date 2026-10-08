#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
probe_dir="$(mktemp -d)"
trap 'rm -rf -- "$probe_dir"' EXIT

# Quickshell's native PanelWindow needs a Wayland session. Exercise the real
# dictionary and shell components without launching lookup/AI processes.
ln -s "$(realpath "$test_dir/../..")" "$probe_dir/plugins"
ln -s /usr/share/omarchy/shell/Commons "$probe_dir/Commons"
ln -s /usr/share/omarchy/shell/Ui "$probe_dir/Ui"
cp "$test_dir/tst_scroll.qml" "$probe_dir/shell.qml"
timeout 15s quickshell --no-color -p "$probe_dir/shell.qml" > "$probe_dir/output" 2>&1
cat "$probe_dir/output"
grep -q 'DICTIONARY_SCROLL_RESULT: 0 failures' "$probe_dir/output"
