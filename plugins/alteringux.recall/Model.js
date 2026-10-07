// Pure logic for the recall plugin: the spaced-repetition scheduler + the
// intrusion decision engine.
//
// Kept free of QML/Quickshell APIs so the daemon's behaviour (when a lesson
// gets taught, when a quiz check-in is due, when either escalates to a
// fullscreen takeover, how grading bends the next due date) can be reasoned
// about and Node-tested in isolation. The bash CLI (omarchy-recall) owns the
// JSON files and side effects; this module is the shared brain both it and
// the bar widget read from. See docs/adr/0006-cli-first-plugins.md.

var MINUTE = 60000
var HOUR = 60 * MINUTE
var DAY = 24 * HOUR

var CATEGORIES = ["technique", "trivia", "vocabulary", "custom"]
var KINDS = ["lesson", "quiz"]
var PROMPT_KINDS = ["lesson", "checkin", "takeover"]
var GRADES = ["again", "hard", "good", "easy"]

// ── defaults ─────────────────────────────────────────────────────────────

function defaultConfig() {
  return {
    version: 1,
    enabled: false,
    // Adaptive check-in cadence, in minutes, for quiz rounds (same shape as
    // grip's escalation math): sits at base, bends toward min while a big
    // backlog is due or you keep dismissing, stretches toward max when the
    // deck is caught up.
    baseIntervalMin: 45,
    minIntervalMin: 15,
    maxIntervalMin: 150,
    // How many due quiz cards a single check-in shows at once.
    quizBatchSize: 5,
    // A quiz backlog overdue by this many hours escalates the next prompt to
    // a fullscreen takeover.
    overdueTakeoverHours: 8,
    // This many dismissed check-ins in a row escalates too.
    dismissTakeoverStreak: 3,
    // New technique lessons are rationed: at most this many fresh lessons
    // per day, and at least this many hours apart, so teaching moments stay
    // short and spaced rather than dumped all at once.
    dailyNewLessonCap: 1,
    lessonGapHours: 20,
    // Snooze buttons offered on a quiz prompt, in minutes.
    snoozeMinutes: [15, 60]
  }
}

// One JSON file holds every card, content and schedule together (unlike
// grip's separate tasks/state split) — a recall card's due date is as much
// "the content" as its front/back text, so there is nothing to gain from
// splitting them.
function defaultCards() {
  return { version: 1, cards: seedCards() }
}

function defaultState() {
  return {
    version: 1,
    prompt: null,            // null | { kind: "lesson"|"checkin"|"takeover", cardIds: [...], reason }
    dismissStreak: 0,
    lastPromptMs: 0,
    lastLessonMs: 0,
    lessonsToday: 0,
    lessonsTodayDate: "",
    pauseUntilMs: 0,
    streakDays: 0,
    lastActiveDate: ""
  }
}

// ── seed content ─────────────────────────────────────────────────────────
// A starter deck so the plugin teaches something from the first run, rather
// than sitting empty until the user hand-authors cards. Lessons are short —
// 3-5 slides, a sentence or two each — because a takeover should cost you
// under a minute, not become a reading assignment.

function lessonSeed(id, title, slides) {
  return {
    id: id, kind: "lesson", category: "technique", title: title, slides: slides,
    front: null, back: null, image: null, linkedLessonId: null,
    createdAt: 0, ease: 2.5, intervalDays: 0, dueAt: 0, reps: 0, lapses: 0,
    lastGrade: null, shownAt: null
  }
}

function quizSeed(id, category, front, back) {
  return {
    id: id, kind: "quiz", category: category, title: null, slides: null,
    front: front, back: back, image: null, linkedLessonId: null,
    createdAt: 0, ease: 2.5, intervalDays: 0, dueAt: 0, reps: 0, lapses: 0,
    lastGrade: null, shownAt: null
  }
}

