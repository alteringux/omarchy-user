#!/usr/bin/env python3
"""Discover and stage extra RSS sources for the News Bar.

Run by a systemd user timer every couple of days (subcommand `suggest`), or by
hand via `omarchy-newsbar-sources <cmd>`.

Default behaviour is PROPOSE-AND-APPROVE: validated new feeds are written to a
staging file and a desktop notification is sent; nothing touches
newsbar-feeds.json until you run `approve`. Flip to unattended adding with
`omarchy-newsbar-sources auto on`.

Subcommands:
  suggest            fetch + validate a couple of pool feeds not already in
                     use, stage them (or add them directly if auto is on)
  list               show what's currently staged
  approve [all|NAME] move staged feed(s) into newsbar-feeds.json + reload
  reject  [all|NAME] drop staged feed(s) (remembered, won't be re-suggested)
  auto   on|off|status
  status             counts + auto state
"""

import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
import newsbar_fetch as nf  # noqa: E402  (sibling module: fetch + parse_feed)

HOME = os.path.expanduser("~")
CONFIG_PATH = os.path.join(HOME, ".config", "omarchy", "newsbar-feeds.json")
STATE_DIR = os.path.join(HOME, ".local", "state", "omarchy")
STAGING_PATH = os.path.join(STATE_DIR, "newsbar-suggested-feeds.json")
AUTO_FLAG = os.path.join(STATE_DIR, "toggles", "newsbar-sources-auto")

BATCH = 2            # feeds considered per run
MIN_HEADLINES = 3    # a feed must yield at least this many to count as live

# Curated pool of reputable, general-interest, keyless news feeds. The timer
# walks this list a couple at a time; anything already in the config, already
# staged, or previously rejected is skipped. Add your own candidates here.
POOL = [
    {"name": "Reuters", "url": "https://www.reutersagency.com/feed/?best-topics=top-news&post_type=best", "category": "World"},
    {"name": "DW", "url": "https://rss.dw.com/rdf/rss-en-all", "category": "World"},
    {"name": "France 24", "url": "https://www.france24.com/en/rss", "category": "World"},
    {"name": "CBC", "url": "https://www.cbc.ca/webfeed/rss/rss-world", "category": "World"},
    {"name": "ABC AU", "url": "https://www.abc.net.au/news/feed/2942460/rss.xml", "category": "World"},
    {"name": "Sky News", "url": "https://feeds.skynews.com/feeds/rss/world.xml", "category": "World"},
    {"name": "CBS News", "url": "https://www.cbsnews.com/latest/rss/world", "category": "World"},
    {"name": "NBC News", "url": "https://feeds.nbcnews.com/nbcnews/public/world", "category": "World"},
    {"name": "UN News", "url": "https://news.un.org/feed/subscribe/en/news/all/rss.xml", "category": "World"},
    {"name": "Euronews", "url": "https://www.euronews.com/rss", "category": "World"},
    {"name": "CS Monitor", "url": "https://rss.csmonitor.com/feeds/all", "category": "World"},
    {"name": "Independent", "url": "https://www.independent.co.uk/news/world/rss", "category": "World"},
    {"name": "Guardian US", "url": "https://www.theguardian.com/us-news/rss", "category": "US"},
    {"name": "NPR World", "url": "https://feeds.npr.org/1004/rss.xml", "category": "World"},
    {"name": "BBC Business", "url": "https://feeds.bbci.co.uk/news/business/rss.xml", "category": "Business"},
    {"name": "BBC Tech", "url": "https://feeds.bbci.co.uk/news/technology/rss.xml", "category": "Tech"},
    {"name": "Guardian Science", "url": "https://www.theguardian.com/science/rss", "category": "Science"},
]


# --------------------------------------------------------------------- io utils
def _read_json(path, fallback):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:  # noqa: BLE001
        return fallback


def _atomic_write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=os.path.basename(path) + ".")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


def _norm(url):
    return (url or "").strip().rstrip("/").lower()


def load_config():
    cfg = _read_json(CONFIG_PATH, None)
    if not isinstance(cfg, dict) or not isinstance(cfg.get("feeds"), list):
        return None
    return cfg


def load_staging():
    s = _read_json(STAGING_PATH, {})
    return {
        "version": 1,
        "suggested": s.get("suggested", []) if isinstance(s, dict) else [],
        "rejected": s.get("rejected", []) if isinstance(s, dict) else [],
    }


def save_staging(s):
    _atomic_write(STAGING_PATH, s)


