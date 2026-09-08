// Pure logic for the reposwatch plugin: tolerant parsing of the state
// ~/.local/bin/omarchy-reposwatch writes, plus the read-side formatting the
// bar glyph and panel render. No QML / Quickshell APIs so it can be reasoned
// about and unit-tested with `node --test`.

function num(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function defaultTotals() {
  return { reposScanned: 0, okRepos: 0, errorRepos: 0, dirtyRepos: 0, totalAhead: 0, totalBehind: 0 }
}

function defaultState() {
  return { version: 1, updatedAt: 0, repos: [], totals: defaultTotals() }
}

function parseRepo(r) {
  r = r || {}
  var ok = r.ok === true
  var dirty = r.dirty || {}
  return {
    path: typeof r.path === "string" ? r.path : "",
    name: typeof r.name === "string" ? r.name : "",
    ok: ok,
    error: (!ok && typeof r.error === "string") ? r.error : null,
    branch: typeof r.branch === "string" ? r.branch : "",
    detached: r.detached === true,
    dirty: {
      staged: num(dirty.staged, 0),
      unstaged: num(dirty.unstaged, 0),
      untracked: num(dirty.untracked, 0),
      total: num(dirty.total, 0)
    },
    hasUpstream: r.hasUpstream === true,
    ahead: num(r.ahead, 0),
    behind: num(r.behind, 0),
    lastCommitTs: num(r.lastCommitTs, 0)
  }
}

function parseState(raw) {
  var d = defaultState()
  if (!raw || raw.length === 0) return d
  var parsed
  try {
    parsed = typeof raw === "string" ? JSON.parse(raw) : raw
  } catch (e) {
    return d
  }
  if (!parsed || typeof parsed !== "object") return d

  var repos = Array.isArray(parsed.repos) ? parsed.repos.map(parseRepo) : []
  var t = parsed.totals || {}

  return {
    version: 1,
    updatedAt: num(parsed.updatedAt, 0),
    repos: repos,
    totals: {
      reposScanned: num(t.reposScanned, repos.length),
      okRepos: num(t.okRepos, 0),
      errorRepos: num(t.errorRepos, 0),
      dirtyRepos: num(t.dirtyRepos, 0),
      totalAhead: num(t.totalAhead, 0),
      totalBehind: num(t.totalBehind, 0)
    }
  }
}

// ── read-side status: what level should the bar glyph show? ─────────────
// "critical" only for a repo the CLI couldn't read at all (path gone, not a
// repo) — that's a config problem, not just "you have local changes".
// "warning" for anything dirty or diverged from its upstream. Otherwise calm.

function repoLevel(repo) {
  if (!repo.ok) return "critical"
  if (repo.dirty.total > 0) return "warning"
  if (repo.hasUpstream && (repo.ahead > 0 || repo.behind > 0)) return "warning"
  return "normal"
}

function overallLevel(state) {
  var repos = state.repos || []
  var level = "normal"
  for (var i = 0; i < repos.length; i++) {
    var l = repoLevel(repos[i])
    if (l === "critical") return "critical"
    if (l === "warning") level = "warning"
  }
  return level
}

// ── formatting ─────────────────────────────────────────────────────────

function formatDirty(repo) {
  if (!repo.ok) return "!"
  return repo.dirty.total > 0 ? String(repo.dirty.total) : "clean"
}

function formatAheadBehind(repo) {
  if (!repo.ok || !repo.hasUpstream) return ""
  var parts = []
  if (repo.ahead > 0) parts.push("+" + repo.ahead)
  if (repo.behind > 0) parts.push("-" + repo.behind)
  return parts.join(" ")
}

// Compact bar readout: count of dirty/errored repos, or a check when calm.
function barLabel(state) {
  var t = state.totals || defaultTotals()
  var trouble = t.dirtyRepos + t.errorRepos
  return trouble > 0 ? String(trouble) : "✓" // check mark
}

function isStale(state, nowMs, staleAfterMs) {
  if (!state || !state.updatedAt) return true
  return (nowMs - state.updatedAt) > (staleAfterMs || 15000)
}

// Exposed only for the plain-node test harness. QML's JS import has no `module`
// global, and this file is re-evaluated on every state poll, so even a `typeof
// module` guard surfaces a ReferenceError in the shell log each tick. A bare
// try/catch is the only form that stays quiet in the shell.
try {
  module.exports = {
    defaultState: defaultState,
    defaultTotals: defaultTotals,
    parseState: parseState,
    parseRepo: parseRepo,
    repoLevel: repoLevel,
    overallLevel: overallLevel,
    formatDirty: formatDirty,
    formatAheadBehind: formatAheadBehind,
    barLabel: barLabel,
    isStale: isStale
  }
} catch (e) {}
