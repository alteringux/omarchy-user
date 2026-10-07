#!/usr/bin/env node
// Thin JSON bridge between the omarchy-phone bash daemon and Model.js, so the
// persona/cadence/parsing logic has exactly one implementation. Reads one op
// from argv[2] and a JSON payload from stdin; writes a JSON (or plain-text,
// for the *-prompt ops) result to stdout. Never throws on bad input — the
// bash side must always get usable output.
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

const op = process.argv[2] || ""
const p = readStdin()
let out
let plain = null

switch (op) {
  // ---- prompts (plain text on stdout) --------------------------------
  case "system-prompt":
    plain = Model.assembleSystemPrompt(
      Model.parseContact(typeof p.contactRaw === "string" ? p.contactRaw : JSON.stringify(p.contact || {})),
      typeof p.memory === "string" ? p.memory : "",
      { extra: typeof p.extra === "string" ? p.extra : "" }
    )
    break
  case "greeting-instruction":
    plain = Model.buildGreetingInstruction(
      Model.parseContact(typeof p.contactRaw === "string" ? p.contactRaw : JSON.stringify(p.contact || {})),
      p.direction === "inbound" ? "inbound" : "outbound"
    )
    break
  case "memory-prompt":
    plain = Model.buildMemoryPrompt(
      typeof p.memory === "string" ? p.memory : "",
      typeof p.contactName === "string" ? p.contactName : "",
      typeof p.maxChars === "number" ? p.maxChars : 1800
    )
    break

  // ---- decisions / parsing (JSON on stdout) --------------------------
  case "inbound-decide": {
    const cfg = Model.parseConfig(typeof p.configRaw === "string" ? p.configRaw : JSON.stringify(p.config || {}))
    const contact = Model.parseContact(typeof p.contactRaw === "string" ? p.contactRaw : JSON.stringify(p.contact || {}))
    const now = p.nowMs ? new Date(p.nowMs) : new Date()
    const gate = Model.shouldOfferInbound(cfg, contact, now, p.todayCount || 0)
    let fire = false
    let prob = 0
    if (gate.ok) {
      prob = Model.inboundTickProbability(contact.frequency, p.tickSeconds || 60)
      const rnd = (typeof p.rnd === "number") ? p.rnd : Math.random()
      fire = rnd < prob
    }
    out = { ok: gate.ok, why: gate.why, probability: prob, fire: fire }
    break
  }
  case "clean-whisper":
    out = { text: Model.cleanWhisperText(typeof p.text === "string" ? p.text : "") }
    break
  case "clean-reply":
    out = { text: Model.cleanReplyText(typeof p.text === "string" ? p.text : "") }
    break
  case "parse-searx":
    out = { results: Model.parseSearxResults(typeof p.json === "string" ? p.json : "", p.n || 5) }
    break
  case "tool-specs":
    out = { tools: Model.toolSpecs() }
    break
  case "tool-label":
    out = { label: Model.toolLabelFor(String(p.name || "")) }
    break
  case "merge-contact":
    out = Model.mergeContact(
      Model.parseContact(typeof p.baseRaw === "string" ? p.baseRaw : JSON.stringify(p.base || Model.defaultContact())),
      p.patch || {}
    )
    break
  case "default-contact":
    out = Model.defaultContact()
    break
  case "validate-contact":
    out = { errors: Model.validateContact(p.contact || {}) }
    break
  case "slugify":
    out = { slug: Model.slugify(String(p.text || "")) }
    break
  case "parse-voice-list":
    out = { voices: Model.parseVoiceList(typeof p.raw === "string" ? p.raw : "") }
    break
  case "default-config":
    out = Model.defaultConfig()
    break

  default:
    process.stderr.write("phone-cli: unknown op '" + op + "'\n")
    process.exit(2)
}

if (plain !== null) {
  process.stdout.write(plain + "\n")
} else {
  process.stdout.write(JSON.stringify(out) + "\n")
}
