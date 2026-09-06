// Pure logic for the glimpse plugin: a visual / photographic-memory trainer.
//
// Kept free of QML/Quickshell APIs so the round mechanics (how a Spot-the-
// Change round is scored, how the drill difficulty ramps, when a scheduled
// scene is due, when a check-in escalates to a takeover, how grading bends
// the next due date) can be reasoned about and Node-tested in isolation. The
// bash CLI (omarchy-glimpse) owns the JSON files, image fetching and the
// ImageMagick alterations; this module is the shared brain both it and the
// bar widget read from. See ~/.config/omarchy/docs/adr/0006-cli-first-plugins.md.

var MINUTE = 60000
var HOUR = 60 * MINUTE
var DAY = 24 * HOUR

var MODES = ["change", "grid", "glimpse"]           // grid + glimpse are scaffolded, not yet wired
var SESSION_TYPES = ["drill", "scheduled"]
var GRADES = ["again", "hard", "good", "easy"]
var MIN_LEVEL = 1
var MAX_LEVEL = 8

// ── defaults ─────────────────────────────────────────────────────────────

function defaultConfig() {
  return {
    version: 1,
    enabled: false,
    // Daily check-in cadence for scheduled scenes: a soft prompt at most
    // once every this-many hours since the last one.
    checkinGapHours: 20,
    // A scheduled scene overdue by this many days escalates the next prompt
    // to a fullscreen takeover.
    overdueTakeoverDays: 3,
    // This many dismissed check-ins in a row escalates too.
    dismissTakeoverStreak: 3,
    // Scheduled pool is kept topped up to this many scene cards.
    poolSize: 24,
    // Wallhaven search: query pool (one picked at random per fetch), plus the
    // category/purity/ratio filters. Biased toward rooms / streets / scenery
    // because those transfer best to tracking real surroundings.
    wallhaven: {
      queries: [
        "interior room", "living room", "kitchen", "office desk", "workshop",
        "street scene", "city street", "town square", "market", "cafe interior",
        "landscape", "mountain village", "harbour", "park", "bookshelf",
        "cluttered desk", "hotel lobby", "train station", "library interior"
      ],
      categories: "100",   // general only (no anime / people)
      purity: "100",       // SFW only
      ratios: "16x9,16x10",
      atleast: "1600x900"
    },
    // "Glimpse & Recall" question generation. deterministic probes always run;
    // vision Q&A is layered on top when this is true and llm-vision + a
    // vision-capable model are available. Off by default.
    visionQuestions: false,
    visionModel: "",
    // Drill exposure envelope, milliseconds, interpolated across the level
    // range. Study time shrinks as you climb.
    exposureMaxMs: 7000,
    exposureMinMs: 2500,
    // Blank-screen gap between study and test.
    blankMs: 650
  }
}

function defaultState() {
  return {
    version: 1,
    prompt: null,   // null | { kind:"checkin"|"takeover", cardIds:[id], reason }
    round: null,    // null | see startRound()
    session: { type: "drill", level: 3, rounds: 0, hits: 0, misses: 0, startedAt: 0 },
    dismissStreak: 0,
    lastPromptMs: 0,
    lastRoundMs: 0,
    roundsToday: 0,
    roundsTodayDate: "",
    pauseUntilMs: 0,
    streakDays: 0,
    lastActiveDate: "",
    lifetime: { rounds: 0, accuracySum: 0 }
  }
}

function defaultCards() {
  return { version: 1, cards: [] }
}

// ── parsing (tolerant — every reader gets a total, clamped shape) ────────

function clampNum(v, def) { return typeof v === "number" && isFinite(v) ? v : def }
function clampStr(v, def) { return typeof v === "string" ? v : def }
function clampInt(v, lo, hi, def) {
  var n = clampNum(v, def)
  n = Math.round(n)
  if (n < lo) n = lo
  if (n > hi) n = hi
  return n
}

