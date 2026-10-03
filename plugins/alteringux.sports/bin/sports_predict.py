#!/usr/bin/env python3
"""omarchy-sports-predict -- compare two teams' recent form and predict a winner.

Weighted model over four normalised 0..1 factors (home team perspective):
  form     0.40   points-per-game over each side's last 5 finished matches
  h2h      0.25   head-to-head record between the two sides
  home     0.20   home vs away split of recent results
  standing 0.15   normalised league position from the state file's standings

Data comes from the plugin's own state file (written by omarchy-sports-refresh)
-- this script never touches the network. Historical matches are read from the
TheSportsDB eventseason + team last-events endpoints ONLY as far as the refresh
script cached them; prediction quality therefore grows with refresh history.

Usage:
    omarchy-sports-predict --sport Soccer --home Arsenal --away Chelsea \
        [--state PATH] [--season KEY]

Output: one JSON object on stdout, e.g.
    {"version":1,"sport":"Soccer","homeTeam":"Arsenal","awayTeam":"Chelsea",
     "predictedWinner":"Arsenal","confidence":0.63,
     "breakdown":{"form":0.55,"h2h":0.5,"home":0.72,"standing":0.9},
     "sample":{"homeMatches":5,"awayMatches":5,"h2hMatches":3},
     "error":null}

Exit codes: 0 ok | 1 insufficient data | 2 bad arguments
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
STATE_PATH = os.path.join(HOME, ".local", "state", "omarchy", "sports.json")

W_FORM = 0.40
W_H2H = 0.25
W_HOME = 0.20
W_STANDING = 0.15

FINISHED_STATUSES = {"FT", "Match Finished", "AET", "PEN", "Finished",
                     "After Over Time", "After Penalties"}


def load_state(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def prediction_key(sport, home_team, away_team):
    parts = (sport, home_team, away_team)
    return "|".join(" ".join(str(part or "").split()).casefold() for part in parts)


def persist_prediction(path, output):
    state = load_state(path)
    predictions = state.get("predictions")
    if not isinstance(predictions, dict):
        predictions = {}
    saved = dict(output)
    saved["savedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    predictions[prediction_key(output["sport"], output["homeTeam"], output["awayTeam"])] = saved
    state["predictions"] = predictions
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(temporary, path)
    return saved


def is_finished(ev):
    st = (ev.get("status") or "").strip()
    if st in FINISHED_STATUSES:
        return True
    return ev.get("homeScore") is not None and ev.get("awayScore") is not None and bool(st)


def team_matches(state, team, sport=None, limit=5):
    """Most recent finished matches featuring `team`, newest first."""
    pool = []
    for section in ("results", "live"):
        for ev in state.get(section) or []:
            if sport and ev.get("sport") and ev["sport"] != sport:
                continue
            if ev.get("homeTeam") == team or ev.get("awayTeam") == team:
                pool.append(ev)
    pool.sort(key=lambda e: e.get("dateEvent") or "", reverse=True)
    out = []
    for ev in pool:
        if is_finished(ev):
            out.append(ev)
        if len(out) >= limit:
            break
    return out


def result_for(ev, team):
    """1 win | 0 draw | -1 loss, from `team`'s perspective."""
    hs, as_ = ev.get("homeScore"), ev.get("awayScore")
    if hs is None or as_ is None:
        return None
    home = ev.get("homeTeam") == team
    mine, theirs = (hs, as_) if home else (as_, hs)
    if mine > theirs:
        return 1
    if mine < theirs:
        return -1
    return 0


def form_factor(matches, team):
    """Mean result over recent matches, mapped to 0..1 (loss=0, draw=.5, win=1)."""
    if not matches:
        return None
    vals = [result_for(ev, team) for ev in matches]
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    return (sum(1 if v == 1 else (0.5 if v == 0 else 0.0) for v in vals)) / len(vals)


def h2h_factor(state, team_a, team_b, sport=None, limit=10):
    """team_a's win share across finished meetings with team_b (0..1)."""
    meetings = []
    for ev in (state.get("results") or []):
        pair = {ev.get("homeTeam"), ev.get("awayTeam")}
        if pair == {team_a, team_b} and is_finished(ev):
            meetings.append(ev)
    if not meetings:
        return None
    score = 0.0
    for ev in meetings:
        r = result_for(ev, team_a)
        if r == 1:
            score += 1.0
        elif r == 0:
            score += 0.5
    return score / len(meetings)


def home_factor(matches, team):
    """Share of points earned in home vs away games, tilted to home advantage."""
    if not matches:
        return None
    home_pts, away_pts, games = 0.0, 0.0, 0
    for ev in matches:
        r = result_for(ev, team)
        if r is None:
            continue
        pts = {1: 3.0, 0: 1.0, -1: 0.0}[r]
        games += 1
        if ev.get("homeTeam") == team:
            home_pts += pts
        else:
            away_pts += pts
    if games == 0:
        return None
    # 0..1 where 0.5 = balanced home/away returns; > 0.5 = stronger at home
    total = home_pts + away_pts
    if total == 0:
        return None
    share = home_pts / total
    # most teams win more at home; map share 0.5..0.8 onto 0..1
    return max(0.0, min(1.0, (share - 0.5) / 0.3 + 0.5))


