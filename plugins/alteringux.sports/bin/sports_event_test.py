#!/usr/bin/env python3
import contextlib
import io
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(__file__))
import sports_event
import sports_fetch


class SportsEventTests(unittest.TestCase):
    def test_compact_stats_keeps_home_and_away_values(self):
        stats = sports_event.compact_stats({"eventstats": [
            {"strStat": "Possession", "intHome": "54", "intAway": "46"},
            {"strStat": "Shots", "strHome": "8", "strAway": "5"},
        ]})
        self.assertEqual(stats, [
            {"name": "Possession", "home": "54", "away": "46"},
            {"name": "Shots", "home": "8", "away": "5"},
        ])

    def test_compact_event_exposes_video_and_context(self):
        event = sports_fetch.compact_event({
            "idEvent": "42",
            "strEvent": "Home v Away",
            "strSport": "Soccer",
            "strLeague": "Test League",
            "strHomeTeam": "Home",
            "strAwayTeam": "Away",
            "strVideo": "https://cdn.example/video",
            "strVenue": "Test Stadium",
            "strOfficial": "A. Referee",
            "intSpectators": "1000",
        }, "Soccer", "Test League")
        self.assertEqual(event["videoUrl"], "https://cdn.example/video")
        self.assertIn("youtube.com/results?search_query=", event["youtubeHighlightsUrl"])
        self.assertEqual(event["official"], "A. Referee")
        self.assertEqual(event["attendance"], "1000")

    def test_fetch_event_allows_missing_provider_stats(self):
        event_doc = {"events": [{
            "idEvent": "42",
            "strEvent": "Home v Away",
            "strSport": "Soccer",
            "strLeague": "Test League",
            "strHomeTeam": "Home",
            "strAwayTeam": "Away",
        }]}
        with mock.patch.object(sports_event.fetch, "fetch_json", side_effect=[event_doc, {"eventstats": None}]):
            with mock.patch.object(sports_event.fetch, "load_config", return_value={"apiKey": "3"}) as config_mock:
                payload = sports_event.fetch_event("42", "/tmp/config")
        config_mock.assert_called_once_with("/tmp/config")
        self.assertIsNone(payload["error"])
        self.assertEqual(payload["event"]["id"], "42")
        self.assertEqual(payload["stats"], [])

    def test_cli_outputs_json_for_mocked_event(self):
        payload = {"version": 1, "event": {"id": "42"}, "stats": [], "error": None}
        output = io.StringIO()
        with mock.patch.object(sports_event, "fetch_event", return_value=payload), contextlib.redirect_stdout(output):
            code = sports_event.main(["--id", "42"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(output.getvalue()), payload)

    def test_compact_event_rejects_unsafe_video(self):
        event = sports_fetch.compact_event({"idEvent": "42", "strVideo": "javascript:alert(1)"}, "Soccer", "")
        self.assertIsNone(event["videoUrl"])


if __name__ == "__main__":
    unittest.main()
