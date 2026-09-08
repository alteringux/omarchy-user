#!/usr/bin/env python3
"""Fetch configured news feeds and write a flat headline list for the News Bar.

Reads   ~/.config/omarchy/newsbar-feeds.json   (created with defaults if absent)
Writes  ~/.local/state/omarchy/newsbar.json    (atomic replace)

The QML side never touches the network: this script fetches + parses RSS/Atom
and bundles a common headline shape; Model.js does presentation only. A break
in a feed's XML shape is therefore a one-file fix here.

Feeds config shape:
    {
      "version": 1,
      "perFeed": 8,          # max headlines kept from each feed
      "maxHeadlines": 40,    # global cap after interleaving
      "refreshMinutes": 15, # read by the QML side, not here
      "feeds": [ { "name": "BBC", "url": "https://...", "category": "World" }, ... ]
    }
    Per-feed "category" is an optional fallback sector; a sector derived from
    an item's own URL path or <category> still takes precedence.

State file shape:
    {
      "version": 1,
      "updatedAt": "2026-01-01T00:00:00Z",
      "error": null | "human readable summary",
      "headlines": [
        { "source", "title", "url", "published" (ISO or ""),
          "category" (or ""), "summary" (or "") },
        ...
      ]
    }
"""

import html
import json
import os
import re
import sys
import tempfile
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from xml.etree import ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import seen_history  # noqa: E402 - sibling module in bin/

HOME = os.path.expanduser("~")
CONFIG_PATH = os.path.join(HOME, ".config", "omarchy", "newsbar-feeds.json")
STATE_DIR = os.path.join(HOME, ".local", "state", "omarchy")
STATE_PATH = os.path.join(STATE_DIR, "newsbar.json")
SEEN_PATH = os.path.join(STATE_DIR, "newsbar-seen.json")

UA = "Mozilla/5.0 (X11; Linux x86_64) omarchy-newsbar-refresh"
TIMEOUT = 8
FRESHNESS_FLOOR = 20  # min headlines a refresh shows before backfilling seen ones

DEFAULT_CONFIG = {
    "version": 1,
    "perFeed": 8,
    "maxHeadlines": 40,
    # Refresh shows headlines not on the previous crawl and retires the rest;
    # if fewer than this remain, the freshest retired ones backfill.
    "freshnessFloor": FRESHNESS_FLOOR,
    # "category" is an optional fallback sector for a feed whose items don't
    # carry one in their URL or <category>; a per-item sector still wins.
    "feeds": [
        {"name": "BBC", "url": "https://feeds.bbci.co.uk/news/world/rss.xml", "category": "World"},
        {"name": "NPR", "url": "https://feeds.npr.org/1001/rss.xml"},
        {"name": "Guardian", "url": "https://www.theguardian.com/world/rss", "category": "World"},
        {"name": "Al Jazeera", "url": "https://www.aljazeera.com/xml/rss/all.xml", "category": "World"},
        {"name": "AP", "url": "https://feedx.net/rss/ap.xml", "category": "World"},
    ],
}

ATOM = "{http://www.w3.org/2005/Atom}"


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_config():
    """Return (config, created?). Writes DEFAULT_CONFIG if the file is missing
    or unreadable so a first run is self-provisioning."""
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as fh:
            raw = json.load(fh)
        feeds = [
            {"name": str(f.get("name", "")).strip() or "News",
             "url": str(f.get("url", "")).strip(),
             "category": str(f.get("category", "")).strip()}
            for f in raw.get("feeds", [])
            if str(f.get("url", "")).strip()
        ]
        if not feeds:
            raise ValueError("no usable feeds in config")
        return {
            "perFeed": int(raw.get("perFeed", DEFAULT_CONFIG["perFeed"]) or 8),
            "maxHeadlines": int(raw.get("maxHeadlines", DEFAULT_CONFIG["maxHeadlines"]) or 40),
            "freshnessFloor": int(raw.get("freshnessFloor", FRESHNESS_FLOOR) or FRESHNESS_FLOOR),
            "feeds": feeds,
        }, False
    except FileNotFoundError:
        write_default_config()
        return _config_from(DEFAULT_CONFIG), True
    except Exception as exc:  # noqa: BLE001 - any parse/shape error -> fall back
        sys.stderr.write(f"newsbar: config unreadable ({exc}); using defaults\n")
        return _config_from(DEFAULT_CONFIG), False


