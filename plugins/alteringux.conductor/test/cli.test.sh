#!/usr/bin/env bash
# Black-box tests for ~/.local/bin/omarchy-conductor — the ritual engine that
# fans one command out across every other alteringux plugin CLI.
#
# Every plugin CLI is replaced with a stub that logs its argv, so the tests
# assert *which verbs fired, in what order, with what token substitution*
# without touching real pomodoro / timer / VPN state. The systemd daemon is
# disabled (OMARCHY_CONDUCTOR_NO_DAEMON=1); phase transitions are driven by
# calling `phase` directly, which is exactly what the daemon does.
#
#   bash test/cli.test.sh
set -uo pipefail

CLI="${OMARCHY_CONDUCTOR_BIN:-$HOME/.local/bin/omarchy-conductor}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
BIN="$(mktemp -d)"
RIT="$(mktemp -d)"
trap 'rm -rf "$WORK" "$BIN" "$RIT"' EXIT

export OMARCHY_STATE_DIR="$WORK"
export OMARCHY_CONDUCTOR_RITUAL_DIR="$RIT"
export OMARCHY_CONDUCTOR_NO_DAEMON=1
export OMARCHY_CONDUCTOR_QUIET=1
export PATH="$BIN:$PATH"
CALLS="$WORK/calls.log"
: > "$CALLS"

# ── stub plugin CLIs ────────────────────────────────────────────────────
for tool in omarchy-pomodoro omarchy-timers omarchy-score omarchy-stopwatch \
            omarchy-remind omarchy-dashboard-note omarchy-newsbar-refresh \
            omarchy-stocks-commentary omarchy-dictionary-suggest-daily flow; do
  cat > "$BIN/$tool" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$tool" "\$*" >> "$CALLS"
exit 0
EOF
  chmod +x "$BIN/$tool"
done

# a stub that always fails — stands in for an optional step that errors
cat > "$BIN/protonvpn-rotate" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "protonvpn-rotate" "\$*" >> "$CALLS"
exit 1
EOF
chmod +x "$BIN/protonvpn-rotate"

# status stubs for snapshot
cat > "$BIN/omarchy-pomodoro" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "omarchy-pomodoro" "\$*" >> "$CALLS"
[ "\$1" = "status" ] && { echo '{"phase":"IDLE","streak":3}'; exit 0; }
exit 0
EOF
chmod +x "$BIN/omarchy-pomodoro"
for t in omarchy-timers omarchy-score omarchy-countdowns; do
  cat > "$BIN/$t" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$t" "\$*" >> "$CALLS"
[ "\$1" = "status" ] && { echo '{"ok":true}'; exit 0; }
exit 0
EOF
  chmod +x "$BIN/$t"
done

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "${2:-}"; fail=$((fail + 1)); }
calls() { cat "$CALLS"; }
st()  { "$CLI" get | jq -r "$1"; }

# ── a compact test ritual with all four phases ─────────────────────────
cat > "$RIT/spec.json" <<'JSON'
{
  "label": "Spec",
  "steps": [
    { "when": "start", "cli": "omarchy-pomodoro", "args": ["start"] },
    { "when": "start", "cli": "omarchy-timers",   "args": ["add", "{{label}}"] },
    { "when": "start", "cli": "omarchy-dashboard-note", "args": ["note {{date}}"], "optional": true },
    { "when": "start", "cli": "protonvpn-rotate", "args": ["connect"], "optional": true },
    { "when": "start", "cli": "omarchy-score",    "args": ["set", "0"] },
    { "when": "break", "cli": "omarchy-stopwatch", "args": ["cancel"] },
    { "when": "break", "cli": "omarchy-newsbar-refresh", "args": [] },
    { "when": "work",  "cli": "omarchy-stopwatch", "args": ["5", "check"] },
    { "when": "end",   "cli": "omarchy-timers", "args": ["clear"] },
    { "when": "end",   "cli": "omarchy-remind", "args": ["stop", "all"] }
  ]
}
JSON

cat > "$RIT/nested.json" <<'JSON'
{
  "label": "Nested",
  "steps": [
    { "when": "start", "cli": "omarchy-score", "args": ["inc"] },
    { "ritual": "spec" },
    { "when": "start", "cli": "omarchy-score", "args": ["dec"] }
  ]
}
JSON

cat > "$RIT/hardfail.json" <<'JSON'
{
  "label": "HardFail",
  "steps": [
    { "when": "start", "cli": "omarchy-score", "args": ["inc"] },
    { "when": "start", "cli": "definitely-not-installed", "args": ["x"], "optional": false },
    { "when": "start", "cli": "omarchy-timers", "args": ["clear"] }
  ]
}
JSON

# ── list ──────────────────────────────────────────────────────────────
n_rituals="$("$CLI" list | jq 'length')"
[ "$n_rituals" = "3" ] && ok "list enumerates every ritual file" || bad "list" "n=$n_rituals"
[ "$("$CLI" list | jq -r '.[] | select(.id=="spec") | .steps')" = "10" ] \
  && ok "list counts a ritual's steps" || bad "list steps"

# ── run: fires start steps in order, with token substitution ──────────
"$CLI" run spec "Ship the thing" > /dev/null
[ "$(calls | sed -n '1p')" = "omarchy-pomodoro start" ] && ok "run fires step 1 first" || bad "order 1" "$(calls | sed -n 1p)"
[ "$(calls | sed -n '2p')" = "omarchy-timers add Ship the thing" ] \
  && ok "run substitutes {{label}} into args" || bad "label subst" "$(calls | sed -n 2p)"