function parseRect(raw) {
  raw = raw || {}
  return {
    x: Math.min(1, Math.max(0, clampNum(raw.x, 0))),
    y: Math.min(1, Math.max(0, clampNum(raw.y, 0))),
    w: Math.min(1, Math.max(0, clampNum(raw.w, 0.1))),
    h: Math.min(1, Math.max(0, clampNum(raw.h, 0.1))),
    kind: clampStr(raw.kind, "")
  }
}

function parsePoint(raw) {
  raw = raw || {}
  return {
    x: Math.min(1, Math.max(0, clampNum(raw.x, 0))),
    y: Math.min(1, Math.max(0, clampNum(raw.y, 0)))
  }
}

function parseRound(raw) {
  if (!raw || typeof raw !== "object") return null
  if (!Array.isArray(raw.truth)) return null
  return {
    id: clampStr(raw.id, ""),
    mode: MODES.indexOf(raw.mode) >= 0 ? raw.mode : "change",
    sessionType: SESSION_TYPES.indexOf(raw.sessionType) >= 0 ? raw.sessionType : "drill",
    cardId: typeof raw.cardId === "string" ? raw.cardId : null,
    sceneId: clampStr(raw.sceneId, ""),
    imageA: clampStr(raw.imageA, ""),
    imageB: clampStr(raw.imageB, ""),
    level: clampInt(raw.level, MIN_LEVEL, MAX_LEVEL, 3),
    exposureMs: Math.max(500, clampNum(raw.exposureMs, 5000)),
    blankMs: Math.max(0, clampNum(raw.blankMs, 650)),
    changeCount: Math.max(1, clampInt(raw.changeCount, 1, 12, 2)),
    truth: raw.truth.map(parseRect),
    clicks: Array.isArray(raw.clicks) ? raw.clicks.map(parsePoint) : [],
    startedAt: clampNum(raw.startedAt, 0)
  }
}

function parseCard(raw) {
  raw = raw || {}
  return {
    id: clampStr(raw.id, ""),
    sceneId: clampStr(raw.sceneId, ""),
    imageA: clampStr(raw.imageA, ""),
    imageB: clampStr(raw.imageB, ""),
    mode: MODES.indexOf(raw.mode) >= 0 ? raw.mode : "change",
    level: clampInt(raw.level, MIN_LEVEL, MAX_LEVEL, 3),
    changeCount: Math.max(1, clampInt(raw.changeCount, 1, 12, 2)),
    truth: Array.isArray(raw.truth) ? raw.truth.map(parseRect) : [],
    createdAt: clampNum(raw.createdAt, 0),
    ease: Math.min(3.0, Math.max(1.3, clampNum(raw.ease, 2.5))),
    intervalDays: Math.max(0, clampNum(raw.intervalDays, 0)),
    dueAt: Math.max(0, clampNum(raw.dueAt, 0)),
    reps: Math.max(0, clampNum(raw.reps, 0)),
    lapses: Math.max(0, clampNum(raw.lapses, 0)),
    lastGrade: GRADES.indexOf(raw.lastGrade) >= 0 ? raw.lastGrade : null,
    shownAt: raw.shownAt == null ? null : clampNum(raw.shownAt, null),
    bestAccuracy: Math.min(1, Math.max(0, clampNum(raw.bestAccuracy, 0)))
  }
}

function parseCards(json) {
  var d = defaultCards()
  try {
    var o = typeof json === "string" ? JSON.parse(json) : (json || {})
    if (!Array.isArray(o.cards)) return d
    var seen = {}
    var out = []
    for (var i = 0; i < o.cards.length; i++) {
      var c = parseCard(o.cards[i])
      if (!c.id || seen[c.id]) continue
      seen[c.id] = true
      out.push(c)
    }
    return { version: 1, cards: out }
  } catch (e) {
    return d
  }
}

