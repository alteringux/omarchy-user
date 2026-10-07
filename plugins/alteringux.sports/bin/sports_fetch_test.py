"""Tests for sports_fetch.py — run with:
    python3 bin/sports_fetch_test.py

Fully offline: fetch_json is monkeypatched with canned TheSportsDB-shaped
responses so no network is touched and the shapes pinned here are the ones
confirmed live on 2026-09-13.
"""
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sports_fetch  # noqa: E402


def key(endpoint, params):
    """Hashable lookup key: endpoint + urlencoded params (dicts aren't hashable)."""
    import urllib.parse
    return (endpoint, urllib.parse.urlencode(params or {}))
"""Tests for sports_fetch.py — run with:
    python3 bin/sports_fetch_test.py

Fully offline: fetch_json is monkeypatched with canned TheSportsDB-shaped
responses so no network is touched and the shapes pinned here are the ones
confirmed live on 2026-09-13.
"""
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sports_fetch  # noqa: E402


def league_next(eid, pairs):
    """pairs of (home, away, timestamp)"""
    return {"events": [
        {"idEvent": f"{eid}n{i}", "strEvent": f"{h} vs {a}", "strHomeTeam": h, "strAwayTeam": a,
         "idHomeTeam": "1", "idAwayTeam": "2", "intHomeScore": None, "intAwayScore": None,
         "dateEvent": ts[:10], "strTimestamp": ts, "strVenue": "Venue X", "strStatus": "NS",
         "strLeague": "L", "strSport": "S"}
        for i, (h, a, ts) in enumerate(pairs)
    ]}


def league_past(eid, pairs, use_results=False):
    """eventspastleague.php rides on an "events" list key; eventslast.php on
    "results" (confirmed live). use_results=True picks the per-team flavour."""
    doc = {"events": [
        {"idEvent": f"{eid}p{i}", "strEvent": f"{h} vs {a}", "strHomeTeam": h, "strAwayTeam": a,
         "idHomeTeam": "1", "idAwayTeam": "2", "intHomeScore": str(hs), "intAwayScore": str(a_s),
         "dateEvent": ts[:10], "strTimestamp": ts, "strStatus": "Match Finished", "strLeague": "L"}
        for i, ((h, a), (hs, a_s), ts) in enumerate(pairs)
    ]}
    if use_results:
        return {"results": doc["events"]}
    return doc



TABLE = {"table": [
    {"intRank": "1", "idTeam": "133602", "strTeam": "Liverpool", "intPlayed": "38", "intWin": "25",
     "intLoss": "4", "intDraw": "9", "intGoalsFor": "86", "intGoalsAgainst": "41",
     "intGoalDifference": "45", "intPoints": "84", "strForm": "DLDLW"}
]}

ROSTER = {"player": [
    {"idPlayer": "34163698", "strPlayer": "Ben White", "strPosition": "Right-Back", "strNumber": "4",
     "strTeam": "Arsenal", "strHeight": "186 cm", "strWeight": "78 kg", "dateBorn": "1997-11-08",
     "strNationality": "England", "strThumb": None, "strDescriptionEN": None}
]}

DAY = {"events": [
    {"idEvent": "d1", "strEvent": "A vs B", "strHomeTeam": "A", "strAwayTeam": "B",
     "intHomeScore": "2", "intAwayScore": "1", "strTimestamp": "2026-09-13T15:00:00",
     "strStatus": "FT", "strLeague": "Day League", "dateEvent": "2026-09-13"},
    {"idEvent": "d2", "strEvent": "C vs D", "strHomeTeam": "C", "strAwayTeam": "D",
     "intHomeScore": "1", "intAwayScore": "1", "strTimestamp": "2026-09-13T17:00:00",
     "strStatus": "2H", "strLeague": "Day League", "dateEvent": "2026-09-13"},
    {"idEvent": "d3", "strEvent": "E vs F", "strHomeTeam": "E", "strAwayTeam": "F",
     "intHomeScore": None, "intAwayScore": None, "strTimestamp": "2026-09-13T18:00:00",
     "strStatus": "Postponed", "strLeague": "Day League", "dateEvent": "2026-09-13"},
    {"idEvent": "d4", "strEvent": "G vs H", "strHomeTeam": "G", "strAwayTeam": "H",
     "intHomeScore": None, "intAwayScore": None, "strTimestamp": "2026-09-13T19:00:00",
     "strStatus": "Cancelled", "strLeague": "Day League", "dateEvent": "2026-09-13"},
]}


