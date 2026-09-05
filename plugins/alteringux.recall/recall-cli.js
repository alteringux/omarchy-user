#!/usr/bin/env node
// Thin JSON bridge between the omarchy-recall bash CLI/daemon and Model.js,
// so the scheduling + intrusion engine has exactly one implementation. Reads
// one op from argv[2] and a JSON payload from stdin; writes a JSON (or
// plain-text, for `render`) result to stdout. Never throws on bad input —
// the bash side must always get usable output.
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
    const now = nowIn(p)
    const d = Model.decide(configIn(p), stateIn(p), cardsIn(p).cards, now)
    out = d
    break
  }
  case "top": {
    const now = nowIn(p)
    const n = typeof p.n === "number" ? p.n : 999
    out = Model.topDue(cardsIn(p).cards, now, n)
    break
  }
  case "stats": {
    const now = nowIn(p)
    const cards = cardsIn(p).cards
    const s = Model.stats(cards, stateIn(p))
    s.dueCount = Model.dueQuizzes(cards, now).length
    out = s
    break
  }
  case "seed": {
    const now = nowIn(p)
    const cards = Model.defaultCards().cards.map((c) => { c.createdAt = now; return c })
    out = { cards: cards }
    break
  }
  case "add-quiz":
    out = Model.addQuizCard(cardsIn(p).cards, p.input || {}, { id: p.id, now: nowIn(p) })
    break
  case "add-quiz-batch": {
    const now = nowIn(p)
    let cards = cardsIn(p).cards
    const items = Array.isArray(p.items) ? p.items : []
    const ids = []
    items.forEach((item, i) => {
      const r = Model.addQuizCard(cards, item, { id: p.idPrefix ? p.idPrefix + i : undefined, now: now + i })
      cards = r.cards
      ids.push(r.id)
    })
    out = { cards: cards, ids: ids }
    break
  }
  case "add-lesson":
    out = Model.addLessonCard(cardsIn(p).cards, p.input || {}, { id: p.id, now: nowIn(p) })
    break
  case "drop":
    out = { cards: Model.dropCard(cardsIn(p).cards, String(p.id)) }
    break
  case "grade":
    out = { cards: Model.gradeCard(cardsIn(p).cards, String(p.id), String(p.grade), nowIn(p)) }
    break
  case "lesson-seen":
    out = { cards: Model.markLessonSeen(cardsIn(p).cards, String(p.id), nowIn(p)) }
    break
  case "roll-daily":
    out = Model.rollDaily(stateIn(p), nowIn(p))
    break
  case "render": {
    // Human-readable due queue for `omarchy-recall list`.
    const now = nowIn(p)
    const rows = Model.topDue(cardsIn(p).cards, now, 999)
    if (rows.length === 0) {
      process.stdout.write("Nothing due. Deck is caught up.\n")
      process.exit(0)
    }
    const lines = rows.map((c) => {
      const due = "  (" + Model.formatDue(c.dueAt - now, now) + ")"
      const tag = "  [" + c.category + "]"
      return c.id.padEnd(12).slice(0, 12) + "  " + c.front + due + tag
    })
    process.stdout.write(lines.join("\n") + "\n")
    process.exit(0)
  }
  default:
    process.stderr.write("recall-cli: unknown op '" + op + "'\n")
    process.exit(2)
}

process.stdout.write(JSON.stringify(out) + "\n")
