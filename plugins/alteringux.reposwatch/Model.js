// Pure logic for the reposwatch plugin: tolerant parsing of the state
// ~/.local/bin/omarchy-reposwatch writes, plus the read-side formatting the
// bar glyph and panel render. No QML / Quickshell APIs so it can be reasoned
// about and unit-tested with `node --test`.

function num(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function validNum(value) {
  return value === undefined || value === null || (typeof value === "number" && isFinite(value))
}

function defaultTotals() {
  return { reposScanned: 0, okRepos: 0, errorRepos: 0, dirtyRepos: 0, totalAhead: 0, totalBehind: 0 }
}

function defaultState() {
  return { version: 1, updatedAt: 0, repos: [], totals: defaultTotals() }
}

function parseRepo(r) {
  var source = r && typeof r === "object" && !Array.isArray(r) ? r : {}
  var malformed = source !== r
  var dirty = source.dirty
  if (dirty !== undefined && (!dirty || typeof dirty !== "object" || Array.isArray(dirty))) malformed = true
  if (source.ok !== undefined && typeof source.ok !== "boolean") malformed = true
  if (source.path !== undefined && typeof source.path !== "string") malformed = true
  if (source.name !== undefined && typeof source.name !== "string") malformed = true
  if (source.error !== undefined && source.error !== null && typeof source.error !== "string") malformed = true
  if (source.branch !== undefined && typeof source.branch !== "string") malformed = true
  if (source.detached !== undefined && typeof source.detached !== "boolean") malformed = true
  if (source.hasUpstream !== undefined && typeof source.hasUpstream !== "boolean") malformed = true
  if (source.dirty && (
    !validNum(source.dirty.staged) ||
    !validNum(source.dirty.unstaged) ||
    !validNum(source.dirty.untracked) ||
    !validNum(source.dirty.total)
  )) malformed = true
  if (!validNum(source.ahead) || !validNum(source.behind) || !validNum(source.lastCommitTs)) malformed = true

  var ok = !malformed && source.ok === true
  return {
    path: typeof source.path === "string" ? source.path : "",
    name: typeof source.name === "string" ? source.name : (malformed ? "Invalid repository" : ""),
    ok: ok,
    error: malformed ? "invalid repository data" : (!ok && typeof source.error === "string" ? source.error : null),
    branch: typeof source.branch === "string" ? source.branch : "",
    detached: source.detached === true,
    dirty: {
      staged: num(source.dirty && source.dirty.staged, 0),
      unstaged: num(source.dirty && source.dirty.unstaged, 0),
      untracked: num(source.dirty && source.dirty.untracked, 0),
      total: num(source.dirty && source.dirty.total, 0)
    },
    hasUpstream: source.hasUpstream === true,
    ahead: num(source.ahead, 0),
    behind: num(source.behind, 0),
    lastCommitTs: num(source.lastCommitTs, 0)
  }
}

function totalsFor(repos) {
  var totals = defaultTotals()
  totals.reposScanned = repos.length
  for (var i = 0; i < repos.length; i++) {
    var repo = repos[i]
    if (!repo.ok) {
      totals.errorRepos++
      continue
    }
    totals.okRepos++
    if (repo.dirty.total > 0) totals.dirtyRepos++
    totals.totalAhead += Math.max(0, repo.ahead)
    totals.totalBehind += Math.max(0, repo.behind)
  }
  return totals
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

  return {
    version: 1,
    updatedAt: num(parsed.updatedAt, 0),
    repos: repos,
    totals: totalsFor(repos)
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
