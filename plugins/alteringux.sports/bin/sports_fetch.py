#!/usr/bin/env python3
"""omarchy-sports-refresh -- fetch sports data from TheSportsDB into the
state file the alteringux.sports bar widget watches (CLI-first, ADR 0006).

For every league listed in the config it fetches:
  - eventsnextleague.php  -> upcoming fixtures
  - eventspastleague.php  -> recent results (final scores)
  - lookuptable.php       -> season standings (table) when the league has one
and, for every favourite team id:
  - eventsnext.php / eventslast.php -> per-team fixtures/results
  - lookup_all_players.php          -> rosters for the Players tab

Sports with a scheduled event day pull eventsday.php?s=<Sport> so the Live
tab shows matches from leagues not individually configured.

All fetches are tolerant: one failing endpoint degrades to an empty section,
never a failed refresh. Output is written atomically to
$OMARCHY_STATE_DIR/sports.json (default ~/.local/state/omarchy/sports.json).

Usage:
    omarchy-sports-refresh [--config PATH] [--state PATH] [--timeout SECS]
"""
import json
import html
import os
import sys
import fcntl
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
CONFIG_PATH = os.path.join(HOME, ".config", "omarchy", "sports-config.json")
STATE_DIR = os.environ.get("OMARCHY_STATE_DIR", os.path.join(HOME, ".local", "state", "omarchy"))
STATE_PATH = os.path.join(STATE_DIR, "sports.json")
TIMEOUT = 10
MAX_EVENTS_PER_LEAGUE = 20

UA = "Mozilla/5.0 (X11; Linux x86_64) omarchy-sports-refresh"

DEFAULT_CONFIG = {
    "version": 1,
    "apiKey": "3",  # TheSportsDB public test key; a Patreon key lifts limits
    "activeSports": ["Soccer", "Rugby", "Basketball"],
    "favouriteTeams": [],  # [{ "idTeam": "133604", "name": "Arsenal", "sport": "Soccer" }]
    "leagues": {
        "Soccer": [{"id": "4328", "name": "English Premier League"}],
        "Rugby": [{"id": "4414", "name": "English Prem Rugby"},
                  {"id": "4430", "name": "French Top 14"},
                  {"id": "4416", "name": "Australian National Rugby League"}],
        "Basketball": [{"id": "4387", "name": "NBA"}]
    },
    "tableSports": ["Soccer"],  # sports whose leagues publish a standings table
    "players": True,            # fetch rosters for favourite teams
    "articlesFeeds": {}         # optional sport -> RSS/Atom URLs
}

LIVE_STATUSES = {
    "ht", "1h", "2h", "1st half", "2nd half", "et", "p", "in play", "live"
}
TERMINAL_STATUSES = {
    "ft", "match finished", "aet", "pen", "finished", "after over time",
    "after penalties", "postponed", "cancelled", "canceled", "abandoned"
}


def _status(event):
    return str(event.get("status") or "").strip().casefold()


def is_live_event(event):
    status = _status(event)
    if status in LIVE_STATUSES:
        return True
    if status in TERMINAL_STATUSES or status in {"", "ns", "not started"}:
        return False
    return event.get("homeScore") is not None or event.get("awayScore") is not None


