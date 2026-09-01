#!/usr/bin/env python3
"""Quote + affirmation store, weighted picker, and feedback scorer for the motivator app."""
import fcntl
import json
import random
import sys
from pathlib import Path

BASE = Path.home() / ".config" / "omarchy" / "motivator"
QUOTES_FILE = BASE / "quotes.txt"
AFFIRMATIONS_FILE = BASE / "affirmations.txt"
SCORES_FILE = BASE / "scores.json"


def _load_lines(path):
    if not path.exists():
        return []
    return [l.strip() for l in path.read_text().splitlines() if l.strip()]


def load_quotes():
    return _load_lines(QUOTES_FILE)


def load_affirmations():
    return _load_lines(AFFIRMATIONS_FILE)


def load_pool():
    """Quotes and affirmations together — what `pick` and `daily-list` draw from."""
    return load_quotes() + load_affirmations()


def load_scores():
    if not SCORES_FILE.exists():
        return {}
    try:
        return json.loads(SCORES_FILE.read_text() or "{}")
    except json.JSONDecodeError:
        return {}


def weights_for(items, scores):
    # Baseline 5, shifted by score, floor of 1 so nothing is ever impossible.
    return [max(1, 5 + scores.get(i, 0)) for i in items]


def with_lock(fn):
    lock_path = BASE / ".lock"
    lock_path.touch(exist_ok=True)
    with open(lock_path, "w") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        try:
            return fn()
        finally:
            fcntl.flock(lf, fcntl.LOCK_UN)


def cmd_pick():
    pool = load_pool()
    if not pool:
        return
    scores = load_scores()
    print(random.choices(pool, weights=weights_for(pool, scores), k=1)[0])


def cmd_daily_list(n):
    """Print up to n distinct picks from the whole pool — the once-a-day digest."""
    pool = load_pool()
    if not pool:
        return
    scores = load_scores()
    remaining = list(pool)
    picks = []
    while remaining and len(picks) < n:
        choice = random.choices(remaining, weights=weights_for(remaining, scores), k=1)[0]
        picks.append(choice)
        remaining = [x for x in remaining if x != choice]
    for p in picks:
        print(p)


def cmd_feedback(quote, delta):
    def update():
        scores = load_scores()
        scores[quote] = scores.get(quote, 0) + delta
        SCORES_FILE.write_text(json.dumps(scores, indent=2))
    with_lock(update)


def cmd_top(n, path):
    items = _load_lines(path)
    scores = load_scores()
    ranked = sorted(items, key=lambda q: scores.get(q, 0), reverse=True)
    liked = [q for q in ranked if scores.get(q, 0) > 0][:n]
    for q in liked:
        print(q)


def cmd_add(path):
    new_lines = [l.strip() for l in sys.stdin.read().splitlines() if l.strip()]
    if not new_lines:
        return

    def update():
        existing_set = set(_load_lines(path))
        added = 0
        with open(path, "a") as f:
            for line in new_lines:
                # Guard against the model echoing numbering/quotes/markdown.
                clean = line.lstrip("0123456789.-) \"'").rstrip("\"'")
                if clean and clean not in existing_set and len(clean) < 200:
                    f.write(clean + "\n")
                    existing_set.add(clean)
                    added += 1
        print(added)
    with_lock(update)


def cmd_prune(threshold, path):
    def update():
        items = _load_lines(path)
        scores = load_scores()
        kept = [q for q in items if scores.get(q, 0) > threshold]
        removed = len(items) - len(kept)
        if removed:
            path.write_text("\n".join(kept) + "\n")
        print(removed)
    with_lock(update)


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        sys.exit(1)
    cmd = args[0]
    if cmd == "pick":
        cmd_pick()
    elif cmd == "daily-list":
        cmd_daily_list(int(args[1]) if len(args) > 1 else 5)
    elif cmd == "feedback":
        cmd_feedback(args[1], int(args[2]))
    elif cmd == "top":
        cmd_top(int(args[1]) if len(args) > 1 else 8, QUOTES_FILE)
    elif cmd == "top-affirmations":
        cmd_top(int(args[1]) if len(args) > 1 else 8, AFFIRMATIONS_FILE)
    elif cmd == "add-quotes":
        cmd_add(QUOTES_FILE)
    elif cmd == "add-affirmations":
        cmd_add(AFFIRMATIONS_FILE)
    elif cmd == "prune":
        cmd_prune(int(args[1]) if len(args) > 1 else -3, QUOTES_FILE)
    elif cmd == "prune-affirmations":
        cmd_prune(int(args[1]) if len(args) > 1 else -3, AFFIRMATIONS_FILE)
    else:
        sys.exit(f"unknown command: {cmd}")
