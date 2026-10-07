#!/usr/bin/env python3
"""Tests for sports_predict.py — run with:
    python3 bin/sports_predict_test.py
Fully offline; feeds canned state dicts.
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sports_predict as sp  # noqa: E402


def ev(id_, home, away, hs, as_, date="2026-09-0", status="Match Finished"):
    return {"id": id_, "sport": "Soccer", "league": "L", "homeTeam": home, "awayTeam": away,
            "homeScore": hs, "awayScore": as_, "dateEvent": f"{date}{len(id_)}",
            "status": status}


STATE = {
    "version": 1,
    "results": [
        ev("1", "Arsenal", "Fulham", 2, 0, date="2026-09-0"),
        ev("2", "Chelsea", "Arsenal", 0, 3, date="2026-09-0"),
        ev("3", "Arsenal", "Spurs", 1, 1, date="2026-09-0"),
        ev("4", "Liverpool", "Arsenal", 1, 2, date="2026-09-0"),
        ev("5", "Arsenal", "Everton", 3, 1, date="2026-09-0"),
        ev("6", "Chelsea", "Fulham", 1, 1, date="2026-09-0"),
        ev("7", "Fulham", "Chelsea", 2, 0, date="2026-09-0"),
        ev("8", "Chelsea", "Spurs", 2, 2, date="2026-09-0"),
        ev("9", "Everton", "Chelsea", 0, 1, date="2026-09-0"),
        ev("10", "Chelsea", "Liverpool", 1, 3, date="2026-09-0"),
        # an unfinished fixture must be ignored
        ev("11", "Arsenal", "Chelsea", None, None, date="2026-09-1", status="NS"),
    ],
    "standings": {"Soccer": [
        {"intRank": "1", "team": "Arsenal"}, {"intRank": "2", "team": "Liverpool"},
        {"intRank": "3", "team": "Chelsea"}, {"intRank": "4", "team": "Fulham"}
    ]}
}


class PredictTest(unittest.TestCase):
    def test_stronger_home_side_wins_with_sane_confidence(self):
        out = sp.predict(STATE, "Soccer", "Arsenal", "Chelsea")
        self.assertEqual(out["predictedWinner"], "Arsenal")
        self.assertGreater(out["confidence"], 0.5)
        self.assertLessEqual(out["confidence"], 1.0)
        self.assertIsNotNone(out["breakdown"]["form"])
        self.assertTrue(out["reason"])

    def test_auto_predictions_cover_live_and_upcoming_team_matches(self):
        state = dict(STATE)
        state["live"] = [ev("live-1", "Arsenal", "Chelsea", None, None, status="2H")]
        state["upcoming"] = [
            ev("next-1", "Chelsea", "Fulham", None, None, status="NS"),
            {"id": "fight-1", "sport": "Fighting", "eventName": "Fight Night",
             "homeTeam": None, "awayTeam": None},
        ]
        predictions = sp.auto_predictions(state)
        self.assertEqual(set(predictions), {
            sp.prediction_key("Soccer", "Arsenal", "Chelsea"),
            sp.prediction_key("Soccer", "Chelsea", "Fulham"),
        })
        for output in predictions.values():
            self.assertIn("reason", output)
            self.assertIn("eventId", output)

    def test_home_advantage_tilts_even_matchups(self):
        # identical form/standing; only the home tilt differs
        st = {"results": [
                ev("1", "A", "C", 1, 0), ev("2", "C", "A", 1, 0),
                ev("3", "A", "D", 2, 0), ev("4", "D", "A", 0, 1),
                ev("5", "A", "E", 1, 0), ev("6", "E", "A", 2, 1)],
              "standings": {"Soccer": [{"intRank": "1", "team": "A"}, {"intRank": "2", "team": "C"}]}}
        out = sp.predict(st, "Soccer", "A", "C")
        self.assertEqual(out["predictedWinner"], "A")

    def test_no_data_yields_error_payload(self):
        out = sp.predict({}, "Soccer", "X", "Y")
        self.assertIsNone(out["predictedWinner"])

    def test_result_for_perspectives(self):
        m = ev("1", "A", "B", 2, 1)
        self.assertEqual(sp.result_for(m, "A"), 1)
        self.assertEqual(sp.result_for(m, "B"), -1)
        d = ev("2", "A", "B", 1, 1)
        self.assertEqual(sp.result_for(d, "B"), 0)

    def test_team_matches_skips_unfinished(self):
        ms = sp.team_matches(STATE, "Arsenal", "Soccer", limit=5)
        self.assertEqual(len(ms), 5)
        for m in ms:
            self.assertIsNotNone(m["homeScore"])

    def test_h2h_counts_meetings(self):
        f = sp.h2h_factor(STATE, "Arsenal", "Chelsea", "Soccer")
        self.assertIsNotNone(f)
        self.assertGreater(f, 0.5)  # Arsenal beat Chelsea home and away

    def test_standing_factor_ranks_top_team_one(self):
        self.assertEqual(sp.standing_factor(STATE, "Arsenal", "Soccer"), 1.0)
        self.assertEqual(sp.standing_factor(STATE, "Fulham", "Soccer"), 0.0)

    def test_cli_error_payload_exits_nonzero(self):
        tmp = tempfile.mkdtemp()
        p = os.path.join(tmp, "empty.json")
        with open(p, "w") as fh:
            json.dump({"results": []}, fh)
        rc = sp.main(["--sport", "Soccer", "--home", "X", "--away", "Y", "--state", p])
        self.assertEqual(rc, 1)

    def test_cli_ok_exits_zero(self):
        tmp = tempfile.mkdtemp()
        p = os.path.join(tmp, "s.json")
        with open(p, "w") as fh:
            json.dump(STATE, fh)
        rc = sp.main(["--sport", "Soccer", "--home", "Arsenal", "--away", "Chelsea", "--state", p])
        self.assertEqual(rc, 0)

    def test_cli_persist_writes_prediction_back_to_state(self):
        tmp = tempfile.mkdtemp()
        p = os.path.join(tmp, "s.json")
        with open(p, "w") as fh:
            json.dump(STATE, fh)
        rc = sp.main([
            "--sport", "Soccer", "--home", "Arsenal", "--away", "Chelsea",
            "--state", p, "--persist"
        ])
        self.assertEqual(rc, 0)
        with open(p) as fh:
            saved = json.load(fh)
        key = sp.prediction_key("Soccer", "Arsenal", "Chelsea")
        self.assertEqual(saved["predictions"][key]["predictedWinner"], "Arsenal")


if __name__ == "__main__":
    unittest.main(verbosity=2)