def is_finished_event(event):
    status = _status(event)
    return status in TERMINAL_STATUSES and status not in {"postponed", "cancelled", "canceled", "abandoned"}


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _atomic_write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def load_config(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            cfg = json.load(fh)
    except (OSError, ValueError):
        return dict(DEFAULT_CONFIG)
    if not isinstance(cfg, dict):
        return dict(DEFAULT_CONFIG)

    merged = dict(DEFAULT_CONFIG)
    merged.update(cfg)
    if not isinstance(merged.get("activeSports"), list):
        merged["activeSports"] = list(DEFAULT_CONFIG["activeSports"])
    else:
        merged["activeSports"] = [s for s in merged["activeSports"] if isinstance(s, str) and s.strip()]
    if not isinstance(merged.get("favouriteTeams"), list):
        merged["favouriteTeams"] = []
    else:
        merged["favouriteTeams"] = [f for f in merged["favouriteTeams"] if isinstance(f, dict)]
    if not isinstance(merged.get("tableSports"), list):
        merged["tableSports"] = list(DEFAULT_CONFIG["tableSports"])
    if not isinstance(merged.get("articlesFeeds"), dict):
        merged["articlesFeeds"] = {}
    if not isinstance(merged.get("leagues"), dict):
        merged["leagues"] = {}
    else:
        merged["leagues"] = {
            sport: [league for league in leagues if isinstance(league, dict)]
            for sport, leagues in merged["leagues"].items()
            if isinstance(sport, str) and isinstance(leagues, list)
        }
    return merged


# ----------------------------------------------------------------------- http
def fetch_json(base, key, endpoint, params):
    qs = urllib.parse.urlencode(params)
    url = f"{base}/api/v1/json/{key}/{endpoint}?{qs}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            doc = json.loads(resp.read().decode("utf-8", "replace"))
    except Exception:
        return None
    if not isinstance(doc, dict):
        return None
    return doc

def events_of(doc, *list_keys):
    if not isinstance(doc, dict):
        return []
    for k in list_keys:
        val = doc.get(k)
        if isinstance(val, list):
            return val
    return []


# -------------------------------------------------------------------- articles
def _feed_value(item, name):
    """Read an RSS child or Atom namespaced child as plain text."""
    node = item.find(name)
    if node is None:
        node = item.find("{*}" + name)
    if node is None:
        return ""
    return html.unescape("".join(node.itertext())).strip()


def compact_article(raw, sport, source):
    if not isinstance(raw, dict):
        return None
    title = str(raw.get("title") or "").strip()
    url = str(raw.get("url") or "").strip()
    if not title or not url or urllib.parse.urlparse(url).scheme not in ("http", "https"):
        return None
    image = str(raw.get("image") or "").strip()
    if urllib.parse.urlparse(image).scheme not in ("http", "https"):
        image = ""
    return {
        "title": title,
        "url": url,
        "source": str(raw.get("source") or source or "").strip(),
        "sport": str(raw.get("sport") or sport or "").strip(),
        "published": str(raw.get("published") or "").strip(),
        "summary": str(raw.get("summary") or "").strip(),
        "image": image,
    }


def fetch_feed(url, sport):
    """Fetch one RSS/Atom feed; malformed or unavailable feeds are empty."""
    parsed = urllib.parse.urlparse(str(url))
    if parsed.scheme not in ("http", "https"):
        return []
    try:
        req = urllib.request.Request(str(url), headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            doc = ET.fromstring(resp.read())
    except Exception:
        return []

    source = parsed.hostname or "feed"
    items = list(doc.findall(".//item")) or list(doc.findall(".//{*}entry"))
    articles = []
    for item in items[:12]:
        link = _feed_value(item, "link")
        if not link:
            link_node = item.find("{*}link")
            link = str(link_node.attrib.get("href", "") if link_node is not None else "")
        image = ""
        for node in item.iter():
            local_name = str(node.tag).rsplit("}", 1)[-1]
            if local_name in ("content", "thumbnail", "enclosure") and node.attrib.get("url"):
                image = node.attrib["url"]
                break
        article = compact_article({
            "title": _feed_value(item, "title"),
            "url": link,
            "source": source,
            "sport": sport,
            "published": _feed_value(item, "pubDate") or _feed_value(item, "published") or _feed_value(item, "updated"),
            "summary": _feed_value(item, "description") or _feed_value(item, "summary"),
            "image": image,
        }, sport, source)
        if article:
            articles.append(article)
    return articles


def fetch_articles(feeds, active_sports):
    """Fetch configured RSS/Atom feeds in stable config order, capped globally."""
    articles = []
    for sport, urls in (feeds or {}).items():
        if sport not in active_sports:
            continue
        if isinstance(urls, str):
            urls = [urls]
        for url in urls if isinstance(urls, list) else []:
            articles.extend(fetch_feed(url, sport))
    seen = set()
    unique = []
    for article in articles:
        if article["url"] in seen:
            continue
        seen.add(article["url"])
        unique.append(article)
    return unique[:40]


# --------------------------------------------------------------- match shapes
def _safe_http_url(value):
    if not isinstance(value, str):
        return None
    value = value.strip()
    return value if value.startswith(("https://", "http://")) else None


def youtube_search_url(event_name, sport, suffix):
    query = " ".join(part for part in (event_name, sport, suffix) if part)
    return "https://www.youtube.com/results?search_query=" + urllib.parse.quote_plus(query)


EVENT_STATS = {
    "attendance": "intSpectators",
    "official": "strOfficial",
    "weather": "strWeather",
    "homeScoreExtra": "intHomeScoreExtra",
    "awayScoreExtra": "intAwayScoreExtra"
}


def compact_event(raw, sport, league_name):
    """Project an event row onto the fields the QML side reads."""
    if not isinstance(raw, dict):
        return None
    if not str(raw.get("idEvent") or "").strip():
        return None

    def _score(v):
        try:
            return int(v)
        except (TypeError, ValueError):
            return None

    def _team(v):
        return v if isinstance(v, str) and v.strip() else None

    event_name = _team(raw.get("strEvent"))
    stats = {
        name: raw.get(source)
        for name, source in EVENT_STATS.items()
        if raw.get(source) not in (None, "")
    }

    return {
        "id": raw.get("idEvent"),
        "sport": sport,
        "eventName": event_name,
        "league": _team(raw.get("strLeague")) or league_name,
        "homeTeam": _team(raw.get("strHomeTeam")),
        "awayTeam": _team(raw.get("strAwayTeam")),
        "idHomeTeam": raw.get("idHomeTeam"),
        "idAwayTeam": raw.get("idAwayTeam"),
        "homeScore": _score(raw.get("intHomeScore")),
        "awayScore": _score(raw.get("intAwayScore")),
        "dateEvent": raw.get("dateEvent"),
        "strTimestamp": raw.get("strTimestamp"),
        "strTime": raw.get("strTime"),
        "venue": _team(raw.get("strVenue")),
        "status": _team(raw.get("strStatus")),
        "official": _team(raw.get("strOfficial")),
        "weather": _team(raw.get("strWeather")),
        "attendance": raw.get("intSpectators"),
        "elapsed": raw.get("strProgress") or raw.get("intElapsed") or raw.get("strProgressMatch"),
        "round": raw.get("intRound"),
        "season": raw.get("strSeason"),
        "videoUrl": _safe_http_url(raw.get("strVideo")),
        "youtubeHighlightsUrl": youtube_search_url(event_name or "", sport, "highlights"),
        "officialCoverageUrl": youtube_search_url(event_name or "", sport, "official live coverage"),
        "stats": stats
    }


def compact_player(raw):
    if not isinstance(raw, dict):
        return None
    name = raw.get("strPlayer")
    if not name:
        return None
    return {
        "id": raw.get("idPlayer"),
        "name": name,
        "team": raw.get("strTeam"),
        "position": raw.get("strPosition"),
        "number": raw.get("strNumber"),
        "height": raw.get("strHeight"),
        "weight": raw.get("strWeight"),
        "born": raw.get("dateBorn"),
        "nationality": raw.get("strNationality"),
        "thumb": raw.get("strThumb") or raw.get("strCutout"),
        "description": raw.get("strDescriptionEN"),
        "stats": {
            "appearances": raw.get("intAppearances"),
            "goals": raw.get("intGoals"),
            "assists": raw.get("intAssists"),
            "points": raw.get("intPoints"),
            "minutes": raw.get("intMinutes"),
            "yellowCards": raw.get("intYellowCards"),
            "redCards": raw.get("intRedCards")
        }
    }


def compact_table_row(raw):
    if not isinstance(raw, dict):
        return None
    return {
        "rank": raw.get("intRank"),
        "idTeam": raw.get("idTeam"),
        "team": raw.get("strTeam"),
        "played": raw.get("intPlayed"),
        "win": raw.get("intWin"),
        "loss": raw.get("intLoss"),
        "draw": raw.get("intDraw"),
        "goalsFor": raw.get("intGoalsFor"),
        "goalsAgainst": raw.get("intGoalsAgainst"),
        "goalDifference": raw.get("intGoalDifference"),
        "points": raw.get("intPoints"),
        "form": raw.get("strForm")
    }


def compact_team(raw):
    if not isinstance(raw, dict):
        return None
    return {
        "id": raw.get("idTeam"),
        "name": raw.get("strTeam"),
        "stadium": raw.get("strStadium"),
        "badge": raw.get("strBadge"),
        "league": raw.get("strLeague"),
        "sport": raw.get("strSport")
    }


# ----------------------------------------------------------------- season key
def season_key_for_year(now=None):
    """TheSportsDB tables are keyed by seasons like 2024-2025; northern-hemisphere
    seasons start in autumn, so before July we are still in the previous season."""
    now = now or datetime.now(timezone.utc)
    y = now.year
    if now.month < 7:
        return f"{y - 1}-{y}"
    return f"{y}-{y + 1}"


# -------------------------------------------------------------------- refresh
def refresh(cfg, base, timeout_unused=None):
    key = str(cfg.get("apiKey") or "3")
    leagues_cfg = cfg.get("leagues") or {}
    active = set(cfg.get("activeSports") or leagues_cfg.keys())
    favourites = cfg.get("favouriteTeams") or []
    season = season_key_for_year()
    match_fetches = {"ok": 0, "failed": 0}

    def fetch_match(endpoint, params):
        value = fetch_json(base, key, endpoint, params)
        match_fetches["ok" if value is not None else "failed"] += 1
        return value

    upcoming, results = {}, {}   # id -> event (dedup across leagues)
    standings = {}               # sport -> [rows]
    players_by_team = {}         # teamName -> [players]
    teams_cache = {}

    for sport, leagues in leagues_cfg.items():
        if sport not in active:
            continue
        for league in leagues:
            lid = str(league.get("id", ""))
            lname = league.get("name", sport)
            if not lid:
                continue

            nxt = fetch_match("eventsnextleague.php", {"id": lid})
            for raw in events_of(nxt, "events")[:MAX_EVENTS_PER_LEAGUE]:
                ev = compact_event(raw, sport, lname)
                if ev:
                    upcoming[ev["id"]] = ev

            past = fetch_match("eventspastleague.php", {"id": lid})
            for raw in events_of(past, "events")[:MAX_EVENTS_PER_LEAGUE]:
                ev = compact_event(raw, sport, lname)
                if ev:
                    results[ev["id"]] = ev

            if sport in (cfg.get("tableSports") or []):
                table = fetch_json(base, key, "lookuptable.php", {"l": lid, "s": season})
                rows = [r for r in (compact_table_row(x) for x in events_of(table, "table")) if r]
                if rows:
                    standings[sport] = rows

    # Favourite teams: per-team fixtures/results, rosters, and team lookup.
    for fav in favourites:
        tid = str(fav.get("idTeam", ""))
        if not tid:
            continue
        nxt = fetch_match("eventsnext.php", {"id": tid})
        for raw in events_of(nxt, "events")[:MAX_EVENTS_PER_LEAGUE]:
            ev = compact_event(raw, fav.get("sport", ""), fav.get("name", ""))
            if ev:
                upcoming[ev["id"]] = ev
        last = fetch_match("eventslast.php", {"id": tid})
        for raw in events_of(last, "results")[:MAX_EVENTS_PER_LEAGUE]:
            ev = compact_event(raw, fav.get("sport", ""), fav.get("name", ""))
            if ev:
                results[ev["id"]] = ev
        if cfg.get("players", True):
            roster = fetch_json(base, key, "lookup_all_players.php", {"id": tid})
            roster = [p for p in (compact_player(x) for x in events_of(roster, "player")) if p]
            if roster:
                players_by_team[fav.get("name") or tid] = roster
        team = fetch_json(base, key, "lookupteam.php", {"id": tid})
        rows = events_of(team, "teams")
        if rows and isinstance(rows[0], dict):
            c = compact_team(rows[0])
            if c and c["name"]:
                teams_cache[c["name"]] = c

    # Day sweep: catch live/in-play matches on scheduled-event sports even for
    # leagues not individually configured. Only today's date; cheap one call
    # per sport.
    live_matches = []
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    for sport in active:
        day = fetch_match("eventsday.php", {"d": today, "s": sport})
        for raw in events_of(day, "events"):
            ev = compact_event(raw, sport, raw.get("strLeague") if isinstance(raw, dict) else sport)
            if not ev:
                continue
            if is_live_event(ev):
                live_matches.append(ev)
                # Keep in-play fixtures in the upcoming feed too; this is
                # the established contract used by the Upcoming tab.
                upcoming.setdefault(ev["id"], ev)
            elif is_finished_event(ev):
                results.setdefault(ev["id"], ev)
            else:
                # Not started, postponed, cancelled, or an otherwise
                # incomplete provider row remains visible without claiming
                # that play is in progress.
                upcoming.setdefault(ev["id"], ev)

    articles = fetch_articles(cfg.get("articlesFeeds"), active)

    state = {
        "version": 1,
        "updatedAt": now_iso(),
        "live": live_matches,
        "upcoming": sorted(upcoming.values(), key=lambda e: e.get("strTimestamp") or e.get("dateEvent") or "9999"),
        "results": sorted(results.values(), key=lambda e: e.get("dateEvent") or "", reverse=True),
        "articles": articles,
        "players": players_by_team,
        "standings": standings,
        "teams": teams_cache,
        "favouriteTeams": favourites,
        "season": season,
        "predictions": {},
        "refreshHealth": {"matchRequestsOk": match_fetches["ok"], "matchRequestsFailed": match_fetches["failed"]}
    }
    return state


def acquire_refresh_lock(state_path):
    lock_path = os.path.join(os.path.dirname(os.path.abspath(state_path)), ".sports-refresh.lock")
    os.makedirs(os.path.dirname(lock_path), exist_ok=True)
    handle = open(lock_path, "w", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        return None
    return handle


def preserve_cached_matches(state, state_path):
    health = state.get("refreshHealth") or {}
    if health.get("matchRequestsOk", 0) != 0:
        return
    try:
        with open(state_path, "r", encoding="utf-8") as fh:
            previous = json.load(fh)
    except (OSError, ValueError):
        return
    if not isinstance(previous, dict):
        return
    fields = ("live", "upcoming", "results", "players", "standings", "teams")
    if not any(previous.get(field) for field in fields):
        return
    for field in fields:
        if field in previous:
            state[field] = previous[field]
    state["matchDataUpdatedAt"] = previous.get("matchDataUpdatedAt") or previous.get("updatedAt")
    health["usedCachedMatches"] = True


def preserve_cached_articles(state, state_path, cfg):
    if state.get("articles"):
        return
    feeds = cfg.get("articlesFeeds") or {}
    active = set(cfg.get("activeSports") or (cfg.get("leagues") or {}).keys())
    configured = any(
        sport in active and isinstance(urls, list) and urls
        for sport, urls in feeds.items()
    )
    if not configured:
        return
    try:
        with open(state_path, "r", encoding="utf-8") as fh:
            previous = json.load(fh)
    except (OSError, ValueError):
        return
    if not isinstance(previous, dict) or not previous.get("articles"):
        return
    state["articles"] = previous["articles"]
    state["articleDataUpdatedAt"] = previous.get("articleDataUpdatedAt") or previous.get("updatedAt")
    health = state.get("refreshHealth") or {}
    health["usedCachedArticles"] = True

def preserve_cached_predictions(state, state_path):
    try:
        with open(state_path, "r", encoding="utf-8") as fh:
            previous = json.load(fh)
    except (OSError, ValueError):
        return
    predictions = previous.get("predictions") if isinstance(previous, dict) else None
    if isinstance(predictions, dict):
        state["predictions"] = predictions



def main(argv):
    args = list(argv)
    config_path = CONFIG_PATH
    state_path = STATE_PATH
    if "--config" in args:
        config_path = args[args.index("--config") + 1]
    if "--state" in args:
        state_path = args[args.index("--state") + 1]

    lock = acquire_refresh_lock(state_path)
    if lock is None:
        return 0
    try:
        cfg = load_config(config_path)
        base = "https://www.thesportsdb.com"
        try:
            state = refresh(cfg, base)
        except Exception as exc:  # noqa: BLE001 - never leave a broken refresh silent
            print(f"omarchy-sports-refresh: {exc}", file=sys.stderr)
            return 1
        preserve_cached_matches(state, state_path)
        preserve_cached_articles(state, state_path, cfg)
        preserve_cached_predictions(state, state_path)
        try:
            import sports_predict
            state["predictions"].update(sports_predict.auto_predictions(state))
        except Exception as exc:  # noqa: BLE001 - refresh data remains usable
            print(f"omarchy-sports-refresh: automatic predictions unavailable: {exc}", file=sys.stderr)
        _atomic_write(state_path, json.dumps(state, indent=2, ensure_ascii=False) + "\n")
        return 0
    finally:
        lock.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
