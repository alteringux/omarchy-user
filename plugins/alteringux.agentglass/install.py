#!/usr/bin/env python3
"""Install the native agentglass widget into a user's Omarchy config."""
import argparse
import json
import os
import shutil
import time
from pathlib import Path


SOURCE = Path(__file__).resolve().parent
HOME = Path.home()
OMARCHY = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "omarchy"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--omarchy-dir", type=Path, default=OMARCHY,
        help="Omarchy config directory (defaults to XDG_CONFIG_HOME/omarchy)",
    )
    parser.add_argument(
        "--bin-dir", type=Path, default=HOME / ".local/bin",
        help="user CLI install directory (defaults to ~/.local/bin)",
    )
    args = parser.parse_args(argv)
    omarchy = args.omarchy_dir
    kit = omarchy / "plugins" / "alteringux.kit"
    if not kit.is_dir():
        raise SystemExit(f"missing Omarchy kit: {kit}")
    shell = omarchy / "shell.json"
    if not shell.is_file():
        raise SystemExit(f"missing Omarchy shell config: {shell}")
    cli = SOURCE / "bin/agentglass-agent"
    if not cli.is_file():
        raise SystemExit("run this installer from the agentglass checkout")
    global_cli = args.bin_dir / "agentglass-agent"
    same_cli = False
    if global_cli.is_file():
        try:
            same_cli = global_cli.read_bytes() == cli.read_bytes()
        except OSError:
            pass
    if global_cli.exists() and global_cli.is_dir() and not global_cli.is_symlink():
        raise SystemExit(f"refusing to replace a directory: {global_cli}")

    config = json.loads(shell.read_text())
    stamp = str(time.time_ns())
    backup = shell.with_name(shell.name + ".bak.agentglass." + stamp)
    shutil.copy2(shell, backup)
    plugins = config.setdefault("plugins", [])
    if not any(isinstance(item, dict) and item.get("id") == "alteringux.agentglass" for item in plugins):
        plugins.append({"id": "alteringux.agentglass"})
    right = config.setdefault("bar", {}).setdefault("layout", {}).setdefault("right", [])
    if not any(isinstance(item, dict) and item.get("id") == "alteringux.agentglass" for item in right):
        insert_at = next((i + 1 for i, item in enumerate(right) if isinstance(item, dict) and item.get("id") == "omarchy.agents"), len(right))
        right.insert(insert_at, {"id": "alteringux.agentglass"})

    plugin = omarchy / "plugins" / "alteringux.agentglass"
    if plugin.exists():
        previous = omarchy / "backups" / "agentglass" / stamp / "plugin"
        previous.parent.mkdir(parents=True, exist_ok=False)
        shutil.move(plugin, previous)
        print(f"previous  {previous}")
    shutil.copytree(SOURCE, plugin, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    shutil.copy2(cli, plugin / "bin/agentglass-agent")
    args.bin_dir.mkdir(parents=True, exist_ok=True)
    if not same_cli:
        staged_cli = args.bin_dir / (".agentglass-agent." + stamp + ".tmp")
        shutil.copy2(cli, staged_cli)
        try:
            if global_cli.exists() or global_cli.is_symlink():
                previous_cli = global_cli.with_name(global_cli.name + ".bak.agentglass." + stamp)
                os.replace(global_cli, previous_cli)
                print(f"previous  {previous_cli}")
            os.replace(staged_cli, global_cli)
        finally:
            staged_cli.unlink(missing_ok=True)
    shell.write_text(json.dumps(config, indent=2) + "\n")
    print(f"installed {plugin}")
    print(f"installed {global_cli}")
    if str(args.bin_dir) not in os.environ.get("PATH", "").split(os.pathsep):
        print(f"add {args.bin_dir} to PATH to run agentglass-agent from any directory")
    print(f"backup    {backup}")
    print("Omarchy hot-reloads the plugin; if needed: omarchy restart shell")


if __name__ == "__main__":
    main()