def standing_factor(state, team, sport=None):
    """Rank-derived 0..1 (top = 1) from the cached league table."""
    tables = state.get("standings") or {}
    rows = None
    if sport and sport in tables:
        rows = tables[sport]
    else:
        for v in tables.values():
            if any(r.get("team") == team for r in v or []):
                rows = v
                break
    if not rows:
        return None
    n = len(rows)
    if n < 2:
        return None
    for r in rows:
        if r.get("team") == team:
            try:
                rank = int(r.get("intRank") or r.get("rank"))
            except (TypeError, ValueError):
                return None
            return (n - rank) / (n - 1)
    return None


def predict(state, sport, home_team, away_team):
    home_matches = team_matches(state, home_team, sport)
    away_matches = team_matches(state, away_team, sport)
    form = form_factor(home_matches, home_team)
    away_form = form_factor(away_matches, away_team)
    h2h = h2h_factor(state, home_team, away_team, sport)
    homeadv = home_factor(home_matches, home_team)
    standing = standing_factor(state, home_team, sport)
    away_standing = standing_factor(state, away_team, sport)

    parts, weights = [], []
    if form is not None and away_form is not None:
        parts.append(form - away_form)
        weights.append(W_FORM)
    if h2h is not None:
        parts.append(h2h - 0.5)
        weights.append(W_H2H)
    if homeadv is not None:
        parts.append(homeadv * 0.5)  # tilt, not a full factor
        weights.append(W_HOME)
    if standing is not None and away_standing is not None:
        parts.append(standing - away_standing)
        weights.append(W_STANDING)

    if not weights:
        return {
            "version": 1, "sport": sport,
            "homeTeam": home_team, "awayTeam": away_team,
            "predictedWinner": None, "confidence": None, "breakdown": None,
            "sample": {"homeMatches": len(home_matches), "awayMatches": len(away_matches)},
            "reason": "Not enough finished-match history is cached for this matchup yet.",
            "error": "no finished matches found in the cached state; run a refresh first"
        }
    total_w = sum(weights)
    edge = sum(p * w for p, w in zip(parts, weights)) / total_w
    confidence = max(0.0, min(1.0, 0.5 + edge / 2))
    winner = home_team if edge >= 0 else away_team
    breakdown = {
        "form": None if form is None else round(form - away_form, 2),
        "h2h": None if h2h is None else round(h2h, 2),
        "home": None if homeadv is None else round(homeadv, 2),
        "standing": None if (standing is None or away_standing is None)
                    else round(standing - away_standing, 2)
    }
    reason = prediction_reason(home_team, away_team, breakdown)
    return {
        "version": 1,
        "sport": sport,
        "homeTeam": home_team,
        "awayTeam": away_team,
        "predictedWinner": winner,
        "confidence": round(confidence, 2),
        "breakdown": breakdown,
        "sample": {
            "homeMatches": len(home_matches),
            "awayMatches": len(away_matches),
            "h2hMatches": None if h2h is None else True
        },
        "reason": reason,
        "error": None
    }


def prediction_reason(home_team, away_team, breakdown):
    labels = {
        "form": "recent form",
        "h2h": "head-to-head history",
        "home": "home advantage",
        "standing": "league standing",
    }
    evidence = []
    for name, value in breakdown.items():
        if value is None or abs(value) < 0.05:
            continue
        team = home_team if value > 0 else away_team
        evidence.append((abs(value), f"{labels[name]} favors {team}"))
    evidence.sort(reverse=True)
    if not evidence:
        return "The model sees a near-even matchup from the cached data."
    return "; ".join(item[1][0].upper() + item[1][1:] for item in evidence[:2]) + "."


def auto_predictions(state):
    """Return predictions for every distinct upcoming/live team matchup."""
    outputs = {}
    for section in ("live", "upcoming"):
        for event in state.get(section) or []:
            sport = event.get("sport")
            home = event.get("homeTeam")
            away = event.get("awayTeam")
            if not sport or not home or not away or home == away:
                continue
            output = predict(state, sport, home, away)
            output["eventId"] = event.get("id")
            output["savedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            outputs[prediction_key(sport, home, away)] = output
    return outputs


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--sport", required=True)
    ap.add_argument("--home", required=True, dest="home_team")
    ap.add_argument("--away", required=True, dest="away_team")
    ap.add_argument("--state", default=STATE_PATH)
    ap.add_argument("--persist", action="store_true",
                    help="save a successful prediction in the state file")
    args = ap.parse_args(argv)

    state = load_state(args.state)
    out = predict(state, args.sport, args.home_team, args.away_team)
    if args.persist and not out.get("error"):
        try:
            out = persist_prediction(args.state, out)
        except OSError as exc:
            out = dict(out)
            out["error"] = f"could not save prediction: {exc}"
    print(json.dumps(out))
    return 1 if out.get("error") else 0

if __name__ == "__main__":
    sys.exit(main())