function parseConfig(json) {
  var d = defaultConfig()
  try {
    var o = typeof json === "string" ? JSON.parse(json) : (json || {})
    var wh = (o.wallhaven && typeof o.wallhaven === "object") ? o.wallhaven : {}
    return {
      version: 1,
      enabled: !!o.enabled,
      checkinGapHours: clampNum(o.checkinGapHours, d.checkinGapHours),
      overdueTakeoverDays: clampNum(o.overdueTakeoverDays, d.overdueTakeoverDays),
      dismissTakeoverStreak: clampNum(o.dismissTakeoverStreak, d.dismissTakeoverStreak),
      poolSize: Math.max(1, clampInt(o.poolSize, 1, 500, d.poolSize)),
      wallhaven: {
        queries: Array.isArray(wh.queries) && wh.queries.length
          ? wh.queries.filter(function (s) { return typeof s === "string" }) : d.wallhaven.queries,
        categories: clampStr(wh.categories, d.wallhaven.categories),
        purity: clampStr(wh.purity, d.wallhaven.purity),
        ratios: clampStr(wh.ratios, d.wallhaven.ratios),
        atleast: clampStr(wh.atleast, d.wallhaven.atleast)
      },
      visionQuestions: !!o.visionQuestions,
      visionModel: clampStr(o.visionModel, ""),
      exposureMaxMs: Math.max(800, clampNum(o.exposureMaxMs, d.exposureMaxMs)),
      exposureMinMs: Math.max(500, clampNum(o.exposureMinMs, d.exposureMinMs)),
      blankMs: Math.max(0, clampNum(o.blankMs, d.blankMs))
    }
  } catch (e) {
    return d
  }
}

function parseSession(raw) {
  raw = raw || {}
  return {
    type: SESSION_TYPES.indexOf(raw.type) >= 0 ? raw.type : "drill",
    level: clampInt(raw.level, MIN_LEVEL, MAX_LEVEL, 3),
    rounds: Math.max(0, clampNum(raw.rounds, 0)),
    hits: Math.max(0, clampNum(raw.hits, 0)),
    misses: Math.max(0, clampNum(raw.misses, 0)),
    startedAt: clampNum(raw.startedAt, 0)
  }
}

function parseState(json) {
  var d = defaultState()
  try {
    var o = typeof json === "string" ? JSON.parse(json) : (json || {})
    var prompt = null
    if (o.prompt && typeof o.prompt === "object" && Array.isArray(o.prompt.cardIds)) {
      prompt = {
        kind: clampStr(o.prompt.kind, ""),
        cardIds: o.prompt.cardIds.filter(function (s) { return typeof s === "string" }),
        reason: clampStr(o.prompt.reason, "")
      }
    }
    var life = (o.lifetime && typeof o.lifetime === "object") ? o.lifetime : {}
    return {
      version: 1,
      prompt: prompt,
      round: parseRound(o.round),
      session: parseSession(o.session),
      dismissStreak: Math.max(0, clampNum(o.dismissStreak, 0)),
      lastPromptMs: Math.max(0, clampNum(o.lastPromptMs, 0)),
      lastRoundMs: Math.max(0, clampNum(o.lastRoundMs, 0)),
      roundsToday: Math.max(0, clampNum(o.roundsToday, 0)),
      roundsTodayDate: clampStr(o.roundsTodayDate, ""),
      pauseUntilMs: Math.max(0, clampNum(o.pauseUntilMs, 0)),
      streakDays: Math.max(0, clampNum(o.streakDays, 0)),
      lastActiveDate: clampStr(o.lastActiveDate, ""),
      lifetime: {
        rounds: Math.max(0, clampNum(life.rounds, 0)),
        accuracySum: Math.max(0, clampNum(life.accuracySum, 0))
      }
    }
  } catch (e) {
    return d
  }
}

// ── card helpers ─────────────────────────────────────────────────────────

function findCard(cards, id) {
  for (var i = 0; i < cards.length; i++) if (cards[i].id === id) return cards[i]
  return null
}

function dueCards(cards, now) {
  return cards.filter(function (c) { return c.dueAt <= now })
    .sort(function (a, b) { return a.dueAt - b.dueAt })
}

// ── drill difficulty ramp ────────────────────────────────────────────────
// level 1..8 -> exposure time (long -> short), number of planted changes,
// and a "subtlety" 1..8 the CLI turns into patch size + colour/brightness
// delta for ImageMagick.

