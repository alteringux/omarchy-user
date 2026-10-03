"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("parseState returns the default shape for garbage input", () => {
  assert.deepEqual(Model.parseState(""), Model.defaultState())
  assert.deepEqual(Model.parseState("{not json"), Model.defaultState())
  assert.deepEqual(Model.parseState(null), Model.defaultState())
})

test("parseState is tolerant of a half-written repos/totals shape", () => {
  const r = Model.parseState(JSON.stringify({ updatedAt: 500, repos: "nope", totals: {} }))
  assert.equal(r.updatedAt, 500)
  assert.deepEqual(r.repos, [])
  assert.equal(r.totals.reposScanned, 0)
})

test("parseState keeps valid repos while surfacing malformed entries", () => {
  const r = Model.parseState(JSON.stringify({
    updatedAt: 700,
    repos: [
      { path: "/good", name: "good", ok: true },
      null,
      { path: "/bad", name: "bad", ok: true, dirty: "not an object" }
    ],
    totals: { reposScanned: 0, okRepos: 3, errorRepos: 0 }
  }))
  assert.equal(r.repos.length, 3)
  assert.equal(r.repos[0].ok, true)
  assert.equal(r.repos[1].name, "Invalid repository")
  assert.equal(r.repos[1].error, "invalid repository data")
  assert.equal(r.repos[2].error, "invalid repository data")
  assert.equal(r.totals.reposScanned, 3)
  assert.equal(r.totals.okRepos, 1)
  assert.equal(r.totals.errorRepos, 2)
  assert.equal(Model.barLabel(r), "2")
  assert.equal(Model.overallLevel(r), "critical")
})

test("parseRepo defaults a missing dirty/ahead/behind shape", () => {
  const r = Model.parseRepo({ path: "/x", name: "x", ok: true })
  assert.deepEqual(r.dirty, { staged: 0, unstaged: 0, untracked: 0, total: 0 })
  assert.equal(r.ahead, 0)
  assert.equal(r.behind, 0)
  assert.equal(r.error, null)
})

test("parseRepo keeps the error only when ok is false", () => {
  const okRepo = Model.parseRepo({ ok: true, error: "should be dropped" })
  assert.equal(okRepo.error, null)
  const badRepo = Model.parseRepo({ ok: false, error: "not a git repository" })
  assert.equal(badRepo.error, "not a git repository")
})

test("repoLevel: critical for an unreadable repo, warning for dirty or diverged, normal otherwise", () => {
  const broken = Model.parseRepo({ ok: false, error: "boom" })
  assert.equal(Model.repoLevel(broken), "critical")

  const dirty = Model.parseRepo({ ok: true, dirty: { total: 2 } })
  assert.equal(Model.repoLevel(dirty), "warning")

  const behind = Model.parseRepo({ ok: true, hasUpstream: true, ahead: 0, behind: 3 })
  assert.equal(Model.repoLevel(behind), "warning")

  const clean = Model.parseRepo({ ok: true, hasUpstream: true, ahead: 0, behind: 0 })
  assert.equal(Model.repoLevel(clean), "normal")
})

test("overallLevel escalates to critical if any repo is unreadable, else warning if any is dirty", () => {
  const clean = Model.parseRepo({ ok: true })
  const dirty = Model.parseRepo({ ok: true, dirty: { total: 1 } })
  const broken = Model.parseRepo({ ok: false })

  assert.equal(Model.overallLevel({ repos: [clean] }), "normal")
  assert.equal(Model.overallLevel({ repos: [clean, dirty] }), "warning")
  assert.equal(Model.overallLevel({ repos: [clean, dirty, broken] }), "critical")
  assert.equal(Model.overallLevel({ repos: [] }), "normal")
})

test("formatDirty shows a count, 'clean', or '!' for an error", () => {
  assert.equal(Model.formatDirty(Model.parseRepo({ ok: true, dirty: { total: 0 } })), "clean")
  assert.equal(Model.formatDirty(Model.parseRepo({ ok: true, dirty: { total: 4 } })), "4")
  assert.equal(Model.formatDirty(Model.parseRepo({ ok: false })), "!")
})

test("formatAheadBehind renders +ahead/-behind, blank with no upstream or no divergence", () => {
  assert.equal(Model.formatAheadBehind(Model.parseRepo({ ok: true, hasUpstream: false })), "")
  assert.equal(Model.formatAheadBehind(Model.parseRepo({ ok: true, hasUpstream: true, ahead: 0, behind: 0 })), "")
  assert.equal(Model.formatAheadBehind(Model.parseRepo({ ok: true, hasUpstream: true, ahead: 2, behind: 0 })), "+2")
  assert.equal(Model.formatAheadBehind(Model.parseRepo({ ok: true, hasUpstream: true, ahead: 0, behind: 5 })), "-5")
  assert.equal(Model.formatAheadBehind(Model.parseRepo({ ok: true, hasUpstream: true, ahead: 1, behind: 3 })), "+1 -3")
})

test("barLabel shows trouble count (dirty + error repos), a check mark when calm", () => {
  assert.equal(Model.barLabel({ totals: { dirtyRepos: 0, errorRepos: 0 } }), "✓")
  assert.equal(Model.barLabel({ totals: { dirtyRepos: 2, errorRepos: 1 } }), "3")
})

test("isStale compares updatedAt against now", () => {
  assert.equal(Model.isStale(Model.defaultState(), Date.now()), true) // updatedAt: 0
  assert.equal(Model.isStale({ updatedAt: 1000 }, 1000, 15000), false)
  assert.equal(Model.isStale({ updatedAt: 1000 }, 20000, 15000), true)
})
