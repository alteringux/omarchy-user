#!/usr/bin/env bash
# Black-box tests for ~/.local/bin/omarchy-reposwatch — the CLI that owns
# reposwatch-state.json (docs/adr/0006-cli-first-plugins.md).
#
#   bash test/cli.test.sh
#
# Drives the CLI against real throwaway git repos under a tmpdir (git status
# porcelain output is cheap and exact to fake correctly by hand, so a real
# repo is simpler and more trustworthy than a fixture string). $HOME is also
# pointed at the tmpdir so the config-seeding default (~/.config/omarchy,
# ~/Work) can't pick up whatever the machine running this happens to have.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CLI="${OMARCHY_REPOSWATCH_BIN:-$REPO/local-bin/omarchy-reposwatch}"
[ -x "$CLI" ] || { echo "not executable: $CLI" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export OMARCHY_STATE_DIR="$WORK/state"
export HOME="$WORK/home"
mkdir -p "$OMARCHY_STATE_DIR" "$HOME"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

pass=0 fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }

state() { jq -r "$1" "$OMARCHY_STATE_DIR/reposwatch-state.json"; }
repo_of() { jq -r --arg n "$1" '.repos[] | select(.name == $n) | '"$2" "$OMARCHY_STATE_DIR/reposwatch-state.json"; }

git_init() { # git_init <dir>
  mkdir -p "$1"
  git -C "$1" init -q -b main
}
commit() { # commit <dir> <message>
  git -C "$1" commit -q --allow-empty -m "$2"
}

# ── config seeding: empty repos when $HOME has neither known path ────────
"$CLI" config >/dev/null
[ -f "$OMARCHY_STATE_DIR/reposwatch-config.json" ] && ok "any verb seeds reposwatch-config.json" \
  || bad "config seed" "missing"
[ "$(jq -c '.repos' "$OMARCHY_STATE_DIR/reposwatch-config.json")" = "[]" ] \
  && ok "seeded config starts empty when \$HOME has no .config/omarchy or Work" \
  || bad "config default" "$(cat "$OMARCHY_STATE_DIR/reposwatch-config.json")"

# ── add a clean repo ───────────────────────────────────────────────────────
git_init "$WORK/clean"
commit "$WORK/clean" "init"
"$CLI" add "$WORK/clean" >/dev/null
[ "$(repo_of clean .ok)" = "true" ] && ok "add + scan reports ok:true for a real repo" \
  || bad "clean repo ok" "$(repo_of clean .)"
[ "$(repo_of clean .dirty.total)" = "0" ] && ok "a freshly committed repo is not dirty" \
  || bad "clean dirty.total" "$(repo_of clean .dirty)"
[ "$(repo_of clean .branch)" = "main" ] && ok "branch name is read correctly" \
  || bad "clean branch" "$(repo_of clean .branch)"

# ── a dirty repo: staged + unstaged + untracked counted separately ────────
git_init "$WORK/dirty"
echo a > "$WORK/dirty/a.txt"
git -C "$WORK/dirty" add a.txt
commit "$WORK/dirty" "init"
echo b >> "$WORK/dirty/a.txt"                 # unstaged modification
echo new > "$WORK/dirty/untracked.txt"        # untracked
echo c > "$WORK/dirty/staged.txt"
git -C "$WORK/dirty" add staged.txt            # staged addition
"$CLI" add "$WORK/dirty" >/dev/null

[ "$(repo_of dirty .dirty.staged)" = "1" ] && ok "dirty.staged counts the staged addition" \
  || bad "dirty.staged" "$(repo_of dirty .dirty)"
[ "$(repo_of dirty .dirty.unstaged)" = "1" ] && ok "dirty.unstaged counts the unstaged modification" \
  || bad "dirty.unstaged" "$(repo_of dirty .dirty)"
[ "$(repo_of dirty .dirty.untracked)" = "1" ] && ok "dirty.untracked counts the untracked file" \
  || bad "dirty.untracked" "$(repo_of dirty .dirty)"
[ "$(repo_of dirty .dirty.total)" = "3" ] && ok "dirty.total sums all three" \
  || bad "dirty.total" "$(repo_of dirty .dirty)"

# ── ahead/behind against a real upstream ──────────────────────────────────
git init -q --bare "$WORK/remote.git"
git_init "$WORK/tracked"
commit "$WORK/tracked" "init"
git -C "$WORK/tracked" remote add origin "$WORK/remote.git"
git -C "$WORK/tracked" push -q -u origin main
commit "$WORK/tracked" "local work"            # 1 ahead

git clone -q "$WORK/remote.git" "$WORK/other" >/dev/null 2>&1
git -C "$WORK/other" checkout -q -b main origin/main
commit "$WORK/other" "remote-side work"
commit "$WORK/other" "more remote-side work"
git -C "$WORK/other" push -q origin main       # remote now 2 commits past what "tracked" has

