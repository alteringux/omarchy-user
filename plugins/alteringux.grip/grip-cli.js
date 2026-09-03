#!/usr/bin/env node
// Thin JSON bridge between the omarchy-grip bash CLI/daemon and Model.js, so the
// intrusion engine has exactly one implementation. Reads one op from argv[2] and
// a JSON payload from stdin; writes a JSON (or plain-text, for `render`) result
// to stdout. Never throws on bad input — the bash side must always get usable
// output.
"use strict"

const Model = require("./Model.js")

function readStdin() {
  try {
    const raw = require("fs").readFileSync(0, "utf8")
    return raw && raw.trim() ? JSON.parse(raw) : {}
  } catch (e) {
    return {}
  }
}

// Every reader runs the value back through Model.parse*, so the engine sees a
// total, clamped, normalised shape whether the bash side handed us the parsed
// object or a raw (possibly hand-mangled) file string.
function tasksIn(p) {
  if (typeof p.tasksRaw === "string") return Model.parseTasks(p.tasksRaw)
  if (Array.isArray(p.tasks)) return Model.parseTasks(JSON.stringify({ tasks: p.tasks }))
  if (p.tasks !== undefined) return Model.parseTasks(JSON.stringify(p.tasks))
  return Model.defaultTasks()
}
function configIn(p) {
  if (typeof p.configRaw === "string") return Model.parseConfig(p.configRaw)
  return Model.parseConfig(JSON.stringify(p.config || {}))
}
function stateIn(p) {
  if (typeof p.stateRaw === "string") return Model.parseState(p.stateRaw)
  return Model.parseState(JSON.stringify(p.state || {}))
}
function nowIn(p) {
  return typeof p.now === "number" && isFinite(p.now) ? p.now : Date.now()
}

const op = process.argv[2] || ""
const p = readStdin()
let out

switch (op) {
  case "decide": {
    const d = Model.decide(configIn(p), stateIn(p), tasksIn(p), nowIn(p))
    out = { prompt: d.prompt, reason: d.reason, nextIntervalMs: d.nextIntervalMs }
    break
  }
  case "summary":
    out = Model.summary(tasksIn(p), stateIn(p), nowIn(p))
    break
  case "top": {
    const n = typeof p.n === "number" ? p.n : 3
    out = Model.topTasks(tasksIn(p), nowIn(p), n)
    break
  }
  case "sync-routines":
    out = Model.syncRoutines(tasksIn(p), configIn(p), p.day || "")
    break
  case "add":
    out = Model.addTask(tasksIn(p), p.input || {}, { id: p.id, now: nowIn(p) })
    break
  case "complete":
    out = Model.completeTask(tasksIn(p), String(p.id))
    break
  case "drop":
    out = Model.dropTask(tasksIn(p), String(p.id))
    break
  case "render": {
    // Human-readable task list for `omarchy-grip list`.
    const now = nowIn(p)
    const rows = Model.topTasks(tasksIn(p), now, 999)
    if (rows.length === 0) {
      process.stdout.write("Nothing open. Wall is clear.\n")
      process.exit(0)
    }
    const lines = rows.map((t) => {
      const flag = t.hard ? "!" : " "
      const due = t.due != null ? "  (" + Model.formatDue(t.due - now, now) + ")" : ""
      const tag = t.source !== "typed" ? "  [" + t.source + "]" : ""
      return flag + " " + t.id.padEnd(10).slice(0, 10) + "  " + t.text + due + tag
    })
    process.stdout.write(lines.join("\n") + "\n")
    process.exit(0)
  }
  default:
    process.stderr.write("grip-cli: unknown op '" + op + "'\n")
    process.exit(2)
}

process.stdout.write(JSON.stringify(out) + "\n")
