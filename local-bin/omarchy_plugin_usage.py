#!/usr/bin/env python3
"""Pure filesystem-backed scanner for Kit.Usage plugin activity.

The command wrapper is ``omarchy-plugin-usage``.  This module intentionally
uses only the Python standard library so Pulse and tests can invoke the same
normalisation logic without a shell or jq pipeline.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

DAY_MS = 86_400_000
DEFAULT_THRESHOLD_DAYS = 30
DEFAULT_USER_PLUGIN_DIR = Path.home() / ".config" / "omarchy" / "plugins"
DEFAULT_OMARCHY_PATH = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))
DEFAULT_PACKAGED_PLUGIN_DIR = DEFAULT_OMARCHY_PATH / "shell" / "plugins"
DEFAULT_USAGE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "omarchy" / "usage"
DEFAULT_SHELL_CONFIG = Path.home() / ".config" / "omarchy" / "shell.json"


def _number(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def _positive_number(value: Any) -> float | None:
    number = _number(value)
    return number if number is not None and number > 0 else None


def _valid_id(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    plugin_id = value.strip()
    if not plugin_id or plugin_id.startswith("/") or ".." in plugin_id or "/" in plugin_id:
        return ""
    return plugin_id


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError, TypeError):
        return None

def _manifest(path: Path, source: str) -> dict[str, Any] | None:
    value = _read_json(path)
    if not isinstance(value, dict):
        return None
    plugin_id = _valid_id(value.get("id"))
    if not plugin_id:
        return None
    label = value.get("name")
    if not isinstance(label, str) or not label.strip():
        label = plugin_id
    return {"id": plugin_id, "label": label.strip(), "source": source, "manifest": path}


def _manifest_paths(root: Path, packaged: bool) -> Iterable[Path]:
    if not root.is_dir():
        return ()
    if not packaged:
        # Third-party plugins are one directory deep, matching PluginRegistry.
        try:
            return tuple(sorted((p / "manifest.json" for p in root.iterdir() if p.is_dir()), key=str))
        except OSError:
            return ()
    try:
        return tuple(sorted(
            (p for p in root.rglob("*") if p.is_file() and (p.name == "manifest.json" or p.name.endswith(".manifest.json"))),
            key=str,
        ))
    except OSError:
        return ()


def discover_plugins(user_dir: Path, packaged_dir: Path) -> list[dict[str, Any]]:
    """Return valid manifests, preferring packaged ids on collisions."""
    plugins: dict[str, dict[str, Any]] = {}
    for path in _manifest_paths(packaged_dir, True):
        item = _manifest(path, "packaged")
        if item:
            plugins[item["id"]] = item
    for path in _manifest_paths(user_dir, False):
        item = _manifest(path, "user")
        if item and item["id"] not in plugins:
            plugins[item["id"]] = item
    return list(plugins.values())


def _plugin_ids(value: Any, result: set[str]) -> None:
    if isinstance(value, dict):
        plugin_id = _valid_id(value.get("id"))
        if plugin_id:
            result.add(plugin_id)
        for child in value.values():
            _plugin_ids(child, result)
    elif isinstance(value, list):
        for child in value:
            _plugin_ids(child, result)


def enabled_plugin_ids(config_path: Path) -> tuple[set[str], set[str]]:
    """Read shell.json refs and disabledPlugins; malformed config means none."""
    config = _read_json(config_path)
    if not isinstance(config, dict):
        return set(), set()
    refs: set[str] = set()
    _plugin_ids(config.get("bar", {}).get("layout", {}) if isinstance(config.get("bar"), dict) else {}, refs)
    _plugin_ids(config.get("plugins", []), refs)
    disabled: set[str] = set()
    raw_disabled = config.get("disabledPlugins")
    if isinstance(raw_disabled, list):
        disabled = {plugin_id for plugin_id in (_valid_id(v) for v in raw_disabled) if plugin_id}
    return refs, disabled


def _usage_doc(path: Path) -> tuple[bool, int, int, int]:
    """Return (tracked, uses, lastAt, firstAt) from one tolerant Kit doc."""
    tracked = path.is_file()
    if not tracked:
        return False, 0, 0, 0
    value = _read_json(path)
    if not isinstance(value, dict):
        return True, 0, 0, 0
    first = _positive_number(value.get("firstAt")) or 0
    actions = value.get("actions")
    if not isinstance(actions, dict):
        return True, 0, 0, int(first)
    uses = 0
    last_at = 0.0
    for action in actions.values():
        if not isinstance(action, dict):
            continue
        count = _positive_number(action.get("count"))
        count_int = int(math.floor(count)) if count else 0
        if count_int:
            uses += count_int
            last = _positive_number(action.get("lastAt"))
            if last and last > last_at:
                last_at = last
    if uses > 0 and not last_at:
        last_at = first
    return True, uses, int(last_at), int(first)


def scan(
    *,
    threshold_days: int = DEFAULT_THRESHOLD_DAYS,
    now_ms: int | None = None,
    user_dir: Path | None = None,
    packaged_dir: Path | None = None,
    usage_dir: Path | None = None,
    shell_config: Path | None = None,
) -> dict[str, Any]:
    """Build the stable scanner contract without writing any state."""
    user_dir = user_dir or Path(os.environ.get("OMARCHY_PLUGIN_USER_DIR", DEFAULT_USER_PLUGIN_DIR))
    packaged_dir = packaged_dir or Path(os.environ.get("OMARCHY_PLUGIN_PACKAGED_DIR", DEFAULT_PACKAGED_PLUGIN_DIR))
    usage_dir = usage_dir or Path(os.environ.get("OMARCHY_PLUGIN_USAGE_DIR", DEFAULT_USAGE_DIR))
    shell_config = shell_config or Path(os.environ.get("OMARCHY_PLUGIN_SHELL_CONFIG", DEFAULT_SHELL_CONFIG))
    if now_ms is None:
        override = _number(os.environ.get("OMARCHY_PLUGIN_USAGE_NOW_MS"))
        now_ms = int(override) if override is not None else int(time.time() * 1000)
    threshold_days = max(0, int(threshold_days))
    refs, disabled = enabled_plugin_ids(shell_config)

    rows: list[dict[str, Any]] = []
    for item in discover_plugins(user_dir, packaged_dir):
        plugin_id = item["id"]
        if item["source"] == "packaged":
            enabled = plugin_id not in disabled
        else:
            enabled = plugin_id in refs and plugin_id not in disabled
        tracked, uses, last_at, _first_at = _usage_doc(usage_dir / f"{plugin_id}.json")
        never_used = tracked and uses == 0
        days_idle = None
        if last_at > 0 and not never_used:
            days_idle = max(0, int((now_ms - last_at) // DAY_MS))
        rows.append({
            "id": plugin_id,
            "label": item["label"],
            "source": item["source"],
            "enabled": enabled,
            "tracked": tracked,
            "uses": uses,
            "lastAt": last_at,
            "daysIdle": days_idle,
            "neverUsed": never_used,
        })

    # Most-used first makes the one batch useful to both dashboards and Pulse;
    # id is the deterministic tie-breaker (including never-used rows).
    rows.sort(key=lambda row: (-row["uses"], row["id"]))
    stale = sum(
        1
        for row in rows
        if row["tracked"]
        and (
            row["neverUsed"]
            or (
                threshold_days > 0
                and row["daysIdle"] is not None
                and row["daysIdle"] >= threshold_days
            )
        )
    )
    return {
        "version": 1,
        "generatedAt": datetime.fromtimestamp(now_ms / 1000, timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "thresholdDays": threshold_days,
        "plugins": rows,
        "summary": {
            "tracked": sum(1 for row in rows if row["tracked"]),
            "untracked": sum(1 for row in rows if not row["tracked"]),
            "neverUsed": sum(1 for row in rows if row["tracked"] and row["neverUsed"]),
            "stale": stale,
        },
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="omarchy-plugin-usage", description="summarize Kit.Usage activity for installed plugins")
    parser.add_argument("--days", type=int, default=DEFAULT_THRESHOLD_DAYS, metavar="N", help="stale threshold in days (default: 30)")
    parser.add_argument("--json", action="store_true", dest="as_json", help="emit the machine-readable contract")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    if args.days < 0:
        parser.error("--days must be non-negative")
    report = scan(threshold_days=args.days)
    if args.as_json:
        print(json.dumps(report, ensure_ascii=False, sort_keys=False, separators=(",", ":")))
    else:
        for row in report["plugins"]:
            usage = "never used" if row["neverUsed"] else f"{row['uses']} uses, {row['daysIdle']}d idle"
            state = "tracked" if row["tracked"] else "untracked"
            enabled = "enabled" if row["enabled"] else "disabled"
            print(f"{row['id']}\t{usage}\t{state}\t{enabled}")
        summary = report["summary"]
        print(f"{summary['tracked']} tracked, {summary['untracked']} untracked, {summary['neverUsed']} never used, {summary['stale']} stale")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