function seedCards() {
  var lessons = [
    lessonSeed("seed-loci", "Method of Loci", [
      "Pick a route you know cold — your hallway, your commute. Each stop is a \"locus\".",
      "To memorize a list, place one vivid image per locus, in order: an exaggerated, absurd, moving image sticks better than a plain one.",
      "To recall, walk the route in your head and read off what you placed at each stop.",
      "Reuse the same route for many lists by clearing it mentally before you load a new one."
    ]),
    lessonSeed("seed-chunking", "Chunking", [
      "Working memory holds about 4-7 items — but an \"item\" can be a group.",
      "Break a long string into meaningful clusters: a phone number as 3 chunks, not 10 digits.",
      "The chunk itself can be a memorized unit (a word, a familiar pattern), so bigger chunks fit the same slot.",
      "Re-chunk anything long before trying to hold it: dates, IDs, code, playlists."
    ]),
    lessonSeed("seed-pao", "PAO System", [
      "Person-Action-Object: assign every 2-digit number (00-99) a fixed Person, Action, and Object.",
      "To memorize a 6-digit number, take 2 digits as the Person, 2 as the Action, 2 as the Object, and combine them into one scene.",
      "A deck of cards or a long numeric string becomes a short sequence of scenes instead of raw digits.",
      "Building the 100-entry table once is the investment; after that, encoding is fast and reusable."
    ]),
    lessonSeed("seed-imagelink", "Image Association", [
      "Abstract facts don't stick; concrete, sensory images do.",
      "Turn a fact into a mental picture that interacts: the two things should touch, collide, or do something absurd together.",
      "Exaggeration, motion, and humor all beat a plain, static image for recall.",
      "This is the atomic move under Loci and PAO both — practice it standalone on plain vocabulary."
    ]),
    lessonSeed("seed-story", "Story Method", [
      "Chain items into a short narrative instead of memorizing them as a bare list.",
      "Each item becomes an actor or event; the next item is what happens because of the last one.",
      "The story's causal links do the work a list's arbitrary order can't — one item cues the next.",
      "Weaker than Loci for very long lists, but faster to build for short ones (5-10 items)."
    ]),
    lessonSeed("seed-majorsystem", "The Major System", [
      "Map each digit 0-9 to a consonant sound: 0=s/z, 1=t/d, 2=n, 3=m, 4=r, 5=l, 6=j/sh, 7=k/g, 8=f/v, 9=p/b.",
      "Turn a number into consonants, then fill in vowels freely to make a word — 32 becomes \"m-n\" -> \"moon\".",
      "Now the number is a concrete word you can turn into an image, and chain via Loci or a story.",
      "This is the encoding layer that makes PAO's number table possible in the first place."
    ]),
    lessonSeed("seed-activerecall", "Active Recall > Rereading", [
      "Rereading feels productive but barely improves retention — recognition is not recall.",
      "Testing yourself, even badly, strengthens the memory trace far more than a passive re-read.",
      "The struggle to retrieve is the point: effortful recall is what this whole plugin is built around.",
      "Prefer generating the answer from a blank prompt over multiple-choice whenever you can."
    ]),
    lessonSeed("seed-spacing", "Spaced Repetition", [
      "Cramming forgets fast; reviewing right as you're about to forget locks it in for longer each time.",
      "Every successful recall pushes the next review further out — that's why intervals compound.",
      "A missed recall (\"again\") resets the interval — it's not a failure of the system, it's the system working.",
      "This is exactly what grading a card here (Again / Hard / Good / Easy) is scheduling for you."
    ])
  ]

  return lessons.concat(triviaSeedCards())
}

// The curated, offline trivia starter set — no NanoGPT/network needed.
// Kept separate from seedCards() so it can also be re-applied on its own
// (see mergeCards / the CLI's `seed-trivia` verb) to top up an existing
// deck that predates this list or is missing some of it, without touching
// lessons or anything the user has added.
var TRIVIA_SEED = [
  ["geography", "What is the smallest country in the world by area?", "Vatican City"],
  ["geography", "Which river is the longest in the world?", "The Nile (by most measures)"],
  ["geography", "What is the capital of Australia?", "Canberra (not Sydney)"],
  ["science", "What is the powerhouse of the cell?", "The mitochondrion"],
  ["science", "What gas do plants absorb that animals exhale?", "Carbon dioxide"],
  ["science", "What is the chemical symbol for gold?", "Au"],
  ["history", "In what year did the Berlin Wall fall?", "1989"],
  ["history", "Who was the first person to walk on the Moon?", "Neil Armstrong"],
  ["history", "Which empire built Machu Picchu?", "The Inca Empire"],
  ["language", "What is the plural of \"octopus\" preferred by classicists?", "Octopuses (octopodes is the Greek-derived form; \"octopi\" is a common myth)"],
  ["language", "What does the Latin phrase \"carpe diem\" literally mean?", "Seize the day"],
  ["art", "Who painted \"The Starry Night\"?", "Vincent van Gogh"],
  ["art", "Which composer was deaf for much of his later career?", "Ludwig van Beethoven"],
  ["misc", "How many bones are in the adult human body?", "206"],
  ["misc", "What is the hardest natural substance on Earth?", "Diamond"],
  ["geography", "What is the longest mountain range in the world?", "The Andes"],
  ["science", "What planet has the most moons in our solar system?", "Saturn"],
  ["history", "Which ancient wonder of the world still stands today?", "The Great Pyramid of Giza"],
  ["language", "What does \"etc.\" stand for in Latin?", "Et cetera (\"and the rest\")"],
  ["misc", "What is the most spoken native language in the world?", "Mandarin Chinese"]
]

