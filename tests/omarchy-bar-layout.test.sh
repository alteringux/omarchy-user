#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
CONFIG="$REPO/shell.json"
BOTTOM="$REPO/plugins/alteringux.bottombar/BottomBar.qml"

command -v jq >/dev/null
command -v python3 >/dev/null

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hypr_dir=$(find "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2-)
  [[ -n "$hypr_dir" ]] && export HYPRLAND_INSTANCE_SIGNATURE=${hypr_dir##*/}
fi

top=$(omarchy shell shell debugBarGeometry)
bottom=$(omarchy shell alteringux.bottombar geometry)
budget=$(omarchy shell alteringux.bottombar budget)
status=$(omarchy shell alteringux.bottombar status)
width=$(hyprctl -j monitors | jq -r '.[0] | (.width / .scale)')
height=$(hyprctl -j monitors | jq -r '.[0] | (.height / .scale)')
monitor=$(hyprctl -j monitors | jq -r '.[0].name')
layers=$(hyprctl -j layers)

python3 - "$CONFIG" "$BOTTOM" "$top" "$bottom" "$budget" "$status" "$width" "$height" "$monitor" "$layers" <<'PY'
import json
import re
import sys

config_path, bottom_path, top_raw, bottom_raw, budget_raw, status_raw, monitor_width, monitor_height, monitor, layers_raw = sys.argv[1:]
config = json.load(open(config_path, encoding="utf-8"))
top = json.loads(top_raw)
bottom = json.loads(bottom_raw)
budget = json.loads(budget_raw)
status = json.loads(status_raw)
layers = json.loads(layers_raw)
width = float(monitor_width)
height = float(monitor_height)

def visible_rows(name, rows):
    rows = [row for row in rows if row.get("visible") and row.get("width", 0) > 0]
    seen = set()
    placed = []
    for row in sorted(rows, key=lambda item: (item.get("y", 0), item["x"])):
        ident = row["id"]
        if ident in seen:
            raise SystemExit(f"{name}: duplicate visible widget {ident}")
        seen.add(ident)
        start = float(row["x"])
        end = start + float(row["width"])
        if start < -1 or end > width + 1:
            raise SystemExit(f"{name}: {ident} is outside 0..{width:g}: {start:g}..{end:g}")
        top = float(row.get("y", 0))
        bottom = top + float(row.get("height", 0))
        for prior in placed:
            horizontal = start < prior["end"] - 1 and prior["start"] < end - 1
            vertical = top < prior["bottom"] - 1 and prior["top"] < bottom - 1
            if horizontal and vertical:
                raise SystemExit(f"{name}: overlap at {ident} with {prior['id']}")
        placed.append({"id": ident, "start": start, "end": end, "top": top, "bottom": bottom})
    return seen

top_ids = visible_rows("top", top)
bottom_ids = visible_rows("bottom", bottom)
if "alteringux.countdown" not in bottom_ids:
    raise SystemExit("countdown must remain visible on the compact bottom taskbar")
if top_ids & bottom_ids:
    raise SystemExit(f"top/bottom duplicate ownership: {sorted(top_ids & bottom_ids)}")
sections = {row["id"]: row["section"] for row in bottom if row.get("visible") and row.get("width", 0) > 0}
expected_side = {"omarchy.menu": "side-left", "alteringux.dashboard": "side-left",
                 "alteringux.skilldashboard": "side-right",
                 "io.github.kristoferlund.webcam": "side-right"}
for ident, section in expected_side.items():
    if sections.get(ident) != section:
        raise SystemExit(f"icon button {ident} missing from {section}: {sections.get(ident)}")
enabled = {name.split(" (")[0] for name in status["widgets"]}
for ident in ("alteringux.flow", "alteringux.cliamp", "alteringux.stocks",
              "alteringux.sports", "alteringux.breathe"):
    if ident in enabled and sections.get(ident) != "overflow":
        raise SystemExit(f"changing widget {ident} missing from horizontal overflow row")
if any(name.endswith(" (pending)") or name.endswith(" (failed)") for name in status["widgets"]):
    raise SystemExit(f"hosted widget failed to load: {status['widgets']}")

layout = config["bar"]["layout"]
configured = [item["id"] for section in ("left", "center", "right") for item in layout[section]]
if len(configured) != len(set(configured)):
    raise SystemExit("shell.json contains duplicate top-bar widget ids")

source = open(bottom_path, encoding="utf-8").read()
sections = re.findall(r"(?:leftCandidates|rightCandidates|overflowCandidates|sideLeftCandidates|sideRightCandidates): \[(.*?)\]", source, re.S)
candidate_ids = [ident for section in sections for ident in re.findall(r'id: "([^"]+)"', section)]
if len(candidate_ids) != len(set(candidate_ids)):
    raise SystemExit("BottomBar.qml contains duplicate candidate ids")
if set(configured) & set(candidate_ids):
    raise SystemExit("a widget is configured in both top and bottom candidates")

for label in ("current", "minimum"):
    result = budget[label]
    if not result["fits"] or result["total"] > result["available"]:
        raise SystemExit(f"{label} bottom budget overlaps: {result}")
    if not 0 < result["scale"] <= 1:
        raise SystemExit(f"{label} invalid compression scale: {result}")

layer_rows = []
for level in layers.get(monitor, {}).get("levels", {}).values():
    layer_rows.extend(level)
bars = {row["namespace"]: row for row in layer_rows
        if row.get("namespace") in ("omarchy-bar", "alteringux-overflow-topbar",
                                     "alteringux-bottombar", "omarchy-newsbar",
                                     "alteringux-sidebar-left", "alteringux-sidebar-right")}
expected_bars = {"omarchy-bar", "alteringux-overflow-topbar",
                 "alteringux-bottombar", "alteringux-sidebar-left",
                 "alteringux-sidebar-right"}
# NewsBar intentionally targets the machine's built-in eDP-1 display. A
# headless/fallback compositor has no such output and should not fail this
# geometry check for a surface that cannot exist there.
if monitor == "eDP-1":
    expected_bars.add("omarchy-newsbar")
if set(bars) != expected_bars:
    raise SystemExit(f"missing taskbar layer surface: {sorted(bars)}")
top_surface = bars["omarchy-bar"]
overflow_surface = bars["alteringux-overflow-topbar"]
bottom_surface = bars["alteringux-bottombar"]
news_surface = bars.get("omarchy-newsbar")
left_sidebar = bars["alteringux-sidebar-left"]
right_sidebar = bars["alteringux-sidebar-right"]
if top_surface["y"] + top_surface["h"] != overflow_surface["y"] or overflow_surface["h"] != 35:
    raise SystemExit(f"top overflow row is not stacked under the main bar: {top_surface} / {overflow_surface}")
if bottom_surface["h"] != 35 or (news_surface and bottom_surface["y"] + bottom_surface["h"] != news_surface["y"]):
    raise SystemExit(f"bottom taskbar is not one row above NewsBar: {bottom_surface} / {news_surface}")
lower_surface_top = news_surface["y"] if news_surface else bottom_surface["y"]
for label, side, edge in (("left", left_sidebar, 0), ("right", right_sidebar, width)):
    edge_ok = side["x"] == edge if label == "left" else side["x"] + side["w"] == width
    if side["w"] != 30 or not edge_ok:
        raise SystemExit(f"{label} sidebar is not a readable 30px idle rail: {side}")
    if side["y"] < 34 or side["y"] + side["h"] < lower_surface_top - 1:
        raise SystemExit(f"{label} sidebar does not span the usable screen edge: {side}")
if news_surface and bottom_surface["y"] + bottom_surface["h"] > news_surface["y"]:
    raise SystemExit(f"bottom bar/news bar vertical overlap: {bottom_surface} / {news_surface}")
for surface in (overflow_surface, bottom_surface, *([news_surface] if news_surface else [])):
    for side in (left_sidebar, right_sidebar):
        vertical = surface["y"] < side["y"] + side["h"] - 1 and side["y"] < surface["y"] + surface["h"] - 1
        horizontal = surface["x"] < side["x"] + side["w"] - 1 and side["x"] < surface["x"] + surface["w"] - 1
        if vertical and horizontal:
            raise SystemExit(f"horizontal surface crosses sidebar: {surface} / {side}")
bottom_edge = max(row["y"] + row["h"] for row in (bottom_surface, *([news_surface] if news_surface else [])))
if bottom_edge < height - 1:
    raise SystemExit(f"bottom bar/news bar leave a gap below the screen edge: end={bottom_edge:g} height={height:g}")

print(f"top={len(top_ids)} bottom={len(bottom_ids)} current={budget['current']['total']}/{budget['current']['available']} minimum={budget['minimum']['total']}/{budget['minimum']['available']}")
PY

# Representative click/popup routing probes. These return non-zero if the
# hosted top and bottom widgets lost their IPC handlers during reorganisation.
omarchy shell alteringux.clock open >/dev/null
omarchy shell alteringux.clock close >/dev/null
omarchy shell alteringux.flow open >/dev/null
omarchy shell alteringux.flow close >/dev/null
omarchy shell alteringux.dashboard open >/dev/null
omarchy shell alteringux.dashboard close >/dev/null
omarchy shell alteringux.skilldashboard open >/dev/null
omarchy shell alteringux.skilldashboard close >/dev/null
omarchy shell io.github.kristoferlund.webcam open >/dev/null
omarchy shell io.github.kristoferlund.webcam close >/dev/null

printf 'bar layout checks passed\n'