def _config_from(raw):
    return {
        "perFeed": raw["perFeed"],
        "maxHeadlines": raw["maxHeadlines"],
        "freshnessFloor": raw.get("freshnessFloor", FRESHNESS_FLOOR),
        "feeds": [dict(f) for f in raw["feeds"]],
    }


def write_default_config():
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    _atomic_write(CONFIG_PATH, json.dumps(DEFAULT_CONFIG, indent=2) + "\n")


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return resp.read()


def clean_text(value):
    if not value:
        return ""
    text = html.unescape(str(value))
    text = re.sub(r"<[^>]+>", "", text)          # strip stray inline markup
    text = re.sub(r"\s+", " ", text).strip()
    return text


CE = "{http://purl.org/rss/1.0/modules/content/}encoded"

# Boilerplate some feeds pad the description with.
_SUMMARY_JUNK = re.compile(
    r"(read more|continue reading|the post .* appeared first|\[\.\.\.\]|&#8230;)\s*$",
    re.IGNORECASE,
)


def clean_summary(value, limit=280):
    """RSS <description> / Atom <summary> often carries a usable standfirst,
    sometimes wrapped in HTML or padded with 'Read more'. Strip to plain text,
    drop the boilerplate tail, and cap to one sentence-ish snippet."""
    text = clean_text(value)
    if not text:
        return ""
    text = _SUMMARY_JUNK.sub("", text).strip()
    if len(text) > limit:
        cut = text[:limit]
        dot = max(cut.rfind(". "), cut.rfind("! "), cut.rfind("? "))
        text = (cut[: dot + 1] if dot > 80 else cut.rstrip()) + " …"
    return text


def to_iso(value):
    if not value:
        return ""
    value = value.strip()
    # RFC 822 (RSS pubDate)
    try:
        dt = parsedate_to_datetime(value)
        if dt is not None:
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except (TypeError, ValueError):
        pass
    # ISO 8601 (Atom updated/published)
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return ""


# Path slugs that name a section, mapped to the label shown on the bar.
SECTION_SLUGS = {
    "world": "World", "uk": "UK", "us": "US", "us-news": "US", "uk-news": "UK",
    "africa": "Africa", "asia": "Asia", "europe": "Europe", "americas": "Americas",
    "australia": "Australia", "middleeast": "Middle East", "middle-east": "Middle East",
    "business": "Business", "economy": "Business", "economics": "Business",
    "money": "Business", "markets": "Business",
    "politics": "Politics", "election": "Politics", "elections": "Politics",
    "technology": "Tech", "tech": "Tech",
    "science": "Science", "environment": "Climate", "climate": "Climate",
    "health": "Health", "coronavirus": "Health",
    "sport": "Sport", "sports": "Sport", "football": "Sport", "soccer": "Sport",
    "culture": "Culture", "arts": "Culture", "books": "Culture", "film": "Culture",
    "music": "Culture", "entertainment": "Culture", "tv-and-radio": "Culture",
    "lifestyle": "Life", "life": "Life", "food": "Life", "travel": "Travel",
    "opinion": "Opinion", "commentisfree": "Opinion", "editorial": "Opinion",
    "education": "Education", "media": "Media",
}

_TRAIL_NEWS = re.compile(r"\s+news$", re.IGNORECASE)
_KNOWN_LABELS = set(SECTION_SLUGS.values())


def category_of(explicit, url):
    """Pick a short sector label. The article URL path is the reliable signal
    (theguardian.com/world/..., aljazeera.com/sports/...); a feed's first
    <category> is usually a topic keyword, so it's only trusted when it maps
    onto a known section."""
    try:
        path = urllib.parse.urlparse(url).path.lower()
    except Exception:  # noqa: BLE001
        path = ""
    for seg in path.split("/"):
        if seg.strip() in SECTION_SLUGS:
            return SECTION_SLUGS[seg.strip()]

    cat = _TRAIL_NEWS.sub("", clean_text(explicit)).strip()
    if 1 <= len(cat) <= 20 and "," not in cat:
        key = cat.lower().replace(" ", "").replace("-", "")
        if key in SECTION_SLUGS:
            return SECTION_SLUGS[key]
        if cat.title() in _KNOWN_LABELS:
            return cat.title()
    return ""


