#!/usr/bin/env python3
"""Fetch one TheSportsDB event and its available statistics as JSON."""
import argparse
import json
import sys

import sports_fetch as fetch


def compact_stats(doc):
    rows = fetch.events_of(doc, "eventstats", "eventStats")
    stats = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        name = row.get("strStat") or row.get("strStatistic") or row.get("name")
        if not name:
            continue
        stats.append({
            "name": str(name),
            "home": row.get("intHome") if row.get("intHome") not in (None, "") else row.get("strHome"),
            "away": row.get("intAway") if row.get("intAway") not in (None, "") else row.get("strAway"),
        })
    return stats


def fetch_event(event_id, config_path=fetch.CONFIG_PATH):
    config = fetch.load_config(config_path)
    key = str(config.get("apiKey") or "3")
    base = str(config.get("apiBase") or "https://www.thesportsdb.com")
    event_doc = fetch.fetch_json(base, key, "lookupevent.php", {"id": event_id})
    events = fetch.events_of(event_doc, "events", "event")
    if not events:
        return {"version": 1, "event": None, "stats": [], "error": "Event not found"}

    raw = events[0]
    sport = raw.get("strSport") or "Sports"
    league = raw.get("strLeague") or ""
    event = fetch.compact_event(raw, sport, league)
    if event is None:
        return {"version": 1, "event": None, "stats": [], "error": "Event data was invalid"}

    stats_doc = fetch.fetch_json(base, key, "lookupeventstats.php", {"id": event_id})
    return {"version": 1, "event": event, "stats": compact_stats(stats_doc), "error": None}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--id", required=True, help="TheSportsDB event id")
    parser.add_argument("--config", default=fetch.CONFIG_PATH)
    args = parser.parse_args(argv)
    try:
        result = fetch_event(args.id, args.config)
        print(json.dumps(result, ensure_ascii=False))
        return 0 if result.get("error") is None else 1
    except Exception as exc:
        print(json.dumps({"version": 1, "event": None, "stats": [], "error": str(exc)}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
