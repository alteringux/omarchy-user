#!/usr/bin/env python3
"""Exercise the owned button's attached press signal with inert handlers.

No window is created. This tests the production handler and availability guard;
it does not establish external AT-SPI delivery or native keyboard behavior.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[4]
with tempfile.TemporaryDirectory(prefix="omarchy-action-button-") as raw:
    scratch = Path(raw)
    (scratch / "qs").symlink_to("/usr/share/omarchy/shell", target_is_directory=True)
    kit = scratch / "kit"
    kit.symlink_to(repo / "plugins/alteringux.kit", target_is_directory=True)
    probe = scratch / "Probe.qml"
    probe.write_text('''import QtQuick
import Quickshell
import "kit" as Kit
ShellRoot {
  property int invocations: 0
  Item {
    Kit.ActionButton {
      id: button
      text: "Synthetic action"
      onClicked: invocations++
    }
  }
  Component.onCompleted: {
    const checks = []
    checks.push(button.focusable && button.Accessible.role === Accessible.Button
      && button.Accessible.name === "Synthetic action")
    button.Accessible.pressAction()
    checks.push(invocations === 1)
    button.enabled = false
    button.Accessible.pressAction()
    checks.push(invocations === 1)
    button.enabled = true
    button.visible = false
    button.Accessible.pressAction()
    checks.push(invocations === 1)
    console.log("ACTION_BUTTON_RESULT " + JSON.stringify({checks: checks, invocations: invocations}))
    Qt.callLater(Qt.quit)
  }
}
''')
    env = os.environ.copy()
    env["QT_QPA_PLATFORM"] = "offscreen"
    env["QT_QPA_PLATFORMTHEME"] = "generic"
    env["QT_QUICK_BACKEND"] = "software"
    env["QML_IMPORT_PATH"] = str(scratch)
    env["XDG_CONFIG_HOME"] = str(scratch / "config")
    runtime = scratch / "runtime"
    runtime.mkdir(mode=0o700)
    env["XDG_RUNTIME_DIR"] = str(runtime)
    try:
        result = subprocess.run(["timeout", "2s", "quickshell", "--path", str(probe), "--no-color"],
                                env=env, capture_output=True, text=True, timeout=8)
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or b"") + (error.stderr or b"")
        raise SystemExit("Button fixture timed out:\n" + output.decode(errors="replace")[-2000:])
    matches = re.findall(r"ACTION_BUTTON_RESULT (\{.*\})", result.stdout + result.stderr)
    if not matches:
        raise SystemExit((result.stdout + result.stderr)[-2000:])
    report = json.loads(matches[-1])
    print(json.dumps(report))
    raise SystemExit(0 if result.returncode in (0, 124) and all(report["checks"]) else 1)