def parse_feed(source, blob, per_feed, feed_category=""):
    """Parse one feed's bytes into a list of headline dicts (RSS or Atom).
    feed_category is the feed-level fallback sector."""
    root = ET.fromstring(blob)
    out = []

    # RSS 2.0 / RDF: <item><title><link><pubDate>
    items = root.findall(".//item")
    for item in items:
        title = clean_text(item.findtext("title"))
        link = (item.findtext("link") or "").strip()
        if not link:
            guid = item.findtext("guid") or ""
            if guid.strip().startswith("http"):
                link = guid.strip()
        pub = item.findtext("pubDate") or item.findtext(
            "{http://purl.org/dc/elements/1.1/}date"
        )
        if title and link:
            out.append({
                "source": source,
                "title": title,
                "url": link,
                "published": to_iso(pub),
                "category": category_of(item.findtext("category"), link) or feed_category,
                "summary": clean_summary(
                    item.findtext("description") or item.findtext(CE)
                ),
            })
        if len(out) >= per_feed:
            return out

    if out:
        return out

    # Atom: <entry><title><link rel="alternate" href><updated>
    for entry in root.findall(f".//{ATOM}entry"):
        title = clean_text(entry.findtext(f"{ATOM}title"))
        link = ""
        for lnk in entry.findall(f"{ATOM}link"):
            rel = lnk.get("rel", "alternate")
            if rel == "alternate" and lnk.get("href"):
                link = lnk.get("href").strip()
                break
        if not link:
            first = entry.find(f"{ATOM}link")
            if first is not None and first.get("href"):
                link = first.get("href").strip()
        pub = entry.findtext(f"{ATOM}published") or entry.findtext(f"{ATOM}updated")
        atom_cat = entry.find(f"{ATOM}category")
        explicit_cat = atom_cat.get("term") if atom_cat is not None else ""
        if title and link:
            out.append({
                "source": source,
                "title": title,
                "url": link,
                "published": to_iso(pub),
                "category": category_of(explicit_cat, link) or feed_category,
                "summary": clean_summary(
                    entry.findtext(f"{ATOM}summary")
                    or entry.findtext(f"{ATOM}content")
                ),
            })
        if len(out) >= per_feed:
            break
    return out


def interleave(groups, cap):
    """Round-robin across feeds so no single source floods the front of the
    crawl, then apply the global cap. Dedupe on lowercased title."""
    seen = set()
    result = []
    idx = 0
    while len(result) < cap and any(idx < len(g) for g in groups):
        for g in groups:
            if idx < len(g):
                h = g[idx]
                key = h["title"].lower()
                if key not in seen:
                    seen.add(key)
                    result.append(h)
                    if len(result) >= cap:
                        break
        idx += 1
    return result


def _atomic_write(path, text):
    d = os.path.dirname(path)
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


def write_state(headlines, error):
    os.makedirs(STATE_DIR, exist_ok=True)
    payload = {
        "version": 1,
        "updatedAt": now_iso(),
        "error": error,
        "headlines": headlines,
    }
    _atomic_write(STATE_PATH, json.dumps(payload, ensure_ascii=False) + "\n")


def read_existing_headlines():
    try:
        with open(STATE_PATH, "r", encoding="utf-8") as fh:
            return json.load(fh).get("headlines", []) or []
    except Exception:  # noqa: BLE001
        return []


def main():
    config, _ = load_config()
    groups = []
    failures = []
    for feed in config["feeds"]:
        try:
            blob = fetch(feed["url"])
            parsed = parse_feed(feed["name"], blob, config["perFeed"], feed.get("category", ""))
            if parsed:
                groups.append(parsed)
            else:
                failures.append(f"{feed['name']} (no items)")
        except Exception as exc:  # noqa: BLE001 - keep going on a single bad feed
            failures.append(f"{feed['name']} ({exc.__class__.__name__})")

    headlines = interleave(groups, config["maxHeadlines"])

    if not headlines:
        # Total failure: keep whatever was on screen, just record the error.
        prev = read_existing_headlines()
        write_state(prev, "; ".join(failures) or "no headlines fetched")
        sys.stderr.write("newsbar: no headlines fetched: " + "; ".join(failures) + "\n")
        return 1

    # Freshness rule: show headlines that weren't on the previous crawl and
    # retire the ones that were; backfill the freshest retired headlines only if
    # under `freshnessFloor` remain. Record what we actually show so the next
    # refresh treats it as stale.
    seen = seen_history.load(SEEN_PATH)
    headlines, shown = seen_history.select_fresh(
        headlines, seen, config.get("freshnessFloor", FRESHNESS_FLOOR))

    error = ("partial: " + "; ".join(failures)) if failures else None
    write_state(headlines, error)
    seen_history.record(SEEN_PATH, shown)
    return 0


if __name__ == "__main__":
    sys.exit(main())
