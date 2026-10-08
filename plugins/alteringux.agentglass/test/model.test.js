import test from "node:test"
import assert from "node:assert/strict"
import vm from "node:vm"
import { readFileSync } from "node:fs"

const module = { exports: {} }
vm.runInNewContext(readFileSync(new URL("../Model.js", import.meta.url), "utf8"), { module, isFinite })
const Model = module.exports

test("malformed and empty state are safe", () => {
  assert.equal(Model.parseState("").reachable, false)
  assert.equal(Model.parseState("not json").counts.total, 0)
})

test("healthy state is bounded and formatted", () => {
  const state = Model.parseState(JSON.stringify({
    reachable: true,
    stale: false,
    updatedAt: Date.now(),
    counts: { total: 4, working: 2, waiting: 1 },
    projectCount: 140,
    agents: Array.from({ length: 20 }, (_, i) => ({ name: String(i) }))
  }))
  assert.equal(state.counts.total, 4)
  assert.equal(state.counts.working, 2)
  assert.equal(state.counts.waiting, 1)
  assert.equal(state.projectCount, 140)
  assert.equal(state.agents.length, 12)
  assert.equal(Model.barLabel(state), "2/1")
  assert.equal(Model.ageLabel(1000, 61000), "1m ago")
})

test("missing fields retain native defaults", () => {
  const state = Model.parseState(JSON.stringify({ reachable: true, counts: { working: "bad" } }))
  assert.equal(state.workspace, "")
  assert.equal(state.counts.total, 0)
  assert.equal(Model.barLabel(state), "!")
})

test("an overdue successful cache is stale and keeps its last counts", () => {
  const state = Model.parseState({ reachable: true, stale: false, updatedAt: Date.now() - 31000, counts: { working: 3 } })
  assert.equal(state.stale, true)
  assert.equal(state.counts.working, 3)
  assert.equal(Model.barLabel(state), "!")
})

test("unchanged cache ages on the UI clock without being parsed again", () => {
  const state = Model.parseState({ reachable: true, stale: false, updatedAt: Date.now(), counts: { working: 2 } })
  assert.equal(Model.isStale(state, state.updatedAt + 1000), false)
  assert.equal(Model.isStale(state, state.updatedAt + 31000), true)
  assert.equal(Model.barLabel(state, state.updatedAt + 31000), "!")
})

test("resource rows show sampled CPU and RSS without implying ownership", () => {
  assert.equal(Model.resourceLabel({ pid: 42, ppid: 1, comm: "bun", cpu: 12.34, rss: 1048576 }),
    "42 ← 1 · bun · CPU 12.3% · RSS 1 MiB")
  assert.match(Model.resourceLabel({ pid: 43, ppid: 1, comm: "node", cpu: null, rss: null }), /CPU sampling · RSS 0 MiB$/)
  assert.equal(Model.pathLabel("/home/example/code/orbit", "/home/example"), "in ~/code/orbit")
  assert.equal(Model.pathLabel(null, "/home/example"), "working directory unknown")
})

test("listening service labels make exposure and ancestry signals visible", () => {
  assert.equal(Model.serviceLabel({ port: 3000, proc: "node", pid: 42, addr: "0.0.0.0", publicBind: true, fromAgent: true }),
    ":3000 · node · pid 42 · 0.0.0.0 · PUBLIC · agent ancestry")
  assert.equal(Model.parseState({ services: { listening: 1, services: [{ port: 80 }] } }).services.listening, 1)
  assert.equal(Model.userServiceLabel({ unit: "pipewire.service", active: "active", sub: "running", description: "PipeWire" }),
    "pipewire.service · active/running · PipeWire")
})

test("installed agent kinds survive in the native status cache", () => {
  const state = Model.parseState({ agentKinds: [{ id: "codex", title: "Codex" }, { id: "claude", title: "Claude Code" }] })
  assert.deepEqual(JSON.parse(JSON.stringify(state.agentKinds)), [{ id: "codex", title: "Codex" }, { id: "claude", title: "Claude Code" }])
})

test("managed workflow rows carry per-unit state and cgroup accounting", () => {
  const state = Model.parseState({ managedRuns: [
    { unit: "agentglass-run-build-abcd1234567890abcdef1234567890ab.service", name: "Agentglass workflow: nightly build", active: "active", sub: "running", cpuUsageNs: 1500000000, memoryCurrent: 1048576, memoryPeak: 2097152 }
  ] })
  assert.equal(state.managedRuns.length, 1)
  assert.equal(Model.managedRunLabel(state.managedRuns[0]), "nightly build · active/running · 1.5s CPU · 1/2 MiB current/peak")
})
