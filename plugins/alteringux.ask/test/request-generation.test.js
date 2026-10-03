"use strict"

const assert = require("node:assert/strict")
const G = require("../RequestGeneration.js")

const state = G.create()
const first = G.begin(state)
G.activate(state, first)
G.markOutput(state, first)
G.markExited(state, first)
assert.equal(G.accepts(state, first), true)

const second = G.begin(state)
G.queue(state, second)
assert.equal(G.accepts(state, second), false)
// Late signals from the stopped first process must not apply to the queued turn.
G.markOutput(state, first)
G.markExited(state, first)
assert.equal(G.takePending(state), second)
assert.equal(state.active, second)
assert.equal(G.accepts(state, first), false)
assert.equal(G.accepts(state, second), true)

const third = G.begin(state)
G.queue(state, third)
G.cancel(state)
G.markOutput(state, second)
G.markExited(state, second)
assert.equal(G.takePending(state), 0)
assert.equal(G.accepts(state, second), false)

console.log("ok - stale Ask responses are rejected by generation")
