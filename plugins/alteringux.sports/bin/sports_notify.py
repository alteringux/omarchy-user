#!/usr/bin/env python3
"""Notify Pulse once when a cached sports event enters an in-play status."""
import argparse
import fcntl
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
STATE_PATH = os.path.join(HOME, ".local", "state", "omarchy", "sports.json")
LIVE_STATUSES = {
    "ht", "1h", "2h", "1st half", "2nd half", "et", "p", "in play", "live"
}
MARKER_RETENTION_SECONDS = 7 * 24 * 60 * 60


def load_json(path, fallback):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            value = json.load(fh)
    except (OSError, ValueError):
        return fallback
    return value


def event_key(event):
    event_id = str(event.get("id") or "").strip()
    if event_id:
        return "id:" + event_id
    return "match:" + "|".join(
        str(event.get(field) or "").strip().casefold()
        for field in ("sport", "homeTeam", "awayTeam", "eventName")
    )


def event_label(event):
    name = str(event.get("eventName") or "").strip()
    if name:
        return name
    home = str(event.get("homeTeam") or "TBA").strip()
    away = str(event.get("awayTeam") or "TBA").strip()
    return f"{home} vs {away}"


def is_live(event):
    status = str(event.get("status") or "").strip().casefold()
    return status in LIVE_STATUSES


def atomic_write(path, value):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as fh:
        json.dump(value, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(temporary, path)


def notify_started(state_path, marker_path=None, pulse_command="omarchy-pulse", now=None):
    now = int(time.time()) if now is None else int(now)
    if marker_path is None:
        marker_path = os.path.join(os.path.dirname(os.path.abspath(state_path)), "sports-notifications.json")
    lock_path = marker_path + ".lock"
    os.makedirs(os.path.dirname(os.path.abspath(marker_path)), exist_ok=True)
    with open(lock_path, "w", encoding="utf-8") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        state = load_json(state_path, {})
        markers = load_json(marker_path, {})
        if not isinstance(markers, dict):
            markers = {}
        markers = {
            key: value for key, value in markers.items()
            if isinstance(value, dict) and now - int(value.get("sentAt", 0)) <= MARKER_RETENTION_SECONDS
        }
        sent = []
        for event in state.get("live") or []:
            if not isinstance(event, dict) or not is_live(event):
                continue
            key = event_key(event)
            if key in markers:
                continue
            label = event_label(event)
            command = [
                pulse_command, "log", "alteringux.sports", f"Started: {label}",
                "--level", "info", "--notify",
                "--action", "omarchy-shell alteringux.sports open",
                "--action-label", "Open Sports",
            ]
            try:
                result = subprocess.run(command, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError:
                continue
            if result.returncode == 0:
                markers[key] = {"sentAt": now, "label": label}
                sent.append(label)
        atomic_write(marker_path, markers)
    return sent


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", default=STATE_PATH)
    parser.add_argument("--marker")
    parser.add_argument("--pulse-command", default="omarchy-pulse")
    args = parser.parse_args(argv)
    labels = notify_started(args.state, args.marker, args.pulse_command)
    for label in labels:
        print(f"notified: {label}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
