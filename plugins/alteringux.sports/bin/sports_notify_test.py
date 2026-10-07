#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(__file__))
import sports_notify


class SportsNotifyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state_path = os.path.join(self.tmp.name, "sports.json")
        self.marker_path = os.path.join(self.tmp.name, "notifications.json")

    def tearDown(self):
        self.tmp.cleanup()

    def write_state(self, live):
        with open(self.state_path, "w", encoding="utf-8") as fh:
            json.dump({"live": live}, fh)

    def test_notifies_new_in_play_event_through_pulse(self):
        self.write_state([{
            "id": "42", "sport": "Soccer", "homeTeam": "Home", "awayTeam": "Away", "status": "1H"
        }])
        with mock.patch.object(sports_notify.subprocess, "run", return_value=mock.Mock(returncode=0)) as run:
            sent = sports_notify.notify_started(self.state_path, self.marker_path, "pulse", now=100)
        self.assertEqual(sent, ["Home vs Away"])
        command = run.call_args.args[0]
        self.assertEqual(command[:4], ["pulse", "log", "alteringux.sports", "Started: Home vs Away"])
        self.assertIn("--notify", command)

    def test_deduplicates_event_and_ignores_finished_status(self):
        self.write_state([{
            "id": "42", "sport": "Soccer", "homeTeam": "Home", "awayTeam": "Away", "status": "LIVE"
        }])
        with mock.patch.object(sports_notify.subprocess, "run", return_value=mock.Mock(returncode=0)) as run:
            self.assertEqual(sports_notify.notify_started(self.state_path, self.marker_path, "pulse", now=100), ["Home vs Away"])
            self.assertEqual(sports_notify.notify_started(self.state_path, self.marker_path, "pulse", now=101), [])
        self.assertEqual(run.call_count, 1)

        self.write_state([{
            "id": "43", "sport": "Soccer", "homeTeam": "Finished", "awayTeam": "Game", "status": "FT"
        }])
        with mock.patch.object(sports_notify.subprocess, "run") as run:
            self.assertEqual(sports_notify.notify_started(self.state_path, self.marker_path, "pulse", now=102), [])
        run.assert_not_called()

    def test_failed_pulse_delivery_is_retryable(self):
        self.write_state([{
            "id": "42", "eventName": "Fight Night", "sport": "Fighting", "status": "LIVE"
        }])
        with mock.patch.object(sports_notify.subprocess, "run", return_value=mock.Mock(returncode=1)):
            self.assertEqual(sports_notify.notify_started(self.state_path, self.marker_path, "pulse", now=100), [])
        with open(self.marker_path, encoding="utf-8") as fh:
            self.assertEqual(json.load(fh), {})


if __name__ == "__main__":
    unittest.main(verbosity=2)