function triviaSeedCards() {
  return TRIVIA_SEED.map(function (row, i) {
    return quizSeed("seed-trivia-" + i, "trivia", row[1], row[2])
  })
}

// Appends any of `additions` whose id isn't already present in `cards` —
// the general "top up a deck without duplicating" merge used to (re)apply
// a seed set (e.g. trivia) after the initial seed, idempotently.
function mergeCards(cards, additions) {
  var seen = {}
  for (var i = 0; i < cards.length; i++) seen[cards[i].id] = true
  var added = additions.filter(function (c) { return !seen[c.id] })
  return { cards: cards.concat(added), addedCount: added.length }
}

// ── parsing (tolerant — every reader gets a total, clamped shape) ────────

function clampNum(v, def) { return typeof v === "number" && isFinite(v) ? v : def }
function clampStr(v, def) { return typeof v === "string" ? v : def }

function parseCard(raw) {
  raw = raw || {}
  var kind = KINDS.indexOf(raw.kind) >= 0 ? raw.kind : "quiz"
  var category = CATEGORIES.indexOf(raw.category) >= 0 ? raw.category : "custom"
  return {
    id: clampStr(raw.id, ""),
    kind: kind,
    category: category,
    title: kind === "lesson" ? clampStr(raw.title, "") : null,
    slides: kind === "lesson" && Array.isArray(raw.slides) ? raw.slides.filter(function (s) { return typeof s === "string" }) : null,
    front: kind === "quiz" ? clampStr(raw.front, "") : null,
    back: kind === "quiz" ? clampStr(raw.back, "") : null,
    image: typeof raw.image === "string" ? raw.image : null,
    linkedLessonId: typeof raw.linkedLessonId === "string" ? raw.linkedLessonId : null,
    createdAt: clampNum(raw.createdAt, 0),
    ease: Math.min(3.0, Math.max(1.3, clampNum(raw.ease, 2.5))),
    intervalDays: Math.max(0, clampNum(raw.intervalDays, 0)),
    dueAt: Math.max(0, clampNum(raw.dueAt, 0)),
    reps: Math.max(0, clampNum(raw.reps, 0)),
    lapses: Math.max(0, clampNum(raw.lapses, 0)),
    lastGrade: GRADES.indexOf(raw.lastGrade) >= 0 ? raw.lastGrade : null,
    shownAt: raw.shownAt == null ? null : clampNum(raw.shownAt, null)
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
      var contentOk = c.kind === "quiz"
        ? c.front.trim().length > 0 && c.back.trim().length > 0
        : c.title.trim().length > 0 && Array.isArray(c.slides) && c.slides.length > 0 &&
          c.slides.every(function (s) { return s.trim().length > 0 })
      if (!c.id || seen[c.id] || !contentOk) continue
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
    if (!o || typeof o !== "object" || Array.isArray(o)) return d

    function positiveInt(v, fallback, min) {
      var n = clampNum(v, fallback)
      return Math.max(min, Math.floor(n))
    }
    var minIntervalMin = positiveInt(o.minIntervalMin, d.minIntervalMin, 1)
    var baseIntervalMin = Math.max(minIntervalMin, positiveInt(o.baseIntervalMin, d.baseIntervalMin, 1))
    var maxIntervalMin = Math.max(baseIntervalMin, positiveInt(o.maxIntervalMin, d.maxIntervalMin, 1))
    var snoozeMinutes = Array.isArray(o.snoozeMinutes)
      ? o.snoozeMinutes
        .filter(function (v) { return typeof v === "number" && isFinite(v) && v > 0 })
        .map(function (v) { return Math.floor(v) })
        .filter(function (v, i, a) { return v > 0 && a.indexOf(v) === i })
      : []
    if (snoozeMinutes.length === 0) snoozeMinutes = d.snoozeMinutes.slice()

    return {
      version: 1,
      enabled: typeof o.enabled === "boolean" ? o.enabled : d.enabled,
      baseIntervalMin: baseIntervalMin,
      minIntervalMin: minIntervalMin,
      maxIntervalMin: maxIntervalMin,
      quizBatchSize: positiveInt(o.quizBatchSize, d.quizBatchSize, 1),
      overdueTakeoverHours: Math.max(0, clampNum(o.overdueTakeoverHours, d.overdueTakeoverHours)),
      dismissTakeoverStreak: positiveInt(o.dismissTakeoverStreak, d.dismissTakeoverStreak, 0),
      dailyNewLessonCap: positiveInt(o.dailyNewLessonCap, d.dailyNewLessonCap, 0),
      lessonGapHours: Math.max(0, clampNum(o.lessonGapHours, d.lessonGapHours)),
      snoozeMinutes: snoozeMinutes
    }
  } catch (e) {
    return d
  }
}

