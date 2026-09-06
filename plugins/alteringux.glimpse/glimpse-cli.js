#!/usr/bin/env node
// Thin JSON bridge between the omarchy-glimpse bash CLI/daemon and Model.js,
// so the round mechanics + scheduling engine have exactly one implementation.
// Reads one op from argv[2] and a JSON payload from stdin; writes a JSON
// result to stdout. Never throws on bad input — the bash side must always get
// usable output.
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

function cardsIn(p) {
  if (typeof p.cardsRaw === "string") return Model.parseCards(p.cardsRaw)
  return Model.parseCards(JSON.stringify({ cards: p.cards || [] }))
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
    out = Model.decide(configIn(p), stateIn(p), cardsIn(p).cards, nowIn(p))
    break
  }
  case "roll-daily": {
    out = Model.rollDaily(stateIn(p), nowIn(p))
    break
  }
  case "level-params": {
    out = Model.levelParams(typeof p.level === "number" ? p.level : 3, configIn(p))
    break
  }
  case "next-level": {
    out = { level: Model.nextLevel(typeof p.level === "number" ? p.level : 3, String(p.grade || "good")) }
    break
  }
  case "start-round": {
    const cfg = configIn(p)
    out = Model.startRound(p.spec || {}, String(p.sessionType || "drill"),
      typeof p.level === "number" ? p.level : 3, cfg, nowIn(p))
    break
  }
  case "score": {
    // p.truth + p.clicks (normalised). Returns hits / accuracy / grade / per-click.
    out = Model.scoreHits(Array.isArray(p.truth) ? p.truth : [], Array.isArray(p.clicks) ? p.clicks : [])
    break
  }
  case "grade": {
    const acc = typeof p.accuracy === "number" ? p.accuracy : undefined
    out = { cards: Model.gradeCard(cardsIn(p).cards, String(p.id), String(p.grade), nowIn(p), acc) }
    break
  }
  case "add-card": {
    const round = Model.parseRound(p.round)
    if (!round) { out = { cards: cardsIn(p).cards, id: null }; break }
    out = Model.addCardFromRound(cardsIn(p).cards, round, nowIn(p), { id: p.id })
    break
  }
  case "drop": {
    out = { cards: Model.dropCard(cardsIn(p).cards, String(p.id)) }
    break
  }
  case "due-ids": {
    out = { ids: Model.dueCards(cardsIn(p).cards, nowIn(p)).map((c) => c.id) }
    break
  }
  case "card": {
    out = Model.findCard(cardsIn(p).cards, String(p.id)) || null
    break
  }
  case "stats": {
    out = Model.stats(cardsIn(p).cards, stateIn(p), nowIn(p))
    break
  }
  default:
    process.stderr.write("glimpse-cli: unknown op '" + op + "'\n")
    process.exit(2)
}

process.stdout.write(JSON.stringify(out) + "\n")
