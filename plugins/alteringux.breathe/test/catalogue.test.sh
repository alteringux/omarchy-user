#!/usr/bin/env bash
# The breathing-technique catalogue exists three times: as canonical data in
# techniques.json, embedded as a JS literal in Model.js (QML cannot read a
# file), and embedded as a heredoc in ~/.local/bin/omarchy-breathe (which must
# run standalone). ADR-0006 accepts that duplication; this is the test that
# stops the copies drifting apart. Run:
#   bash ~/.config/omarchy/plugins/alteringux.breathe/test/catalogue.test.sh

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN=$(dirname "$HERE")
CLI="$HOME/.local/bin/omarchy-breathe"
CANON="$PLUGIN/techniques.json"

RESULTS=$(mktemp)
WORK=$(mktemp -d)
trap 'rm -rf "$RESULTS" "$WORK"' EXIT

ok()   { echo P >> "$RESULTS"; printf '  \033[32mok\033[0m   %s\n' "$1"; }
no()   { echo F >> "$RESULTS"; printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1"$'\n'"        want: [$3]"$'\n'"        got:  [$2]"; fi; }

# Sorted keys so field ORDER never counts as drift, only content.
norm() { jq -S '.' ; }

# ── the canonical file ────────────────────────────────────────────────
if [ ! -f "$CANON" ]; then
  echo "catalogue: techniques.json is missing at $CANON" >&2
  exit 1
fi
jq -e '.techniques | type == "array" and length > 0' "$CANON" >/dev/null \
  || { echo "catalogue: techniques.json has no techniques array" >&2; exit 1; }

jq '.techniques' "$CANON" | norm > "$WORK/canon.json"
ok "techniques.json parses and holds $(jq 'length' < "$WORK/canon.json") techniques"

# ── the bash CLI copy ─────────────────────────────────────────────────
# `techniques` merges in the user's custom patterns, so compare against a
# pristine state dir — a real config with customs would legitimately differ.
if [ ! -x "$CLI" ]; then
  no "omarchy-breathe is not installed at $CLI"
else
  OMARCHY_STATE_DIR="$WORK/state" OMARCHY_BREATHE_NO_DAEMON=1 OMARCHY_BREATHE_QUIET=1 \
    "$CLI" techniques | norm > "$WORK/cli.json" 2>/dev/null

  if [ ! -s "$WORK/cli.json" ]; then
    no "omarchy-breathe techniques produced nothing"
  elif diff -q "$WORK/canon.json" "$WORK/cli.json" >/dev/null; then
    ok "omarchy-breathe's embedded catalogue matches techniques.json"
  else
    no "omarchy-breathe's embedded catalogue has DRIFTED from techniques.json"
    diff -u "$WORK/canon.json" "$WORK/cli.json" | head -40
  fi
fi

# ── the Model.js copy ─────────────────────────────────────────────────
if [ ! -f "$PLUGIN/Model.js" ]; then
  skip "Model.js is not present yet — its copy was not compared"
elif ! command -v node >/dev/null 2>&1; then
  skip "node is not available — Model.js's copy was not compared"
else
  node -e '
    const Model = require(process.argv[1] + "/Model.js")
    process.stdout.write(JSON.stringify(Model.TECHNIQUES))
  ' "$PLUGIN" 2>/dev/null | norm > "$WORK/model.json"

  if [ ! -s "$WORK/model.json" ]; then
    no "Model.js did not expose TECHNIQUES"
  elif diff -q "$WORK/canon.json" "$WORK/model.json" >/dev/null; then
    ok "Model.js's embedded catalogue matches techniques.json"
  else
    no "Model.js's embedded catalogue has DRIFTED from techniques.json"
    diff -u "$WORK/canon.json" "$WORK/model.json" | head -40
  fi
fi

# ── the check can actually fail ───────────────────────────────────────
# A comparison that always passes certifies nothing. Prove the diff notices a
# single changed second before trusting a clean result above.
jq '(.[0].phases[0].seconds) += 1' "$WORK/canon.json" | norm > "$WORK/tampered.json"
if diff -q "$WORK/canon.json" "$WORK/tampered.json" >/dev/null; then
  no "CONTROL: the comparison did not notice a deliberately changed duration"
else
  ok "control: the comparison does notice a one-second change"
fi

# ── structural invariants every copy must hold ────────────────────────
check "every technique declares an id"      "$(jq '[.[] | select(.id == null or .id == "")] | length' < "$WORK/canon.json")" 0
check "every technique declares phases"     "$(jq '[.[] | select((.phases | length) == 0)] | length' < "$WORK/canon.json")" 0
check "no phase has a non-positive length"  "$(jq '[.[].phases[] | select(.seconds <= 0)] | length' < "$WORK/canon.json")" 0
check "no technique has a zero cycle count" "$(jq '[.[] | select((.defaultCycles // 0) <= 0)] | length' < "$WORK/canon.json")" 0
check "ids are unique"                      "$(jq '(length - ([.[].id] | unique | length))' < "$WORK/canon.json")" 0
check "every phase kind is declared"        "$(jq --slurpfile c "$CANON" '[.[].phases[].kind] | unique - $c[0].phaseKinds | length' < "$WORK/canon.json")" 0
check "power-breath phases carry a count"   "$(jq '[.[].phases[] | select(.kind == "POWER_BREATHS" and ((.breaths // 0) <= 0))] | length' < "$WORK/canon.json")" 0

# ── the two phase resolvers agree ─────────────────────────────────────
# resolve() also exists twice: in Model.js for the widget's frames, and in the
# CLI's jq library for the daemon's transitions. If they disagree, the bar
# shows one phase while the daemon cues another — so sample both across the
# techniques whose shapes are awkward (a sip on top, power breaths, an
# eight-phase both-sides cycle, one-second phases).
if [ ! -x "$CLI" ] || [ ! -f "$PLUGIN/Model.js" ] || ! command -v node >/dev/null 2>&1; then
  skip "resolver cross-check needs both the CLI and Model.js"
else
  resolver_state="$WORK/resolver"
  mkdir -p "$resolver_state"
  export OMARCHY_STATE_DIR="$resolver_state" OMARCHY_BREATHE_NO_DAEMON=1 OMARCHY_BREATHE_QUIET=1
  "$CLI" get >/dev/null 2>&1
  mismatches=0
  points=0
  for technique in box relaxing478 wim-hof nadi-shodhana bellows physiological-sigh buteyko vortex; do
    "$CLI" start "$technique" >/dev/null 2>&1 || continue
    planned="$(jq -r '.cycles' "$resolver_state/breathe-session.json")"
    for ms in 0 1500 4000 12500 31000 65000 91000 150000; do
      jq --argjson e "$ms" '.state="PAUSED" | .elapsedMs=$e' \
        "$resolver_state/breathe-session.json" > "$resolver_state/.s" \
        && mv "$resolver_state/.s" "$resolver_state/breathe-session.json"
      from_cli="$("$CLI" status | jq -r '[.phaseKind, .cycleIndex] | @tsv')"
      from_model="$(node -e '
        const M = require(process.argv[1] + "/Model.js")
        const t = M.techniqueById(process.argv[2])
        const r = M.resolve({ state: "PAUSED", cycles: +process.argv[4], elapsedMs: +process.argv[3], savedAtMs: 0 }, t, 0)
        process.stdout.write(r.phaseKind + "\t" + r.cycleIndex)
      ' "$PLUGIN" "$technique" "$ms" "$planned")"
      points=$((points + 1))
      if [ "$from_cli" != "$from_model" ]; then
        mismatches=$((mismatches + 1))
        printf '        %s @%sms  cli=[%s] model=[%s]\n' "$technique" "$ms" "$from_cli" "$from_model"
      fi
    done
  done
  unset OMARCHY_STATE_DIR OMARCHY_BREATHE_NO_DAEMON OMARCHY_BREATHE_QUIET
  check "the CLI and Model.js resolve the same phase at $points sample points" "$mismatches" 0
fi

P=$(grep -c P "$RESULTS" || true); F=$(grep -c F "$RESULTS" || true)
printf '\n%s passed, %s failed\n' "$P" "$F"
[ "$F" = 0 ]
