#!/usr/bin/env python3
"""Tests for bin/seen_history.py — the shared 'already shown it' / freshness rule.

  python3 test/seen_history_test.py
"""
import importlib.util
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "seen_history", os.path.join(HERE, "..", "bin", "seen_history.py"))
sh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sh)

_fail = 0


def check(name, cond):
    global _fail
    print(("ok   - " if cond else "FAIL - ") + name)
    if not cond:
        _fail += 1


def items(*urls):
    return [{"url": u, "title": u} for u in urls]


def urls(lst):
    return [i["url"] for i in lst]


# ---- select_fresh: nothing seen -> everything is fresh, order kept ----------
disp, shown = sh.select_fresh(items("a", "b", "c"), {}, floor=2)
check("all-unseen: shows every candidate in order", urls(disp) == ["a", "b", "c"])
check("all-unseen: shown mirrors the display set", shown == ["a", "b", "c"])

# ---- select_fresh: enough fresh -> seen ones are dropped entirely ----------
seen = {"a": time.time(), "b": time.time()}
disp, shown = sh.select_fresh(items("a", "b", "c", "d", "e"), seen, floor=2)
check("enough fresh: stale items retired", urls(disp) == ["c", "d", "e"])
check("enough fresh: shown == fresh", shown == ["c", "d", "e"])

# ---- select_fresh: too few fresh -> backfill freshest stale to the floor ---
seen = {"a": 100, "b": 200, "c": 300}   # c is the freshest stale
disp, shown = sh.select_fresh(items("a", "b", "c", "d"), seen, floor=3)
check("backfill: one fresh ('d') kept", "d" in urls(disp))
check("backfill: filled up to the floor", len(disp) == 3)
check("backfill: display keeps candidate order", urls(disp) == ["a", "b", "d"])
check("backfill: took the front of the listing as backfill (a, b)",
      set(urls(disp)) == {"a", "b", "d"})

# ---- select_fresh: floor bigger than the listing -> show all --------------
disp, shown = sh.select_fresh(items("a", "b"), {"a": 1, "b": 1}, floor=10)
check("floor > listing: shows the whole listing", set(urls(disp)) == {"a", "b"})

# ---- select_fresh: duplicate urls in candidates are collapsed -------------
disp, shown = sh.select_fresh(items("a", "a", "b"), {}, floor=1)
check("dupes: each url appears once", urls(disp) == ["a", "b"])
check("dupes: shown has no repeats", shown == ["a", "b"])

# ---- select_fresh: floor 0 -> only ever the fresh set --------------------
disp, shown = sh.select_fresh(items("a", "b"), {"a": 1}, floor=0)
check("floor 0: just the fresh items", urls(disp) == ["b"])

# ---- load: tolerant of missing / corrupt / wrong-shape ------------------
tmp = tempfile.mkdtemp(prefix="seen_test_")
missing = os.path.join(tmp, "nope.json")
check("load: missing file -> {}", sh.load(missing) == {})
bad = os.path.join(tmp, "bad.json")
open(bad, "w").write("{not json")
check("load: corrupt file -> {}", sh.load(bad) == {})
arr = os.path.join(tmp, "arr.json")
open(arr, "w").write("[1,2,3]")
check("load: wrong shape (list) -> {}", sh.load(arr) == {})

# ---- record: stamps, prunes by age, prunes by count, round-trips -------
store = os.path.join(tmp, "hist.json")
sh.record(store, ["u1", "u2", "u3"])
back = sh.load(store)
check("record: all urls written", set(back) == {"u1", "u2", "u3"})
check("record: round-trips through load()", all(isinstance(v, float) for v in back.values()))

# an entry older than the ttl window is forgotten on the next record()
old = os.path.join(tmp, "old.json")
sh._atomic_write(old, sh.json.dumps({"stale": time.time() - 10 * 86400,
                                     "keep": time.time()}))
sh.record(old, ["fresh"], ttl_days=4)
back = sh.load(old)
check("record: ttl drops entries past the window", "stale" not in back)
check("record: ttl keeps recent + newly stamped", {"keep", "fresh"} <= set(back))

# count cap keeps the newest N
cap = os.path.join(tmp, "cap.json")
sh._atomic_write(cap, sh.json.dumps({f"u{i}": 1000 + i for i in range(10)}))
sh.record(cap, ["brand-new"], ttl_days=0, count_cap=3)
back = sh.load(cap)
check("record: count cap enforced", len(back) == 3)
check("record: count cap keeps the newest", "brand-new" in back and "u9" in back and "u0" not in back)

import shutil
shutil.rmtree(tmp, ignore_errors=True)

print()
if _fail:
    print(f"{_fail} check(s) failed")
    sys.exit(1)
print("all checks passed")