function levelParams(level, config) {
  config = config || defaultConfig()
  var lv = clampInt(level, MIN_LEVEL, MAX_LEVEL, 3)
  var t = (lv - MIN_LEVEL) / (MAX_LEVEL - MIN_LEVEL)   // 0..1
  var exposureMs = Math.round(config.exposureMaxMs - t * (config.exposureMaxMs - config.exposureMinMs))
  var changeCount = Math.min(4, 1 + Math.floor((lv - 1) / 2))   // 1,1,2,2,3,3,4,4
  return { level: lv, exposureMs: exposureMs, blankMs: config.blankMs, changeCount: changeCount, subtlety: lv }
}

function nextLevel(level, gradeName) {
  var lv = clampInt(level, MIN_LEVEL, MAX_LEVEL, 3)
  if (gradeName === "good" || gradeName === "easy") lv += 1
  else if (gradeName === "again") lv -= 1
  return clampInt(lv, MIN_LEVEL, MAX_LEVEL, lv)
}

// ── scoring a Spot-the-Change round ─────────────────────────────────────
// Greedily match each click to the nearest not-yet-matched truth rect whose
// centre is within a tolerance radius (scaled to the rect size, floored so a
// tiny change is still forgiving). Pure and total.

function rectCentre(r) { return { x: r.x + r.w / 2, y: r.y + r.h / 2 } }
function dist(a, b) {
  var dx = a.x - b.x, dy = a.y - b.y
  return Math.sqrt(dx * dx + dy * dy)
}
function toleranceFor(r) {
  var diag = Math.sqrt(r.w * r.w + r.h * r.h)
  return Math.max(0.07, diag * 0.6)
}

function scoreHits(truth, clicks) {
  truth = Array.isArray(truth) ? truth : []
  clicks = Array.isArray(clicks) ? clicks : []
  var matchedTruth = truth.map(function () { return false })
  var results = []           // per click: { hit, truthIndex }
  var hits = 0

  for (var ci = 0; ci < clicks.length; ci++) {
    var best = -1, bestD = Infinity
    for (var ti = 0; ti < truth.length; ti++) {
      if (matchedTruth[ti]) continue
      var d = dist(clicks[ci], rectCentre(truth[ti]))
      if (d < bestD && d <= toleranceFor(truth[ti])) { bestD = d; best = ti }
    }
    if (best >= 0) { matchedTruth[best] = true; hits++; results.push({ hit: true, truthIndex: best }) }
    else results.push({ hit: false, truthIndex: -1 })
  }

  var total = truth.length || 1
  var extraClicks = Math.max(0, clicks.length - hits)
  var raw = hits / total - 0.5 * (extraClicks / total)
  var accuracy = Math.min(1, Math.max(0, raw))
  var missedTruth = []
  for (var mi = 0; mi < truth.length; mi++) if (!matchedTruth[mi]) missedTruth.push(mi)

  return {
    hits: hits,
    total: truth.length,
    extraClicks: extraClicks,
    accuracy: accuracy,
    clickResults: results,
    missedTruth: missedTruth,
    grade: gradeForAccuracy(accuracy)
  }
}

function gradeForAccuracy(a) {
  if (a >= 0.9) return "easy"
  if (a >= 0.7) return "good"
  if (a >= 0.4) return "hard"
  return "again"
}

// ── SM-2-lite grading (scheduled scenes) ───────────────────────────────
// Same shape as the recall plugin: quality 0=again 1=hard 2=good 3=easy,
// pure, returns a new card. A lapse ("again") comes back in 10 minutes so
// you re-see the scene the same session; a success compounds the interval.

