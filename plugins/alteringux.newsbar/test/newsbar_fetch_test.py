#!/usr/bin/env python3
"""Regression checks for the RSS age and new-article refresh rules."""

import importlib.util
import json
import os
import shutil
import tempfile
import time
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "newsbar_fetch", os.path.join(HERE, "..", "bin", "newsbar_fetch.py"))
nf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nf)

_fail = 0


def check(name, cond):
    global _fail
    if cond:
        print(f"ok - {name}")
    else:
        print(f"not ok - {name}")
        _fail += 1


fixed = datetime(2026, 9, 14, 12, 0, tzinfo=timezone.utc)
exact_boundary = (fixed - timedelta(hours=24)).isoformat().replace("+00:00", "Z")
just_old = (fixed - timedelta(hours=24, seconds=1)).isoformat().replace("+00:00", "Z")
check("age boundary: exactly 24 hours remains visible",
      nf.is_recent(exact_boundary, now=fixed))
check("age boundary: older than 24 hours is hidden",
      not nf.is_recent(just_old, now=fixed))
check("age filter: missing timestamps are hidden", not nf.is_recent("", now=fixed))

now = datetime.now(timezone.utc).replace(microsecond=0)
recent = (now - timedelta(hours=1)).strftime("%a, %d %b %Y %H:%M:%S GMT")
old = (now - timedelta(hours=25)).strftime("%a, %d %b %Y %H:%M:%S GMT")
rss = f"""<?xml version=\"1.0\"?>
<rss version=\"2.0\"><channel>
  <item><title>Recent</title><link>https://example.test/recent</link><pubDate>{recent}</pubDate></item>
  <item><title>Old</title><link>https://example.test/old</link><pubDate>{old}</pubDate></item>
  <item><title>No date</title><link>https://example.test/unknown</link></item>
</channel></rss>""".encode()
parsed = nf.parse_feed("Test", rss, 10)
check("RSS parser: only recent timestamped articles remain",
      [item["title"] for item in parsed] == ["Recent"])

seen = {"https://example.test/recent": time.time()}
display, shown = nf.seen_history.select_fresh(
    [{"url": "https://example.test/recent", "title": "Recent"}], seen, floor=1)
check("refresh rule: recent fallback keeps marquee populated",
      [item["title"] for item in display] == ["Recent"] and
      shown == ["https://example.test/recent"])

# A fetched response can be syntactically broken even when the HTTP request
# succeeds. That must be treated as a failed feed, not as an empty successful
# refresh that erases the last usable state.
tmp = tempfile.mkdtemp(prefix="newsbar_fetch_test_")
saved_paths = (nf.CONFIG_PATH, nf.STATE_DIR, nf.STATE_PATH, nf.SEEN_PATH, nf.fetch)
try:
    nf.CONFIG_PATH = os.path.join(tmp, "newsbar-feeds.json")
    nf.STATE_DIR = tmp
    nf.STATE_PATH = os.path.join(tmp, "newsbar.json")
    nf.SEEN_PATH = os.path.join(tmp, "newsbar-seen.json")
    with open(nf.CONFIG_PATH, "w", encoding="utf-8") as fh:
        json.dump({
            "perFeed": 8,
            "maxHeadlines": 40,
            "feeds": [{"name": "Broken", "url": "https://broken.test/rss"}],
        }, fh)
    cached = [{"source": "BBC", "title": "Cached", "url": "https://example.test/cached"}]
    with open(nf.STATE_PATH, "w", encoding="utf-8") as fh:
        json.dump({"version": 1, "updatedAt": "2026-09-14T12:00:00Z",
                   "error": None, "headlines": cached}, fh)
    nf.fetch = lambda _url: b"<rss><channel><item><title>truncated"
    check("malformed feed: cached headlines survive parse failure", nf.main() == 1)
    with open(nf.STATE_PATH, encoding="utf-8") as fh:
        state = json.load(fh)
    check("malformed feed: state schema and cached content are retained",
          state["headlines"] == cached and "Broken (ParseError)" in state["error"])
finally:
    nf.CONFIG_PATH, nf.STATE_DIR, nf.STATE_PATH, nf.SEEN_PATH, nf.fetch = saved_paths
    shutil.rmtree(tmp, ignore_errors=True)

if _fail:
    raise SystemExit(f"{_fail} check(s) failed")
print("all checks passed")