class RefreshTest(unittest.TestCase):
    def setUp(self):
        self.cfg = json.loads(json.dumps(sports_fetch.DEFAULT_CONFIG))
        self.tmp = tempfile.mkdtemp()
        self.state_path = os.path.join(self.tmp, "sports.json")

    def test_load_config_tolerates_malformed_shapes(self):
        path = os.path.join(self.tmp, "sports-config.json")
        with open(path, "w") as fh:
            json.dump({
                "activeSports": "Soccer",
                "favouriteTeams": {"name": "Arsenal"},
                "leagues": {"Soccer": ["broken"]},
                "articlesFeeds": [],
            }, fh)
        cfg = sports_fetch.load_config(path)
        self.assertEqual(cfg["activeSports"], sports_fetch.DEFAULT_CONFIG["activeSports"])
        self.assertEqual(cfg["favouriteTeams"], [])
        self.assertEqual(cfg["leagues"], {"Soccer": []})
        self.assertEqual(cfg["articlesFeeds"], {})

    def test_refresh_merges_leagues_and_favourites(self):
        self.cfg["favouriteTeams"] = [{"idTeam": "133604", "name": "Arsenal", "sport": "Soccer"}]
        responses = {}
        responses[key("eventsnextleague.php", {"id": "4328"})] = league_next("a", [("Arsenal", "Chelsea", "2026-09-15T19:00:00")])
        responses[key("eventspastleague.php", {"id": "4328"})] = league_past("a", [(("Arsenal", "Fulham"), (2, 1), "2026-09-06T14:00:00")])
        responses[key("eventsnextleague.php", {"id": "4387"})] = league_next("b", [("Celtics", "Lakers", "2026-09-16T02:30:00")])
        responses[key("eventspastleague.php", {"id": "4387"})] = {"events": []}
        responses[key("eventsnext.php", {"id": "133604"})] = league_next("t", [("Arsenal", "Spurs", "2026-09-20T16:30:00")])
        responses[key("eventslast.php", {"id": "133604"})] = league_past("t", [(("Arsenal", "Chelsea"), (1, 0), "2026-09-13T15:00:00")], use_results=True)
        responses[key("lookup_all_players.php", {"id": "133604"})] = ROSTER
        responses[key("lookuptable.php", {"l": "4328", "s": "2026-2027"})] = TABLE
        responses[key("lookupteam.php", {"id": "133604"})] = {"teams": [{"idTeam": "133604", "strTeam": "Arsenal", "strStadium": "Emirates Stadium", "strBadge": None, "strLeague": "English Premier League", "strSport": "Soccer"}]}
        for lid in ("4414", "4430", "4416"):
            responses[key("eventsnextleague.php", {"id": lid})] = {"events": []}
            responses[key("eventspastleague.php", {"id": lid})] = {"events": []}
        for sport in ("Soccer", "Rugby", "Basketball"):
            responses[key("eventsday.php", {"d": "ANY", "s": sport})] = DAY if sport == "Basketball" else {"events": []}

        def fake_fetch(base, k, endpoint, params):
            params = dict(params)
            if endpoint == "lookuptable.php":
                params["s"] = sports_fetch.season_key_for_year(datetime(2026, 9, 13))
            if endpoint == "eventsday.php":
                params["d"] = "ANY"
            return responses.get(key(endpoint, params))

        with mock.patch.object(sports_fetch, "fetch_json", side_effect=fake_fetch):
            state = sports_fetch.refresh(self.cfg, "https://x")
        # upcoming: 2 league fixtures + 1 favourite fixture + live d2 and
        # terminal-but-unscheduled day-sweep matches
        up_ids = [e["id"] for e in state["upcoming"]]
        self.assertIn("an0", up_ids)
        self.assertIn("bn0", up_ids)
        self.assertIn("tn0", up_ids)
        self.assertIn("d2", up_ids)  # in-play day-sweep match lands in upcoming
        self.assertIn("d3", up_ids)
        self.assertIn("d4", up_ids)
        # results: past league match + favourite last match + finished day match d1
        res_ids = [e["id"] for e in state["results"]]
        self.assertIn("ap0", res_ids)
        self.assertIn("tp0", res_ids)
        self.assertIn("d1", res_ids)
        # only the in-play day-sweep match belongs in live.
        self.assertEqual(sorted(e["id"] for e in state["live"]), ["d2"])
        self.assertEqual(state["standings"]["Soccer"][0]["team"], "Liverpool")
        # roster keyed by favourite team name
        self.assertEqual(state["players"]["Arsenal"][0]["name"], "Ben White")

    def test_failed_endpoint_degrades_to_empty(self):
        with mock.patch.object(sports_fetch, "fetch_json", return_value=None):
            state = sports_fetch.refresh(self.cfg, "https://x")
        self.assertEqual(state["upcoming"], [])
        self.assertEqual(state["results"], [])
        self.assertEqual(state["standings"], {})
        self.assertEqual(state["players"], {})

    def test_compact_event_rejects_rows_without_ids(self):
        self.assertIsNone(sports_fetch.compact_event({"strHomeTeam": "x"}, "Soccer", "L"))
        self.assertIsNone(sports_fetch.compact_event(None, "Soccer", "L"))

    def test_compact_event_scores_tolerate_nulls(self):
        ev = sports_fetch.compact_event(
            {"idEvent": "1", "strEvent": "UFC Fight Night", "strHomeTeam": None, "strAwayTeam": None,
             "intHomeScore": None, "intAwayScore": None}, "Fighting", "UFC")
        self.assertIsNone(ev["homeScore"])
        self.assertEqual(ev["eventName"], "UFC Fight Night")
        self.assertIsNone(ev["homeTeam"])

    def test_refresh_lock_allows_one_writer(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "sports.json")
            first = sports_fetch.acquire_refresh_lock(path)
            self.assertIsNotNone(first)
            try:
                self.assertIsNone(sports_fetch.acquire_refresh_lock(path))
            finally:
                first.close()

    def test_compact_article_requires_safe_url_and_keeps_media(self):
        self.assertIsNone(sports_fetch.compact_article(
            {"title": "Fight Night", "url": "file:///tmp/story"}, "Fighting", "ufc.com"))
        article = sports_fetch.compact_article(
            {"title": "Fight Night", "url": "https://ufc.com/story",
             "image": "https://ufc.com/story.jpg", "summary": "Preview"},
            "Fighting", "ufc.com")
        self.assertEqual(article["sport"], "Fighting")
        self.assertEqual(article["image"], "https://ufc.com/story.jpg")
    def test_inactive_sport_skipped(self):
        self.cfg["activeSports"] = ["Soccer"]
        with mock.patch.object(sports_fetch, "fetch_json", return_value=None) as m:
            sports_fetch.refresh(self.cfg, "https://x")
            asked = {call.args[2] for call in m.call_args_list if call.args}
            league_calls = [c for c in m.call_args_list if c.args[2] == "eventsnextleague.php"]
            asked_ids = {c.args[3]["id"] for c in league_calls}
        self.assertNotIn("4387", asked_ids)  # Basketball league not fetched
        self.assertIn("4328", asked_ids)

    def test_season_key(self):
        self.assertEqual(sports_fetch.season_key_for_year(datetime(2026, 9, 13)), "2026-2027")
        self.assertEqual(sports_fetch.season_key_for_year(datetime(2026, 3, 13)), "2025-2026")

    def test_main_writes_state_atomically(self):
        with mock.patch.object(sports_fetch, "fetch_json", return_value=None), \
             mock.patch.object(sports_fetch, "fetch_articles", return_value=[]), \
             mock.patch.object(sports_fetch, "STATE_PATH", self.state_path):
            rc = sports_fetch.main(["--state", self.state_path])
        self.assertEqual(rc, 0)
        with open(self.state_path) as fh:
            doc = json.load(fh)
        self.assertEqual(doc["version"], 1)
        self.assertIn("updatedAt", doc)
        self.assertFalse(os.path.exists(self.state_path + ".tmp"))

    def test_main_preserves_cached_matches_when_source_is_unavailable(self):
        previous = {
            "version": 1,
            "updatedAt": "2026-09-13T12:00:00Z",
            "live": [],
            "upcoming": [{"id": "next-1", "homeTeam": "A", "awayTeam": "B"}],
            "results": [{"id": "result-1", "homeTeam": "C", "awayTeam": "D"}],
            "articles": [{"title": "Fresh story", "url": "https://example.test/story"}]
        }
        with open(self.state_path, "w") as fh:
            json.dump(previous, fh)
        with mock.patch.object(sports_fetch, "fetch_json", return_value=None), \
             mock.patch.object(sports_fetch, "fetch_articles", return_value=[]):
            rc = sports_fetch.main(["--state", self.state_path])
        self.assertEqual(rc, 0)
        with open(self.state_path) as fh:
            doc = json.load(fh)
        self.assertEqual(doc["upcoming"], previous["upcoming"])
        self.assertEqual(doc["results"], previous["results"])
        self.assertTrue(doc["refreshHealth"]["usedCachedMatches"])


    def test_main_preserves_saved_predictions(self):
        previous = {
            "version": 1,
            "updatedAt": "2026-09-13T12:00:00Z",
            "live": [],
            "upcoming": [],
            "results": [],
            "articles": [],
            "predictions": {
                "soccer|home|away": {
                    "sport": "Soccer",
                    "homeTeam": "Home",
                    "awayTeam": "Away",
                    "predictedWinner": "Home",
                }
            },
        }
        with open(self.state_path, "w") as fh:
            json.dump(previous, fh)
        with mock.patch.object(sports_fetch, "fetch_json", return_value=None), \
             mock.patch.object(sports_fetch, "fetch_articles", return_value=[]):
            rc = sports_fetch.main(["--state", self.state_path])
        self.assertEqual(rc, 0)
        with open(self.state_path) as fh:
            doc = json.load(fh)
        self.assertEqual(doc["predictions"], previous["predictions"])
    def test_main_preserves_cached_articles_when_feeds_are_unavailable(self):
        previous = {
            "version": 1,
            "updatedAt": "2026-09-13T12:00:00Z",
            "live": [],
            "upcoming": [],
            "results": [],
            "articles": [{"title": "Cached story", "url": "https://example.test/cached"}]
        }
        with open(self.state_path, "w") as fh:
            json.dump(previous, fh)
        with mock.patch.object(sports_fetch, "fetch_json", return_value=None), \
             mock.patch.object(sports_fetch, "fetch_articles", return_value=[]):
            rc = sports_fetch.main(["--state", self.state_path])
        self.assertEqual(rc, 0)
        with open(self.state_path) as fh:
            doc = json.load(fh)
        self.assertEqual(doc["articles"], previous["articles"])
        self.assertTrue(doc["refreshHealth"]["usedCachedArticles"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
