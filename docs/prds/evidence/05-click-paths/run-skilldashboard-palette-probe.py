#!/usr/bin/env python3
"""Evaluate the panel's real palette references in Quickshell, without a window."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[4]
source = (repo / "plugins/alteringux.skilldashboard/Panel.qml").read_text()
references = re.findall(r"\b(?:Kit\.Palette|root\._webPalette)\.[a-z]\w*", source)
assert references, "panel palette references must be exercised"
with tempfile.TemporaryDirectory(prefix="skilldashboard-palette-") as raw:
    scratch = Path(raw)
    (scratch / "qs").symlink_to("/usr/share/omarchy/shell", target_is_directory=True)
    (scratch / "kit").symlink_to(repo / "plugins/alteringux.kit", target_is_directory=True)
    probe = scratch / "Probe.qml"
    probe.write_text('''import QtQuick
import Quickshell
import "kit" as Kit
ShellRoot {
  id: root
  property QtObject _webPalette: Kit.Palette {}
  Component.onCompleted: {
    const values = [''' + ",".join(references) + ''']
    console.log("PALETTE_BINDING_RESULT " + JSON.stringify({
      checks: values.map(function(value) { return value !== undefined && /^#[0-9a-f]{6,8}$/i.test(String(value)) }),
      values: values.map(String)
    }))
    Qt.callLater(Qt.quit)
  }
}
''')
    runtime = scratch / "runtime"
    runtime.mkdir(mode=0o700)
    env = os.environ.copy()
    env.update(QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic",
               QT_QUICK_BACKEND="software", QML_IMPORT_PATH=raw,
               XDG_CONFIG_HOME=str(scratch / "config"), XDG_RUNTIME_DIR=str(runtime))
    result = subprocess.run(["quickshell", "--path", str(probe), "--no-color"],
                            env=env, capture_output=True, text=True, timeout=8)
    matches = re.findall(r"PALETTE_BINDING_RESULT (\{.*\})", result.stdout + result.stderr)
    if not matches:
        raise SystemExit((result.stdout + result.stderr)[-2000:])
    report = json.loads(matches[-1])
    print(json.dumps(report))
    raise SystemExit(0 if result.returncode == 0 and all(report["checks"]) else 1)
