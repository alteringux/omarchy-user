#!/usr/bin/env python3
"""Check the actual shared reader in a private headless Wayland compositor."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--sway", type=Path, default=shutil.which("sway"))
args = parser.parse_args()
if args.sway is None or not args.sway.is_file():
    parser.error("Sway is required; supply --sway /absolute/path/to/sway")
sway_binary = args.sway.resolve()
fixture = Path(__file__).with_name("tst_reader_layout.qml")
with tempfile.TemporaryDirectory(prefix="omarchy-reader-layout-") as raw:
    scratch = Path(raw)
    (scratch / "qs").symlink_to("/usr/share/omarchy/shell", target_is_directory=True)
    repo = fixture.parents[4]
    for name in ("shared", "alteringux.kit"):
        (scratch / name).symlink_to(repo / "plugins" / name, target_is_directory=True)
    probe = scratch / "Probe.qml"
    probe.write_text(fixture.read_text().replace('"../../../../plugins/shared"', '"shared"'))
    runtime = scratch / "runtime"
    runtime.mkdir(mode=0o700)
    (scratch / "home").mkdir()
    config = scratch / "sway.conf"
    config.write_text("xwayland disable\noutput HEADLESS-1 resolution 800x600\n"
                      'for_window [app_id=".*"] floating enable\n')
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(("DBUS_", "HYPRLAND_", "SWAY", "QT_", "QML_", "QS_")) or key in {"DISPLAY", "WAYLAND_DISPLAY"}:
            env.pop(key)
    env.update(HOME=str(scratch / "home"), XDG_CONFIG_HOME=str(scratch / "home/config"),
               XDG_STATE_HOME=str(scratch / "home/state"), XDG_CACHE_HOME=str(scratch / "home/cache"),
               XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM="wayland", QT_QPA_PLATFORMTHEME="generic",
               QT_QUICK_BACKEND="software", QML_IMPORT_PATH=str(scratch), QS_DISABLE_CRASH_HANDLER="1",
               WLR_BACKENDS="headless", WLR_RENDERER="pixman", WLR_HEADLESS_OUTPUTS="1",
               LD_LIBRARY_PATH=str(sway_binary.parent.parent / "lib"))
    isolated = ["bwrap", "--unshare-all", "--die-with-parent", "--ro-bind", "/", "/",
                "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/run", "--tmpfs", "/tmp",
                "--ro-bind", str(sway_binary.parent.parent), str(sway_binary.parent.parent),
                "--bind", raw, raw, "--chdir", raw, "--"]
    with (scratch / "compositor.log").open("w") as log:
        compositor = subprocess.Popen(isolated + [str(sway_binary), "--unsupported-gpu", "-c", str(config)],
                                      env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                sockets = [path for path in runtime.glob("wayland-*") if path.is_socket()]
                if sockets:
                    env["WAYLAND_DISPLAY"] = sockets[0].name
                    break
                if compositor.poll() is not None:
                    raise SystemExit((scratch / "compositor.log").read_text()[-2000:])
                time.sleep(0.05)
            else:
                raise SystemExit("Private compositor socket deadline")
            try:
                result = subprocess.run(isolated + ["quickshell", "--path", str(probe), "--no-color"],
                                        env=env, capture_output=True, text=True, timeout=10)
            except subprocess.TimeoutExpired as error:
                output = (error.stdout or b"") + (error.stderr or b"")
                raise SystemExit("Reader fixture deadline:\n" + output.decode(errors="replace")[-2000:])
            output = result.stdout + result.stderr
            matches = re.findall(r"READER_LAYOUT_RESULT (\[.*\])", output)
            if not matches:
                raise SystemExit(output[-2000:])
            report = json.loads(matches[-1])
            print(json.dumps(report))
            passed = len(report) == 3 and all(len(row["checks"]) == 8 and all(row["checks"]) for row in report)
            raise SystemExit(0 if result.returncode == 0 and passed else 1)
        finally:
            if compositor.poll() is None:
                os.killpg(compositor.pid, signal.SIGTERM)
                try:
                    compositor.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(compositor.pid, signal.SIGKILL)
                    compositor.wait(timeout=3)