function grade(card, gradeName, now, accuracy) {
  var q = GRADES.indexOf(gradeName)
  if (q < 0) q = 2
  var next = {}
  for (var k in card) next[k] = card[k]

  if (q === 0) {
    next.reps = 0
    next.lapses = card.lapses + 1
    next.intervalDays = 0
    next.ease = Math.max(1.3, card.ease - 0.2)
    next.dueAt = now + 10 * MINUTE
  } else {
    next.reps = card.reps + 1
    var interval
    if (next.reps === 1) interval = q === 1 ? 1 : (q === 2 ? 2 : 3)
    else if (next.reps === 2) interval = q === 1 ? 3 : (q === 2 ? 6 : 9)
    else interval = card.intervalDays * card.ease * (q === 1 ? 0.85 : (q === 3 ? 1.25 : 1))
    next.intervalDays = Math.max(1, Math.round(interval))
    next.ease = Math.min(3.0, Math.max(1.3, card.ease + (q === 1 ? -0.15 : (q === 3 ? 0.15 : 0.05))))
    next.dueAt = now + next.intervalDays * DAY
  }
  next.lastGrade = gradeName
  next.shownAt = now
  if (typeof accuracy === "number" && isFinite(accuracy)) {
    next.bestAccuracy = Math.max(card.bestAccuracy || 0, Math.min(1, Math.max(0, accuracy)))
  }
  return next
}

function gradeCard(cards, id, gradeName, now, accuracy) {
  return cards.map(function (c) { return c.id === id ? grade(c, gradeName, now, accuracy) : c })
}

// ── round construction ─────────────────────────────────────────────────
// The CLI has already fetched + altered the scene and knows the truth rects;
// this just assembles the round object the Overlay reads. `spec` carries the
// image paths, sceneId, truth, and (scheduled only) the source cardId.

function startRound(spec, sessionType, level, config, now) {
  config = config || defaultConfig()
  var lp = levelParams(level, config)
  return {
    id: "r" + (now || Date.now()).toString(36),
    mode: "change",
    sessionType: SESSION_TYPES.indexOf(sessionType) >= 0 ? sessionType : "drill",
    cardId: spec && typeof spec.cardId === "string" ? spec.cardId : null,
    sceneId: spec && spec.sceneId ? String(spec.sceneId) : "",
    imageA: spec && spec.imageA ? String(spec.imageA) : "",
    imageB: spec && spec.imageB ? String(spec.imageB) : "",
    level: lp.level,
    exposureMs: lp.exposureMs,
    blankMs: lp.blankMs,
    changeCount: Array.isArray(spec && spec.truth) ? spec.truth.length : lp.changeCount,
    truth: Array.isArray(spec && spec.truth) ? spec.truth.map(parseRect) : [],
    clicks: [],
    startedAt: now || Date.now()
  }
}

function addCardFromRound(cards, round, now, opts) {
  opts = opts || {}
  var id = opts.id || ("s" + (now || Date.now()).toString(36) + Math.random().toString(36).slice(2, 6))
  var card = parseCard({
    id: id, sceneId: round.sceneId, imageA: round.imageA, imageB: round.imageB,
    mode: round.mode, level: round.level, changeCount: round.truth.length,
    truth: round.truth, createdAt: now || Date.now(),
    dueAt: (now || Date.now()) + DAY
  })
  return { cards: cards.concat([card]), id: id }
}

function dropCard(cards, id) {
  return cards.filter(function (c) { return c.id !== id })
}

// ── daily bookkeeping ───────────────────────────────────────────────────

function dateKey(ms) { return new Date(ms).toISOString().slice(0, 10) }

function rollDaily(state, now) {
  var today = dateKey(now)
  var next = {}
  for (var k in state) next[k] = state[k]
  if (state.roundsTodayDate !== today) {
    next.roundsToday = 0
    next.roundsTodayDate = today
  }
  if (state.lastActiveDate !== today) {
    var yesterday = dateKey(now - DAY)
    next.streakDays = state.lastActiveDate === yesterday ? state.streakDays + 1 : 1
    next.lastActiveDate = today
  }
  return next
}

// ── the decision engine ────────────────────────────────────────────────
// A scheduled scene that's due raises a soft check-in once the cadence gap
// has passed; a big overdue backlog or a run of dismissals escalates it to a
// fullscreen takeover. Drill rounds are user-initiated and never appear here.

