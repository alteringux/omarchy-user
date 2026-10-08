#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
probe_config="$(mktemp -d)"
trap 'rm -rf -- "$probe_config"' EXIT

QT_QPA_PLATFORM=offscreen XDG_CONFIG_HOME="$probe_config" \
  /usr/lib/qt6/bin/qmltestrunner -input "$test_dir/tst_output_text.qml"