def notify(summary, body):
    for cmd in (
        ["omarchy-notification-send", summary, body],
        ["notify-send", summary, body],
    ):
        try:
            subprocess.run(cmd, check=False, timeout=5,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        except Exception:  # noqa: BLE001
            continue


def reload_shell():
    try:
        subprocess.run(["omarchy-shell", "alteringux.newsbar", "reloadConfig"],
                       check=False, timeout=5,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:  # noqa: BLE001
        pass


def auto_on():
    return os.path.exists(AUTO_FLAG)


# ---------------------------------------------------------------- feed checking
def validate(feed):
    """Return the feed dict with a fresh headline count, or None if it doesn't
    look like a live RSS/Atom feed right now."""
    try:
        blob = nf.fetch(feed["url"])
        items = nf.parse_feed(feed["name"], blob, 10, feed.get("category", ""))
        if len(items) >= MIN_HEADLINES:
            return feed
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"newsbar-sources: {feed['name']} failed validation ({exc.__class__.__name__})\n")
    return None


def add_to_config(feeds):
    cfg = load_config()
    if cfg is None:
        sys.stderr.write("newsbar-sources: newsbar-feeds.json unreadable; not adding\n")
        return 0
    have = {_norm(f.get("url")) for f in cfg["feeds"]}
    added = 0
    for f in feeds:
        if _norm(f["url"]) in have:
            continue
        entry = {"name": f["name"], "url": f["url"]}
        if f.get("category"):
            entry["category"] = f["category"]
        cfg["feeds"].append(entry)
        have.add(_norm(f["url"]))
        added += 1
    if added:
        _atomic_write(CONFIG_PATH, cfg)
        reload_shell()
    return added


# ------------------------------------------------------------------- subcommands
def cmd_suggest(_args):
    cfg = load_config()
    if cfg is None:
        sys.stderr.write("newsbar-sources: newsbar-feeds.json unreadable; nothing to do\n")
        return 1
    staging = load_staging()

    blocked = {_norm(f.get("url")) for f in cfg["feeds"]}
    blocked |= {_norm(f.get("url")) for f in staging["suggested"]}
    blocked |= {_norm(u) for u in staging["rejected"]}

    candidates = [f for f in POOL if _norm(f["url"]) not in blocked]
    if not candidates:
        print("newsbar-sources: pool exhausted; nothing new to suggest")
        return 0

    picked = []
    for feed in candidates[:BATCH * 3]:   # over-scan: some pool entries may be dead
        live = validate(feed)
        if live:
            picked.append({**live, "addedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
        if len(picked) >= BATCH:
            break

    if not picked:
        print("newsbar-sources: no live candidates this run")
        return 0

    if auto_on():
        n = add_to_config(picked)
        notify("News Bar", f"Auto-added {n} new source(s): " + ", ".join(p["name"] for p in picked))
        print(f"newsbar-sources: auto-added {n}: " + ", ".join(p["name"] for p in picked))
        return 0

    staging["suggested"].extend(picked)
    save_staging(staging)
    names = ", ".join(p["name"] for p in picked)
    notify("News Bar — new sources suggested",
           f"{names}\nRun  omarchy-newsbar-sources approve all  to add them.")
    print(f"newsbar-sources: staged {len(picked)}: {names}")
    print("approve with:  omarchy-newsbar-sources approve all")
    return 0


def cmd_list(_args):
    staging = load_staging()
    if not staging["suggested"]:
        print("(nothing staged)")
        return 0
    for f in staging["suggested"]:
        cat = f" [{f['category']}]" if f.get("category") else ""
        print(f"  {f['name']}{cat}\n    {f['url']}\n    staged {f.get('addedAt', '?')}")
    print("\napprove:  omarchy-newsbar-sources approve all")
    return 0


def _match(feeds, args):
    if not args or args == ["all"]:
        return list(feeds), []
    wanted = {a.lower() for a in args}
    keep = [f for f in feeds if f["name"].lower() in wanted]
    rest = [f for f in feeds if f["name"].lower() not in wanted]
    return keep, rest


def cmd_approve(args):
    staging = load_staging()
    take, rest = _match(staging["suggested"], args)
    if not take:
        print("newsbar-sources: no staged feed matched")
        return 1
    n = add_to_config(take)
    staging["suggested"] = rest
    save_staging(staging)
    print(f"newsbar-sources: added {n} feed(s): " + ", ".join(f["name"] for f in take))
    return 0


def cmd_reject(args):
    staging = load_staging()
    drop, rest = _match(staging["suggested"], args)
    if not drop:
        print("newsbar-sources: no staged feed matched")
        return 1
    staging["suggested"] = rest
    staging["rejected"].extend(_norm(f["url"]) for f in drop)
    save_staging(staging)
    print("newsbar-sources: rejected " + ", ".join(f["name"] for f in drop))
    return 0


def cmd_auto(args):
    val = (args[0].lower() if args else "status")
    if val == "on":
        os.makedirs(os.path.dirname(AUTO_FLAG), exist_ok=True)
        open(AUTO_FLAG, "w").close()
        print("newsbar-sources: auto-add ON — the timer will add validated feeds directly")
    elif val == "off":
        try:
            os.unlink(AUTO_FLAG)
        except FileNotFoundError:
            pass
        print("newsbar-sources: auto-add OFF — the timer will stage feeds for approval")
    else:
        print("auto-add: " + ("ON" if auto_on() else "OFF"))
    return 0


def cmd_status(_args):
    cfg = load_config() or {"feeds": []}
    staging = load_staging()
    print(f"active feeds:   {len(cfg['feeds'])}")
    print(f"staged:         {len(staging['suggested'])}")
    print(f"rejected:       {len(staging['rejected'])}")
    print(f"pool size:      {len(POOL)}")
    print(f"auto-add:       {'ON' if auto_on() else 'OFF'}")
    return 0


COMMANDS = {
    "suggest": cmd_suggest,
    "list": cmd_list,
    "approve": cmd_approve,
    "reject": cmd_reject,
    "auto": cmd_auto,
    "status": cmd_status,
}


def main(argv):
    cmd = argv[0] if argv else "suggest"
    fn = COMMANDS.get(cmd)
    if not fn:
        sys.stderr.write(__doc__)
        return 2
    return fn(argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