git -C "$WORK/tracked" fetch -q origin
"$CLI" add "$WORK/tracked" >/dev/null

[ "$(repo_of tracked .hasUpstream)" = "true" ] && ok "hasUpstream is true once a remote branch is set" \
  || bad "hasUpstream" "$(repo_of tracked .hasUpstream)"
[ "$(repo_of tracked .ahead)" = "1" ] && ok "ahead counts the one local-only commit" \
  || bad "ahead" "$(repo_of tracked .ahead)"
[ "$(repo_of tracked .behind)" = "2" ] && ok "behind counts the two upstream-only commits" \
  || bad "behind" "$(repo_of tracked .behind)"

# ── a path that isn't a repo ──────────────────────────────────────────────
mkdir -p "$WORK/notarepo"
"$CLI" add "$WORK/notarepo" >/dev/null
[ "$(repo_of notarepo .ok)" = "false" ] && ok "a non-repo path reports ok:false" \
  || bad "notarepo ok" "$(repo_of notarepo .)"
[ "$(repo_of notarepo .error)" = "not a git repository" ] && ok "non-repo carries a clear error" \
  || bad "notarepo error" "$(repo_of notarepo .error)"


# ── totals aggregate across the whole watch list ──────────────────────────
scanned="$(state '.totals.reposScanned')"
[ "$scanned" = "4" ] && ok "totals.reposScanned counts every watched path" || bad "reposScanned" "$scanned"
[ "$(state '.totals.dirtyRepos')" = "1" ] && ok "totals.dirtyRepos counts only the dirty one" \
  || bad "dirtyRepos" "$(state '.totals.dirtyRepos')"
[ "$(state '.totals.errorRepos')" = "1" ] && ok "totals.errorRepos counts the non-repo path" \
  || bad "errorRepos" "$(state '.totals.errorRepos')"
[ "$(state '.totals.totalAhead')" = "1" ] && ok "totals.totalAhead sums ahead across repos" \
  || bad "totalAhead" "$(state '.totals.totalAhead')"
[ "$(state '.totals.totalBehind')" = "2" ] && ok "totals.totalBehind sums behind across repos" \
  || bad "totalBehind" "$(state '.totals.totalBehind')"

# ── remove drops a repo from the watch list ───────────────────────────────
"$CLI" remove "$WORK/notarepo" >/dev/null
[ "$(state '.repos | length')" = "3" ] && ok "remove drops the repo and re-scans" \
  || bad "after remove count" "$(state '.repos | length')"

# ── get seeds state if missing ─────────────────────────────────────────────
rm -f "$OMARCHY_STATE_DIR/reposwatch-state.json"
"$CLI" get >/dev/null
[ -f "$OMARCHY_STATE_DIR/reposwatch-state.json" ] && ok "get seeds state when missing" \
  || bad "get seeds state" "missing"

# ── reset wipes state but keeps config ─────────────────────────────────────
"$CLI" reset >/dev/null
[ -f "$OMARCHY_STATE_DIR/reposwatch-config.json" ] && ok "reset keeps config" || bad "reset kept config" "config missing"
# ── a polling failure is an error, not a false clean result ────────────────
git_init "$WORK/broken"
commit "$WORK/broken" "init"
printf 'not a git index\n' > "$WORK/broken/.git/index"
"$CLI" add "$WORK/broken" >/dev/null
[ "$(repo_of broken .ok)" = "false" ] && ok "git status failure reports ok:false" \
  || bad "git status failure ok" "$(repo_of broken .)"
[ "$(repo_of broken .error)" = "git status failed" ] && ok "polling failure carries a visible error" \
  || bad "git status failure error" "$(repo_of broken .error)"
[ "$(repo_of clean .ok)" = "true" ] && ok "a failed repo does not discard valid repo entries" \
  || bad "valid repo after failure" "$(repo_of clean .)"

# ── malformed config entries stay visible without dropping valid paths ─────
jq -n --arg p "$WORK/clean" '{repos: [$p, 42]}' > "$OMARCHY_STATE_DIR/reposwatch-config.json"
"$CLI" scan >/dev/null
[ "$(repo_of clean .ok)" = "true" ] && ok "valid config entry survives malformed sibling" \
  || bad "valid entry after malformed config" "$(repo_of clean .)"
[ "$(state '.totals.errorRepos')" = "1" ] && ok "malformed config entry is a visible error" \
  || bad "malformed config error count" "$(state '.totals.errorRepos')"

printf '{broken\n' > "$OMARCHY_STATE_DIR/reposwatch-config.json"
"$CLI" scan >/dev/null
[ "$(repo_of clean .ok)" = "true" ] && ok "valid state entry survives invalid config" \
  || bad "valid entry after invalid config" "$(repo_of clean .)"
[ "$(state '.totals.errorRepos')" = "1" ] && ok "invalid config is a visible error" \
  || bad "invalid config error count" "$(state '.totals.errorRepos')"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
