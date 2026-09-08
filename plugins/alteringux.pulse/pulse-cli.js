#!/usr/bin/env node
// Thin JSON bridge between the omarchy-pulse bash CLI and Model.js, so the
// activity/attention engine has exactly one implementation. Reads one op from
// argv[2] and a JSON payload from stdin; writes JSON (or plain text, for
// `render`) to stdout. Never throws on bad input — the bash side must always
// get usable output.
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

function activityIn(p) {
  if (typeof p.activityRaw === "string") return Model.parseActivity(p.activityRaw, nowIn(p))
  return Model.parseActivity(p.activity || { events: [] }, nowIn(p))
}
function attentionIn(p) {
  if (typeof p.attentionRaw === "string") return Model.parseAttention(p.attentionRaw)
  return Model.parseAttention(p.attention || { items: {} })
}
function stateIn(p) {
  if (typeof p.stateRaw === "string") return Model.parseState(p.stateRaw)
  return Model.parseState(p.state || {})
}
function nowIn(p) {
  return typeof p.now === "number" && isFinite(p.now) ? p.now : Date.now()
}

const op = process.argv[2] || ""
const p = readStdin()
let out

switch (op) {
  case "make-event":
    // -> one normalised event object; bash appends JSON.stringify(it)+"\n".
    out = Model.makeEvent(p.input || {}, { now: nowIn(p), id: p.id })
    break

  case "make-attention":
    // -> the item object to store under attention.items[plugin].
    out = Model.makeAttentionItem(p.input || {}, { now: nowIn(p) })
    break

  case "prune": {
    // -> the full re-normalised, pruned event list as JSONL text.
    const a = activityIn(p)
    const lines = a.events.map((e) => JSON.stringify(e))
    process.stdout.write(lines.length ? lines.join("\n") + "\n" : "")
    process.exit(0)
    break
  }

  case "summary":
    out = Model.summary(activityIn(p), attentionIn(p), stateIn(p))
    break

  case "get":
    out = {
      activity: activityIn(p),
      attention: attentionIn(p),
      state: stateIn(p),
      attentionList: Model.attentionList(attentionIn(p)),
      summary: Model.summary(activityIn(p), attentionIn(p), stateIn(p))
    }
    break

  case "render": {
    const n = typeof p.n === "number" ? p.n : 20
    process.stdout.write(Model.formatList(activityIn(p), nowIn(p), n) + "\n")
    process.exit(0)
    break
  }

  default:
    process.stderr.write("pulse-cli: unknown op '" + op + "'\n")
    process.exit(2)
}

process.stdout.write(JSON.stringify(out) + "\n")
