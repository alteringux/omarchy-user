#!/usr/bin/env python3
"""Compile actual plugin QML with Quickshell; never instantiate plugin actions."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--package", default="", help="Restrict to one plugin directory, including nested QML")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[4]
plugins = (repo / "plugins").resolve()
scan_root = (plugins / args.package).resolve() if args.package else plugins
if not scan_root.is_dir() or not scan_root.is_relative_to(plugins):
    raise SystemExit("Plugin directory not found under plugins/")
files = sorted(
    file for file in scan_root.rglob("*.qml")
    if not {"test", "tests"}.intersection(file.relative_to(scan_root).parts[:-1])
)
if not files:
    raise SystemExit("No QML files matched")

with tempfile.TemporaryDirectory(prefix="omarchy-plugin-load-") as raw:
    scratch = Path(raw)
    (scratch / "qs").symlink_to("/usr/share/omarchy/shell", target_is_directory=True)
    source = '''import QtQuick
import Quickshell
ShellRoot {
  Component.onCompleted: {
    const urls = URLS
    const failures = []
    for (let i = 0; i < urls.length; i++) {
      const component = Qt.createComponent(urls[i], Component.PreferSynchronous)
      if (component.status !== Component.Ready)
        failures.push({file: urls[i], error: component.errorString()})
    }
    console.log("PLUGIN_LOAD_RESULTS " + JSON.stringify({count: urls.length, failures: failures}))
    Qt.quit()
  }
}
'''.replace("URLS", json.dumps([file.as_uri() for file in files]))
    probe = scratch / "LoadProbe.qml"
    probe.write_text(source)
    env = os.environ.copy()
    env["QML_IMPORT_PATH"] = str(scratch)
    # Quickshell's PanelWindow type is registered only by its Wayland backend.
    # Components are compiled, never created, so this maps no desktop window.
    env.pop("QT_QPA_PLATFORM", None)
    run = subprocess.run(["timeout", "8s", "quickshell", "--path", str(probe), "--no-color"],
                         env=env, capture_output=True, text=True, timeout=12)
    matches = re.findall(r"PLUGIN_LOAD_RESULTS (\{.*\})", run.stdout + run.stderr)
    if not matches:
        raise SystemExit("Compile probe did not report: " + (run.stdout + run.stderr)[-2000:])
    result = json.loads(matches[-1])
    for failure in result["failures"]:
        failure["file"] = failure["file"].replace(repo.as_uri() + "/", "")
        failure["error"] = failure["error"].replace(repo.as_uri() + "/", "")
    print(json.dumps(result, indent=2))
    raise SystemExit(1 if result["failures"] or run.returncode not in (0, 124) else 0)
