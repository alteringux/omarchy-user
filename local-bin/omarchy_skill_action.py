#!/usr/bin/env python3
"""Apply explicit, local lifecycle actions to user-owned skills."""
from __future__ import annotations
import argparse, json, os, shutil, time
from pathlib import Path

STATE = Path(os.environ.get("OMARCHY_SKILL_LIFECYCLE", Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "omarchy" / "skill-lifecycle.json"))

def _state():
    try:
        value = json.loads(STATE.read_text())
        return value if isinstance(value, dict) else {"version": 1, "skills": {}, "history": []}
    except (OSError, ValueError, TypeError):
        return {"version": 1, "skills": {}, "history": []}

def _write(value):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_name("." + STATE.name + ".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    os.replace(tmp, STATE)

def apply(action, skill_id, path=None, now=None):
    state = _state()
    now = now or int(time.time() * 1000)
    if action in {"remove", "disable", "enable", "restore"} and path and not str(Path(path).resolve()).startswith(str(Path.home())):
        raise ValueError("packaged/system-owned skill is protected")
    entry = state["skills"].setdefault(skill_id, {})
    if action == "remove":
        if not path: raise ValueError("remove requires a skill path")
        source = Path(path).resolve()
        if not source.is_dir(): raise ValueError("skill path does not exist")
        backup = source.parent / ".omarchy-skill-trash" / f"{skill_id}-{now}"
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source), str(backup))
        entry.update({"status": "removed", "backup": str(backup)})
    elif action == "restore":
        backup = Path(entry.get("backup", ""))
        if not backup.is_dir(): raise ValueError("no recoverable backup")
        target = Path(path).resolve() if path else backup.parent.parent / skill_id
        if target.exists(): raise ValueError("restore target already exists")
        shutil.move(str(backup), str(target))
        entry.update({"status": "active", "path": str(target)})
    elif action in {"disable", "enable", "deprecate", "acknowledge"}:
        entry["status"] = {"disable": "disabled", "enable": "active", "deprecate": "deprecated", "acknowledge": entry.get("status", "active")}[action]
        if action == "acknowledge": entry["acknowledgedAt"] = now
    else: raise ValueError("unsupported action")
    state["history"].append({"action": action, "id": skill_id, "at": now})
    _write(state)
    return entry

def main(argv=None):
    parser = argparse.ArgumentParser(prog="omarchy-skill-action")
    parser.add_argument("action", choices=["acknowledge", "disable", "enable", "deprecate", "remove", "restore"])
    parser.add_argument("id")
    parser.add_argument("--path")
    args = parser.parse_args(argv)
    try: print(json.dumps(apply(args.action, args.id, args.path), ensure_ascii=False))
    except (OSError, ValueError) as error:
        parser.error(str(error))
    return 0

if __name__ == "__main__": raise SystemExit(main())
