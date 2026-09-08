#!/usr/bin/env python3
"""Shared "already shown it" history + freshness rule for the News Bar.

Both fetchers (newsbar_fetch.py for the RSS half, stories_fetch.py for the
ero-story half) call this so a refresh surfaces *new* entries and retires the
ones that were already on the crawl, instead of re-showing the same set every
cycle.

The rule (`select_fresh`):
  * an item whose URL was shown on a previous refresh is "stale";
  * a refresh shows the stale-free set;
  * if that set is thinner than `floor`, it is topped up ("backfilled") with
    the freshest stale items so the bar is never left empty/threadbare;
  * every URL actually shown is then recorded (`record`) so the *next* refresh
    treats it as stale.

History is a plain `{ "<url>": <epoch first/last shown> }` JSON map, pruned by
age (`ttl_days`) and then by count (`count_cap`, newest kept). stdlib only;
tolerant of a missing or half-written file (treated as empty).
"""

import json
import os
import tempfile
import time

# ---- defaults (callers override from their config) -------------------------
DEFAULT_FLOOR = 8          # min items a refresh will show before backfilling
DEFAULT_TTL_DAYS = 4       # a URL not shown again within this window is forgotten
DEFAULT_COUNT_CAP = 2000   # hard ceiling on history size (newest kept)


def _url(item):
    return (item.get("url") or "").strip() if isinstance(item, dict) else str(item).strip()


def load(path):
    """URL -> epoch map. Missing / corrupt / wrong-shape file -> {}."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = json.load(fh)
    except Exception:  # noqa: BLE001 - any read/parse error degrades to empty
        return {}
    if not isinstance(raw, dict):
        return {}
    out = {}
    for k, v in raw.items():
        try:
            out[str(k)] = float(v)
        except (TypeError, ValueError):
            continue
    return out


def select_fresh(candidates, seen, floor=DEFAULT_FLOOR):
    """Partition `candidates` (already in display order, freshest first) against
    the `seen` map. Returns (display, shown_urls).

    * >= `floor` unseen items -> show exactly those.
    * fewer -> show every unseen item plus the freshest seen ones needed to
      reach `floor`, keeping original candidate order.
    """
    floor = max(0, int(floor))
    fresh_urls = []
    fresh_set = set()
    for c in candidates:
        u = _url(c)
        if u and u not in seen and u not in fresh_set:
            fresh_set.add(u)
            fresh_urls.append(u)

    if len(fresh_set) >= floor:
        keep = fresh_set
    else:
        keep = set(fresh_set)
        need = floor - len(fresh_set)
        for c in candidates:
            if need <= 0:
                break
            u = _url(c)
            if u and u not in keep:
                keep.add(u)
                need -= 1

    display, emitted = [], set()
    for c in candidates:
        u = _url(c)
        if u in keep and u not in emitted:
            emitted.add(u)
            display.append(c)
    return display, [_url(c) for c in display]


def record(path, urls, ttl_days=DEFAULT_TTL_DAYS, count_cap=DEFAULT_COUNT_CAP):
    """Stamp every URL in `urls` as shown-now, then prune by age and count."""
    hist = load(path)
    now = time.time()
    for u in urls:
        u = (u or "").strip()
        if u:
            hist[u] = now

    if ttl_days and ttl_days > 0:
        cutoff = now - ttl_days * 86400
        hist = {u: t for u, t in hist.items() if t >= cutoff}

    if count_cap and len(hist) > count_cap:
        for u, _ in sorted(hist.items(), key=lambda kv: kv[1])[: len(hist) - count_cap]:
            hist.pop(u, None)

    _atomic_write(path, json.dumps(hist, ensure_ascii=False) + "\n")
    return hist


def _atomic_write(path, text):
    d = os.path.dirname(path) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=os.path.basename(path) + ".")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
