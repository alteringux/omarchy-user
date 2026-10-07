#!/usr/bin/env python3
"""Build a local, deterministic snapshot of installed agent skills."""
from __future__ import annotations
import argparse, json, os, re, time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DAY_MS = 86_400_000
DEFAULT_THRESHOLD_DAYS = 30
DEFAULT_ROOTS = (Path.home() / ".codex" / "skills", Path.home() / ".agents" / "skills")
DEFAULT_STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "omarchy" / "skill-usage"

def _roots():
    raw = os.environ.get("OMARCHY_SKILL_ROOTS")
    return tuple(Path(p).expanduser() for p in raw.split(os.pathsep) if p) if raw else DEFAULT_ROOTS

def _read_usage(path):
    if not path.is_file(): return False, 0, 0
    try: value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError): return True, 0, 0
    if not isinstance(value, dict): return True, 0, 0
    try: return True, max(0, int(value.get("uses", 0))), max(0, int(value.get("lastAt", 0)))
    except (TypeError, ValueError): return True, 0, 0

def _frontmatter(path):
    try: text = path.read_text(encoding="utf-8", errors="replace")
    except OSError: return "", ""
    block = text.split("---", 2)[1] if text.startswith("---") and "---" in text[3:] else text
    name = re.search(r"^name:\s*(.+?)\s*$", block, re.MULTILINE)
    description = re.search(r"^description:\s*[\"']?(.*?)[\"']?\s*$", block, re.MULTILINE)
    return (name.group(1).strip() if name else path.parent.name, description.group(1).strip() if description else "")

def discover(roots=None):
    rows = {}
    for root in roots or _roots():
        if not root.is_dir(): continue
        try: candidates = sorted((p for p in root.iterdir() if p.is_dir() and (p / "SKILL.md").is_file()), key=lambda p: p.name)
        except OSError: continue
        for directory in candidates:
            real = directory.resolve()
            name, description = _frontmatter(directory / "SKILL.md")
            rows.setdefault(directory.name, {"id": directory.name, "name": name, "description": description, "source": str(root), "path": str(real), "owned": str(real).startswith(str(Path.home()))})
    return [rows[key] for key in sorted(rows)]

def scan(*, now_ms=None, threshold_days=DEFAULT_THRESHOLD_DAYS, roots=None, state_dir=None, lifecycle_path=None):
    now_ms = now_ms if now_ms is not None else int(time.time() * 1000)
    state_dir = state_dir or Path(os.environ.get("OMARCHY_SKILL_USAGE_DIR", DEFAULT_STATE))
    lifecycle_path = lifecycle_path or Path(os.environ.get("OMARCHY_SKILL_LIFECYCLE", state_dir.parent / "skill-lifecycle.json"))
    try:
        lifecycle = json.loads(lifecycle_path.read_text(encoding="utf-8"))
        lifecycle = lifecycle if isinstance(lifecycle, dict) else {}
    except (OSError, ValueError, TypeError):
        lifecycle = {}
    lifecycle_skills = lifecycle.get("skills", {}) if isinstance(lifecycle.get("skills", {}), dict) else {}
    rows = []
    for row in discover(roots):
        tracked, uses, last_at = _read_usage(state_dir / f"{row['id']}.json")
        never_used = tracked and uses == 0
        days_idle = None if not last_at or never_used else max(0, (now_ms - last_at) // DAY_MS)
        stale = tracked and (never_used or (days_idle is not None and threshold_days > 0 and days_idle >= threshold_days))
        lifecycle_row = lifecycle_skills.get(row["id"], {})
        lifecycle_row = lifecycle_row if isinstance(lifecycle_row, dict) else {}
        rows.append({**row, "tracked": tracked, "uses": uses, "lastAt": last_at, "daysIdle": days_idle, "neverUsed": never_used, "stale": stale, "status": lifecycle_row.get("status", "active"), "acknowledgedAt": lifecycle_row.get("acknowledgedAt")})
    rows.sort(key=lambda row: (-row["uses"], row["id"]))
    return {"version": 1, "generatedAt": datetime.fromtimestamp(now_ms / 1000, timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"), "thresholdDays": max(0, int(threshold_days)), "skills": rows, "summary": {"total": len(rows), "tracked": sum(r["tracked"] for r in rows), "untracked": sum(not r["tracked"] for r in rows), "neverUsed": sum(r["neverUsed"] for r in rows), "stale": sum(r["stale"] for r in rows), "uses": sum(r["uses"] for r in rows)}}

def main(argv=None):
    parser = argparse.ArgumentParser(prog="omarchy-skill-usage")
    parser.add_argument("--days", type=int, default=DEFAULT_THRESHOLD_DAYS)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    if args.days < 0: parser.error("--days must be non-negative")
    report = scan(threshold_days=args.days)
    if args.json: print(json.dumps(report, ensure_ascii=False, separators=(",", ":")))
    else:
        for row in report["skills"]: print(f"{row['id']}\t{row['uses']} uses\t{'stale' if row['stale'] else 'current'}")
        print(json.dumps(report["summary"], separators=(",", ":")))
    return 0

if __name__ == "__main__": raise SystemExit(main())