calls | sed -n '3p' | grep -qE "^omarchy-dashboard-note note [0-9]{4}-[0-9]{2}-[0-9]{2}$" \
  && ok "run substitutes {{date}} into args" || bad "date subst" "$(calls | sed -n 3p)"
[ "$(calls | grep -c .)" = "5" ] && ok "run fired exactly the 5 start steps" || bad "start count" "$(calls | grep -c .)"

# ── state after run ──────────────────────────────────────────────────
[ "$(st '.active')" = "true" ] && ok "run leaves the ritual active" || bad "active"
[ "$(st '.phase')" = "running" ] && ok "phase is 'running' (ritual has phased steps)" || bad "phase" "$(st .phase)"
[ "$(st '.steps[0].status')" = "ok" ] && ok "completed start step marked ok" || bad "step0" "$(st '.steps[0].status')"
[ "$(st '.steps[3].status')" = "skipped" ] \
  && ok "optional step whose CLI exits 1 is 'skipped', not fatal" || bad "opt skip" "$(st '.steps[3].status')"
[ "$(st '.steps[4].status')" = "ok" ] \
  && ok "the step after a skipped optional still runs" || bad "post-skip" "$(st '.steps[4].status')"
[ "$(st '.steps[5].status')" = "pending" ] && ok "break steps stay pending after run" || bad "break pending"

step_count="$("$CLI" status | jq -r '.step')"
[ "$step_count" = "5" ] && ok "status.step counts resolved steps" || bad "status.step" "$step_count"

# ── phase break ──────────────────────────────────────────────────────
: > "$CALLS"
"$CLI" phase break > /dev/null
[ "$(calls | sed -n '1p')" = "omarchy-stopwatch cancel" ] && ok "phase break fires break steps" || bad "break 1" "$(calls|sed -n 1p)"
[ "$(calls | grep -c .)" = "2" ] && ok "phase break fired only the 2 break steps" || bad "break count" "$(calls|grep -c .)"
[ "$(st '.steps[5].status')" = "ok" ] && ok "break step marked ok" || bad "break status"
[ "$(st '.phase')" = "break" ] && ok "state.phase tracks the current phase" || bad "phase=break" "$(st .phase)"

# ── phase work ───────────────────────────────────────────────────────
: > "$CALLS"
"$CLI" phase work > /dev/null
[ "$(calls | grep -c .)" = "1" ] && ok "phase work fires the single work step" || bad "work count"
[ "$(calls)" = "omarchy-stopwatch 5 check" ] && ok "work step args intact" || bad "work args" "$(calls)"

# ── phase end deactivates ────────────────────────────────────────────
: > "$CALLS"
"$CLI" phase end > /dev/null
[ "$(calls | sed -n '1p')" = "omarchy-timers clear" ] && ok "phase end fires end steps" || bad "end 1"
[ "$(calls | grep -c .)" = "2" ] && ok "phase end fired both end steps" || bad "end count"
[ "$(st '.active')" = "false" ] && ok "phase end goes idle" || bad "end active"
"$CLI" status | jq -e '.lastSummary | test("ok")' > /dev/null && ok "end writes a run summary" || bad "summary" "$("$CLI" status | jq -r .lastSummary)"

# ── advance: one step at a time ──────────────────────────────────────
: > "$CALLS"
"$CLI" run spec "x" > /dev/null
: > "$CALLS"
"$CLI" phase break > /dev/null   # 2 calls
: > "$CALLS"
"$CLI" advance > /dev/null
[ "$(calls | grep -c .)" = "1" ] && ok "advance runs exactly one pending step" || bad "advance count" "$(calls|grep -c .)"
"$CLI" abort > /dev/null
[ "$(st '.active')" = "false" ] && ok "abort goes idle" || bad "abort"

# ── nested rituals splice in ─────────────────────────────────────────
: > "$CALLS"
"$CLI" run nested "N" > /dev/null
[ "$(calls | sed -n '1p')" = "omarchy-score inc" ]  && ok "nested: outer step 1 runs" || bad "nest 1" "$(calls|sed -n 1p)"
[ "$(calls | sed -n '2p')" = "omarchy-pomodoro start" ] && ok "nested: spec's steps spliced in" || bad "nest 2" "$(calls|sed -n 2p)"
[ "$(calls | grep -c 'omarchy-score dec')" = "1" ] && ok "nested: outer step after the sub-ritual runs" || bad "nest tail"
"$CLI" abort > /dev/null

# ── a non-optional missing CLI is fatal to that step ────────────────
: > "$CALLS"
"$CLI" run hardfail "h" > /dev/null 2>&1
[ "$(st '.steps[0].status')" = "ok" ] && ok "hardfail: step before the bad one ran" || bad "hf 0"
[ "$(st '.steps[1].status')" = "failed" ] \
  && ok "non-optional missing CLI marks the step failed" || bad "hf 1" "$(st '.steps[1].status')"
"$CLI" abort > /dev/null

# ── snapshot ───────────────────────────────────────────────────────
snap="$("$CLI" snapshot)"
echo "$snap" | jq -e '.pomodoro.streak == 3' > /dev/null && ok "snapshot pulls each plugin's status JSON" || bad "snapshot pomodoro"
echo "$snap" | jq -e 'has("timers") and has("score") and has("countdowns") and has("vpn")' > /dev/null \
  && ok "snapshot has a slot per plugin" || bad "snapshot keys"
[ -f "$WORK/conductor-snapshot.json" ] && ok "snapshot writes conductor-snapshot.json" || bad "snapshot file"

# ── summary ─────────────────────────────────────────────────────────
echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
