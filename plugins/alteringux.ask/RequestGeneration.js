// RequestGeneration keeps the process generation separate from the latest
// requested generation. A stopped Process can still deliver queued stdout and
// exit signals; those signals must retain the old generation until both arrive.

function create() {
  return { next: 0, active: 0, pending: 0, output: 0, exited: 0 }
}

function begin(state) {
  state.next += 1
  return state.next
}

function cancel(state) {
  state.next += 1
  state.pending = 0
  return state.next
}

function activate(state, serial) {
  state.active = serial
  state.output = 0
  state.exited = 0
}

function queue(state, serial) {
  state.pending = serial
}

function markOutput(state, serial) {
  state.output = serial
}

function markExited(state, serial) {
  state.exited = serial
}

function accepts(state, serial) {
  return serial > 0 && state.next === serial && state.active === serial
}

function takePending(state) {
  if (!state.pending || state.pending !== state.next ||
      state.output !== state.active || state.exited !== state.active)
    return 0
  var serial = state.pending
  state.pending = 0
  activate(state, serial)
  return serial
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    create: create,
    begin: begin,
    cancel: cancel,
    activate: activate,
    queue: queue,
    markOutput: markOutput,
    markExited: markExited,
    accepts: accepts,
    takePending: takePending
  }
}