function parseState(json) {
  var d = defaultState()
  try {
    var o = typeof json === "string" ? JSON.parse(json) : (json || {})
    var prompt = null
    if (o.prompt && typeof o.prompt === "object" && Array.isArray(o.prompt.cardIds)) {
      var kind = clampStr(o.prompt.kind, "")
      var cardIds = o.prompt.cardIds.filter(function (s) { return typeof s === "string" && s.trim().length > 0 })
      if (PROMPT_KINDS.indexOf(kind) >= 0 && cardIds.length > 0) {
        prompt = { kind: kind, cardIds: cardIds, reason: clampStr(o.prompt.reason, "") }
        // Current slide of an in-progress lesson, persisted so a shell
        // restart resumes the lesson instead of restarting it at slide 1.
        // Optional: absent for non-lesson prompts and for state written
        // before this field existed.
        if (typeof o.prompt.slideIndex === "number" && isFinite(o.prompt.slideIndex) && o.prompt.slideIndex >= 0) {
          prompt.slideIndex = Math.floor(o.prompt.slideIndex)
        }
      }
    }
    return {
      version: 1,
      prompt: prompt,
      dismissStreak: Math.max(0, clampNum(o.dismissStreak, 0)),
      lastPromptMs: Math.max(0, clampNum(o.lastPromptMs, 0)),
      lastLessonMs: Math.max(0, clampNum(o.lastLessonMs, 0)),
      lessonsToday: Math.max(0, clampNum(o.lessonsToday, 0)),
      lessonsTodayDate: clampStr(o.lessonsTodayDate, ""),
      pauseUntilMs: Math.max(0, clampNum(o.pauseUntilMs, 0)),
      streakDays: Math.max(0, clampNum(o.streakDays, 0)),
      lastActiveDate: clampStr(o.lastActiveDate, "")
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

function dueQuizzes(cards, now) {
  return cards.filter(function (c) { return c.kind === "quiz" && c.dueAt <= now })
    .sort(function (a, b) { return a.dueAt - b.dueAt })
}

function unseenLessons(cards) {
  return cards.filter(function (c) { return c.kind === "lesson" && c.shownAt == null })
}

function topDue(cards, now, n) {
  return dueQuizzes(cards, now).slice(0, n)
}

function shuffle(arr, rng) {
  rng = rng || Math.random
  var a = arr.slice()
  for (var i = a.length - 1; i > 0; i--) {
    var j = Math.floor(rng() * (i + 1))
    var tmp = a[i]; a[i] = a[j]; a[j] = tmp
  }
  return a
}

// Multiple-choice "clue" for a quiz card: the correct answer plus up to
// n-1 distractors pulled from other quiz cards' back text (same category
// preferred, any other category as a fallback), all shuffled together.
// Pure and total: with too few other cards to draw distractors from it just
// returns fewer options — it never throws and never repeats the same
// answer text twice. `rng` is injectable (defaults to Math.random) so
// shuffling is deterministic under test.
function buildChoices(card, cards, n, rng) {
  n = n || 4
  var pool = cards.filter(function (c) {
    return c.kind === "quiz" && c.id !== card.id && typeof c.back === "string" && c.back !== card.back
  })
  var sameCategory = shuffle(pool.filter(function (c) { return c.category === card.category }), rng)
  var otherCategory = shuffle(pool.filter(function (c) { return c.category !== card.category }), rng)
  var ordered = sameCategory.concat(otherCategory)

  var seen = {}
  seen[card.back] = true
  var distractors = []
  for (var i = 0; i < ordered.length && distractors.length < n - 1; i++) {
    var back = ordered[i].back
    if (seen[back]) continue
    seen[back] = true
    distractors.push(back)
  }

  var options = shuffle([card.back].concat(distractors), rng)
  return { options: options, correctIndex: options.indexOf(card.back) }
}

// ── SM-2-lite grading ───────────────────────────────────────────────────
// quality: 0=again 1=hard 2=good 3=easy. Pure — returns a new card object,
// never mutates the input.

function grade(card, gradeName, now) {
  var q = GRADES.indexOf(gradeName)
  if (q < 0) q = 2
  var next = {}
  for (var k in card) next[k] = card[k]

  if (q === 0) {
    // A lapse: back to the start, ease takes a hit, due again soon (10 min)
    // rather than tomorrow — you're meant to re-see it the same session.
    next.reps = 0
    next.lapses = card.lapses + 1
    next.intervalDays = 0
    next.ease = Math.max(1.3, card.ease - 0.2)
    next.dueAt = now + 10 * MINUTE
  } else {
    next.reps = card.reps + 1
    var interval
    if (next.reps === 1) interval = q === 1 ? 1 : (q === 2 ? 1 : 2)
    else if (next.reps === 2) interval = q === 1 ? 3 : (q === 2 ? 6 : 8)
    else interval = card.intervalDays * card.ease * (q === 1 ? 0.85 : (q === 3 ? 1.25 : 1))
    next.intervalDays = Math.max(1, Math.round(interval))
    next.ease = Math.min(3.0, Math.max(1.3, card.ease + (q === 1 ? -0.15 : (q === 3 ? 0.15 : 0.05))))
    next.dueAt = now + next.intervalDays * DAY
  }
  next.lastGrade = gradeName
  next.shownAt = now
  return next
}

// ── daily bookkeeping ───────────────────────────────────────────────────

// Local calendar day of `ms` as "YYYY-MM-DD". NOT toISOString().slice(0,10):
// that is a UTC boundary, so for a user hours off UTC (AEST is +10/+11) the
// daily lesson cap would reset mid-morning and the streak could miscount
// around that offset. Local, like pomodoro's todayDateString.
function dateKey(ms) {
  var d = new Date(ms)
  var mo = d.getMonth() + 1
  var da = d.getDate()
  return d.getFullYear() + "-" + (mo < 10 ? "0" : "") + mo + "-" + (da < 10 ? "0" : "") + da
}

// The local calendar day before `key` ("YYYY-MM-DD"). Walks the date field so
// a DST transition can't land it two days back (which `dateKey(now - DAY)` can).
function prevDateKey(key) {
  var p = String(key).split("-").map(Number)
  var d = new Date(p[0], p[1] - 1, p[2])
  d.setDate(d.getDate() - 1)
  return dateKey(d.getTime())
}

function rollDaily(state, now) {
  var today = dateKey(now)
  var next = {}
  for (var k in state) next[k] = state[k]
  if (state.lessonsTodayDate !== today) {
    next.lessonsToday = 0
    next.lessonsTodayDate = today
  }
  if (state.lastActiveDate !== today) {
    next.streakDays = state.lastActiveDate === prevDateKey(today) ? state.streakDays + 1 : 1
    next.lastActiveDate = today
  }
  return next
}

// ── the decision engine ─────────────────────────────────────────────────
// Mirrors grip's escalation shape: an adaptive cadence for the routine
// prompt (here, a quiz check-in), escalating to a fullscreen takeover on a
// big backlog or too many dismissals in a row. A fresh technique lesson
// always takes over the whole screen the moment it's due — teaching is
// meant to be a short, undivided-attention moment, not a corner popup —
// but is rationed by dailyNewLessonCap/lessonGapHours so it stays rare.

function nextIntervalMs(config, dueCount, dismissStreak) {
  var base = config.baseIntervalMin
  var min = config.minIntervalMin
  var max = config.maxIntervalMin
  var minutes = base
  if (dueCount > config.quizBatchSize * 2 || dismissStreak > 0) {
    var pressure = Math.min(1, (dueCount / (config.quizBatchSize * 4)) + dismissStreak * 0.2)
    minutes = base - (base - min) * pressure
  } else if (dueCount === 0) {
    minutes = max
  }
  return Math.round(minutes) * MINUTE
}

function decide(config, state, cards, now) {
  if (!config.enabled) return { prompt: null, reason: "disabled", nextIntervalMs: nextIntervalMs(config, 0, 0) }
  if (now < state.pauseUntilMs) return { prompt: null, reason: "paused", nextIntervalMs: state.pauseUntilMs - now }

  var lessonReady = state.lessonsToday < config.dailyNewLessonCap &&
    (now - state.lastLessonMs) >= config.lessonGapHours * HOUR
  var lessons = unseenLessons(cards)
  if (lessonReady && lessons.length > 0) {
    return { prompt: { kind: "lesson", cardIds: [lessons[0].id], reason: "new-lesson" }, reason: "new-lesson", nextIntervalMs: 0 }
  }

  var due = dueQuizzes(cards, now)
  if (due.length === 0) {
    return { prompt: null, reason: "caught-up", nextIntervalMs: nextIntervalMs(config, 0, state.dismissStreak) }
  }

  // A brand-new, never-graded card is "due now" by design (that's the SRS
  // baseline), not "overdue" — it must never itself force a takeover just
  // because its dueAt sits at epoch 0. Only cards that were graded before
  // and have since gone stale count toward the overdue escalation.
  var reviewedDue = due.filter(function (c) { return c.reps > 0 || c.lapses > 0 })
  var oldestOverdueMs = reviewedDue.length > 0 ? now - reviewedDue[0].dueAt : 0
  var elapsedSincePrompt = now - state.lastPromptMs
  var interval = nextIntervalMs(config, due.length, state.dismissStreak)
  if (elapsedSincePrompt < interval) {
    return { prompt: null, reason: "not-yet", nextIntervalMs: interval - elapsedSincePrompt }
  }

  var escalate = state.dismissStreak >= config.dismissTakeoverStreak
    ? "dismissed"
    : (oldestOverdueMs >= config.overdueTakeoverHours * HOUR ? "overdue" : null)
  var kind = escalate ? "takeover" : "checkin"
  var batch = due.slice(0, escalate ? Math.max(config.quizBatchSize, due.length) : config.quizBatchSize)
  return {
    prompt: { kind: kind, cardIds: batch.map(function (c) { return c.id }), reason: escalate || "due" },
    reason: escalate || "due",
    nextIntervalMs: interval
  }
}

// ── mutation helpers (called by the CLI, not used by the daemon read path) ─

function addQuizCard(cards, input, opts) {
  opts = opts || {}
  var id = opts.id || ("c" + (opts.now || Date.now()).toString(36) + Math.random().toString(36).slice(2, 6))
  var card = quizSeed(id, CATEGORIES.indexOf(input.category) >= 0 ? input.category : "custom", input.front || "", input.back || "")
  card.image = input.image || null
  card.createdAt = opts.now || Date.now()
  return { cards: cards.concat([card]), id: id }
}

function addLessonCard(cards, input, opts) {
  opts = opts || {}
  var id = opts.id || ("l" + (opts.now || Date.now()).toString(36) + Math.random().toString(36).slice(2, 6))
  var card = lessonSeed(id, input.title || "", Array.isArray(input.slides) ? input.slides : [])
  card.createdAt = opts.now || Date.now()
  return { cards: cards.concat([card]), id: id }
}

function dropCard(cards, id) {
  return cards.filter(function (c) { return c.id !== id })
}

// Marking a lesson seen retires it from the "unseen" queue and, if it
// doesn't already have one, spins up a companion quiz card due tomorrow —
// this is the "show it, then quiz later" loop the whole plugin is for.
function markLessonSeen(cards, id, now) {
  var out = []
  var lessonTitle = null
  var already = cards.some(function (c) { return c.linkedLessonId === id })
  for (var i = 0; i < cards.length; i++) {
    var c = cards[i]
    if (c.id === id && c.kind === "lesson") {
      lessonTitle = c.title
      var next = {}
      for (var k in c) next[k] = c[k]
      next.shownAt = now
      out.push(next)
    } else {
      out.push(c)
    }
  }
  if (lessonTitle != null && !already) {
    var companionId = "q-" + id
    var summary = null
    var lesson = findCard(cards, id)
    if (lesson && lesson.slides && lesson.slides.length) summary = lesson.slides[lesson.slides.length - 1]
    var companion = quizSeed(companionId, "technique",
      "Recall: describe the technique from \"" + lessonTitle + "\" in your own words.",
      summary || lessonTitle)
    companion.linkedLessonId = id
    companion.createdAt = now
    companion.dueAt = now + DAY
    out.push(companion)
  }
  return out
}

function gradeCard(cards, id, gradeName, now) {
  return cards.map(function (c) { return c.id === id ? grade(c, gradeName, now) : c })
}

// ── stats + formatting ───────────────────────────────────────────────────

function stats(cards, state) {
  var quizzes = cards.filter(function (c) { return c.kind === "quiz" })
  var seen = quizzes.filter(function (c) { return c.reps > 0 || c.lapses > 0 })
  var successes = seen.filter(function (c) { return c.lastGrade && c.lastGrade !== "again" })
  return {
    totalCards: cards.length,
    lessonsTotal: cards.filter(function (c) { return c.kind === "lesson" }).length,
    lessonsLearned: cards.filter(function (c) { return c.kind === "lesson" && c.shownAt != null }).length,
    dueCount: 0, // filled in by caller (needs `now`)
    reviewedCount: seen.length,
    retentionRate: seen.length ? successes.length / seen.length : null,
    streakDays: state.streakDays
  }
}

// Bug fix: the unit bucket used to be chosen from the raw ms delta (e.g.
// `overdue < HOUR`) and only then rounded for display. A delta a few ms
// under an hour (or under a day) picked the minutes (or hours) bucket but
// rounded up to the next unit's own threshold — "60m overdue" / "24h
// overdue" instead of "1h overdue" / "1d overdue". Round first, then bucket
// the rounded value, so a value that rounds up to the next unit displays in
// that unit instead of at the top of the one below it.
function formatDue(deltaMs, now) {
  if (deltaMs <= 0) {
    var overdue = -deltaMs
    if (overdue < MINUTE) return "due now"
    var m = Math.round(overdue / MINUTE)
    if (m < 60) return m + "m overdue"
    var h = Math.round(overdue / HOUR)
    if (h < 24) return h + "h overdue"
    return Math.round(overdue / DAY) + "d overdue"
  }
  var m2 = Math.round(deltaMs / MINUTE)
  if (m2 < 60) return "in " + m2 + "m"
  var h2 = Math.round(deltaMs / HOUR)
  if (h2 < 24) return "in " + h2 + "h"
  return "in " + Math.round(deltaMs / DAY) + "d"
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    MINUTE: MINUTE, HOUR: HOUR, DAY: DAY,
    CATEGORIES: CATEGORIES, KINDS: KINDS, PROMPT_KINDS: PROMPT_KINDS, GRADES: GRADES,
    defaultConfig: defaultConfig, defaultCards: defaultCards, defaultState: defaultState,
    parseCards: parseCards, parseConfig: parseConfig, parseState: parseState,
    findCard: findCard, dueQuizzes: dueQuizzes, unseenLessons: unseenLessons, topDue: topDue,
    buildChoices: buildChoices,
    grade: grade, gradeCard: gradeCard,
    dateKey: dateKey, prevDateKey: prevDateKey, rollDaily: rollDaily,
    nextIntervalMs: nextIntervalMs, decide: decide,
    addQuizCard: addQuizCard, addLessonCard: addLessonCard, dropCard: dropCard, markLessonSeen: markLessonSeen,
    triviaSeedCards: triviaSeedCards, mergeCards: mergeCards,
    stats: stats, formatDue: formatDue,
  }
}
