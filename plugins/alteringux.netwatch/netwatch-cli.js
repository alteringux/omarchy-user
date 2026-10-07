#!/usr/bin/env node
// Thin JSON bridge between the omarchy-netwatch bash CLI and Model.js, so the
// rate/rollup engine has exactly one implementation. Reads one op from argv[2]
// and a JSON payload from stdin; writes JSON to stdout. Never throws on bad
// input — the bash side must always get usable output.
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

function nowIn(p) {
  return typeof p.now === "number" && isFinite(p.now) ? p.now : Date.now()
}

const op = process.argv[2] || ""
const p = readStdin()
let out

try {
  switch (op) {
    case "ingest": {
      // stdin: { stateRaw, sampleRaw, cur:{ts,rxBytes,txBytes,iface,up,isVpn}, config, now }
      // -> { state, sample, alerts }  ; bash writes state + sample, fires alerts.
      const state = Model.parseState(p.stateRaw)
      const prev = Model.parseSample(p.sampleRaw)
      const cfg = Model.parseConfig(p.config || {})
      out = Model.ingest(state, prev, p.cur || {}, cfg, nowIn(p))
      break
    }
    case "config":
      out = Model.parseConfig(p.config || {})
      break

    case "status":
      out = Model.status(p.stateRaw, p.config || {}, nowIn(p))
      break

    case "report":
      out = Model.report(p.stateRaw, p.range || "today", nowIn(p))
      break

    case "sparkline":
      out = Model.sparkline(p.stateRaw, typeof p.n === "number" ? p.n : 40)
      break

    default:
      process.stderr.write("netwatch-cli: unknown op '" + op + "'\n")
      process.exit(2)
  }
} catch (e) {
  process.stderr.write("netwatch-cli: " + (e && e.message ? e.message : e) + "\n")
  // Degrade to something parseable rather than aborting the bash verb.
  out = op === "ingest" ? { state: Model.defaultState(), sample: null, alerts: [] } : {}
}

process.stdout.write(JSON.stringify(out) + "\n")