function decide(config, state, cards, now) {
  if (!config.enabled) return { prompt: null, reason: "disabled", nextIntervalMs: config.checkinGapHours * HOUR }
  if (now < state.pauseUntilMs) return { prompt: null, reason: "paused", nextIntervalMs: state.pauseUntilMs - now }

  var due = dueCards(cards, now)
  if (due.length === 0) {
    return { prompt: null, reason: "caught-up", nextIntervalMs: config.checkinGapHours * HOUR }
  }

  var gap = config.checkinGapHours * HOUR
  var elapsed = now - state.lastPromptMs
  if (elapsed < gap) {
    return { prompt: null, reason: "not-yet", nextIntervalMs: gap - elapsed }
  }

  var reviewedDue = due.filter(function (c) { return c.reps > 0 || c.lapses > 0 })
  var oldestOverdueMs = reviewedDue.length > 0 ? now - reviewedDue[0].dueAt : 0
  var escalate = state.dismissStreak >= config.dismissTakeoverStreak
    ? "dismissed"
    : (oldestOverdueMs >= config.overdueTakeoverDays * DAY ? "overdue" : null)
  var kind = escalate ? "takeover" : "checkin"
  return {
    prompt: { kind: kind, cardIds: [due[0].id], reason: escalate || "due" },
    reason: escalate || "due",
    nextIntervalMs: gap
  }
}

// ── stats + formatting ─────────────────────────────────────────────────

function stats(cards, state, now) {
  var seen = cards.filter(function (c) { return c.reps > 0 || c.lapses > 0 })
  var life = state.lifetime || { rounds: 0, accuracySum: 0 }
  return {
    poolSize: cards.length,
    learnedCount: cards.filter(function (c) { return c.shownAt != null }).length,
    dueCount: dueCards(cards, now || Date.now()).length,
    reviewedCount: seen.length,
    lifetimeRounds: life.rounds,
    lifetimeAccuracy: life.rounds ? life.accuracySum / life.rounds : null,
    drillLevel: state.session ? state.session.level : 3,
    streakDays: state.streakDays,
    roundsToday: state.roundsToday
  }
}

function formatDue(deltaMs) {
  if (deltaMs <= 0) {
    var overdue = -deltaMs
    if (overdue < MINUTE) return "due now"
    if (overdue < HOUR) return Math.round(overdue / MINUTE) + "m overdue"
    if (overdue < DAY) return Math.round(overdue / HOUR) + "h overdue"
    return Math.round(overdue / DAY) + "d overdue"
  }
  if (deltaMs < HOUR) return "in " + Math.round(deltaMs / MINUTE) + "m"
  if (deltaMs < DAY) return "in " + Math.round(deltaMs / HOUR) + "h"
  return "in " + Math.round(deltaMs / DAY) + "d"
}

function formatPct(x) {
  if (x == null || !isFinite(x)) return "—"
  return Math.round(x * 100) + "%"
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    MINUTE: MINUTE, HOUR: HOUR, DAY: DAY,
    MODES: MODES, SESSION_TYPES: SESSION_TYPES, GRADES: GRADES,
    MIN_LEVEL: MIN_LEVEL, MAX_LEVEL: MAX_LEVEL,
    defaultConfig: defaultConfig, defaultState: defaultState, defaultCards: defaultCards,
    parseConfig: parseConfig, parseState: parseState, parseCards: parseCards,
    parseCard: parseCard, parseRound: parseRound,
    findCard: findCard, dueCards: dueCards,
    levelParams: levelParams, nextLevel: nextLevel,
    scoreHits: scoreHits, gradeForAccuracy: gradeForAccuracy,
    grade: grade, gradeCard: gradeCard,
    startRound: startRound, addCardFromRound: addCardFromRound, dropCard: dropCard,
    dateKey: dateKey, rollDaily: rollDaily, decide: decide,
    stats: stats, formatDue: formatDue, formatPct: formatPct
  }
}
