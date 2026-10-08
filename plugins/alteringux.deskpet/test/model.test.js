"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const MIN = 60_000
const HOUR = 60 * MIN

function state(over) {
  return Object.assign(Model.defaultState(), over || {})
}

// ── catalogue ────────────────────────────────────────────────────────────

test("catalogue: exactly 13 pets, all with distinct ids and full phrase banks", () => {
  assert.equal(Model.PETS.length, 13)
  const ids = Model.PETS.map((p) => p.id)
  assert.equal(new Set(ids).size, 13)
  for (const pet of Model.PETS) {
    assert.ok(pet.glyph && pet.glyph.length > 0, pet.id + " glyph")
    assert.ok(pet.tagline && pet.tagline.length > 0, pet.id + " tagline")
    assert.ok(typeof pet.voice === "function", pet.id + " voice")
    assert.ok(pet.greet.length >= 2, pet.id + " greet")
    assert.ok(pet.poke.length >= 2, pet.id + " poke")
    assert.ok(pet.feed.length >= 1, pet.id + " feed")
    assert.ok(pet.play.length >= 1, pet.id + " play")
    assert.ok(pet.sleepy && pet.wake && pet.lowBattery && pet.longIdle && pet.milestone, pet.id + " singleton lines")
  }
})

test("petById: unknown id falls back to the first pet, never throws", () => {
  assert.equal(Model.petById("nope").id, Model.PETS[0].id)
  assert.equal(Model.petById(undefined).id, Model.PETS[0].id)
})

test("nextPetId / prevPetId wrap around the catalogue", () => {
  const first = Model.PETS[0].id
  const last = Model.PETS[Model.PETS.length - 1].id
  assert.equal(Model.prevPetId(first), last)
  assert.equal(Model.nextPetId(last), first)
  assert.equal(Model.nextPetId(first), Model.PETS[1].id)
})

// ── parsing ──────────────────────────────────────────────────────────────

test("parseState: missing state -> healthy defaults, malformed state -> disabled", () => {
  const d = Model.defaultState()
  const empty = Model.parseState("")
  for (const key of Object.keys(d)) {
    if (["lastTickMs", "lastInteractionMs", "bornMs"].includes(key)) {
      assert.equal(typeof empty[key], "number", key)
    } else {
      assert.deepEqual(empty[key], d[key], key)
    }
  }
  for (const raw of ["not json", "[1,2,3]", "null", "{}", JSON.stringify({ energy: "oops" }), JSON.stringify({ energy: null })]) {
    assert.equal(Model.parseState(raw).enabled, false, raw)
  }
})

test("parseState: adopts known keys, clamps stats, ignores unknown pet id", () => {
  const raw = JSON.stringify({
    petId: "fox", happiness: 500, fullness: -20, energy: 50, muted: true, bogus: "x"
  })
  const s = Model.parseState(raw)
  assert.equal(s.petId, "fox")
  assert.equal(s.happiness, 100)
  assert.equal(s.fullness, 0)
  assert.equal(s.energy, 50)
  assert.equal(s.muted, true)
  assert.equal(s.bogus, undefined)
})

test("parseState: unknown petId keeps the default pet, not the garbage id", () => {
  const s = Model.parseState(JSON.stringify({ petId: "velociraptor" }))
  assert.equal(s.petId, Model.defaultState().petId)
})

// ── decay ────────────────────────────────────────────────────────────────

test("applyDecay: no elapsed time is a no-op", () => {
  const s = state({ lastTickMs: 1000 })
  const next = Model.applyDecay(s, 1000)
  assert.equal(next, s)
})

test("applyDecay: stats drain over elapsed hours and clamp at 0", () => {
  const s = state({ happiness: 10, fullness: 10, energy: 100, lastTickMs: 0, manualSleep: false })
  const next = Model.applyDecay(s, 3 * HOUR)
  assert.equal(next.happiness, 0)   // 10 - 6*3 clamps to 0
  assert.equal(next.fullness, 0)    // 10 - 9*3 clamps to 0
  assert.ok(next.energy < 100 && next.energy > 0)
})

test("applyDecay: asleep pets recover energy instead of draining", () => {
  const s = state({ energy: 20, manualSleep: true, lastTickMs: 0 })
  const next = Model.applyDecay(s, 1 * HOUR)
  assert.ok(next.energy > 20)
  assert.equal(next.asleep, true)
})

test("applyDecay: energy dropping to <=15 sets asleep automatically", () => {
  // A modest step that just crosses the threshold (17 -> 14.5 at 5/hr over
  // 30 min), not a multi-hour jump that would overshoot into recovery.
  const s = state({ energy: 17, manualSleep: false, lastTickMs: 0 })
  const next = Model.applyDecay(s, 30 * MIN)
  assert.ok(next.energy <= 15)
  assert.equal(next.asleep, true)
})

// ── interactions ─────────────────────────────────────────────────────────

test("feed: raises fullness and happiness, records the timestamp and count", () => {
  const s = state({ fullness: 50, happiness: 50, lastTickMs: 0, totalFeeds: 2 })
  const next = Model.feed(s, 0)
  assert.equal(next.fullness, 80)
  assert.equal(next.happiness, 55)
  assert.equal(next.lastFedMs, 0)
  assert.equal(next.totalFeeds, 3)
})

test("feed and play clamp at 100 even when nearly full", () => {
  const s = state({ fullness: 95, happiness: 95, lastTickMs: 0 })
  const fed = Model.feed(s, 0)
  assert.equal(fed.fullness, 100)
  const played = Model.play(fed, 0)
  assert.equal(played.happiness, 100)
})

test("feed: streak continues within the window, resets after it lapses", () => {
  let s = state({ lastTickMs: 0, feedStreak: 0, feedStreakAt: 0 })
  s = Model.feed(s, 0)
  assert.equal(s.feedStreak, 1)
  s = Model.feed(s, 1000) // within FEED_STREAK_WINDOW_MS
  assert.equal(s.feedStreak, 2)
  s = Model.feed(s, 1000 + Model.FEED_STREAK_WINDOW_MS + 1) // lapsed
  assert.equal(s.feedStreak, 1)
})

test("isFeedCombo: true once the streak reaches FEED_STREAK_COMBO, stays true after", () => {
  assert.equal(Model.isFeedCombo({ feedStreak: Model.FEED_STREAK_COMBO - 1 }), false)
  assert.equal(Model.isFeedCombo({ feedStreak: Model.FEED_STREAK_COMBO }), true)
  assert.equal(Model.isFeedCombo({ feedStreak: Model.FEED_STREAK_COMBO + 5 }), true)
  assert.equal(Model.isFeedCombo({ feedStreak: 0 }), false)
})

test("pickFeedLine: returns the combo line once the feed streak hits the threshold", () => {
  const pet = Model.petById("cat")
  const combo = state({ feedStreak: Model.FEED_STREAK_COMBO })
  assert.equal(Model.pickFeedLine(pet, 0, combo), Model.pickFeedComboLine(pet, combo.feedStreak))
  const normal = state({ feedStreak: 1 })
  assert.equal(Model.pickFeedLine(pet, 0, normal), pet.feed[0])
})

test("pickFeedComboLine: interpolates the count and rides the pet's voice", () => {
  const pet = Model.petById("robot")
  const line = Model.pickFeedComboLine(pet, 4)
  assert.ok(line.includes("4"))
  assert.equal(line, pet.voice(Model.FEED_COMBO_LINE.replace("{count}", 4)))
})

test("play: raises happiness, costs energy, records count", () => {
  const s = state({ happiness: 50, energy: 50, lastTickMs: 0, totalPlays: 0 })
  const next = Model.play(s, 0)
  assert.equal(next.happiness, 65)
  assert.equal(next.energy, 42)
  assert.equal(next.totalPlays, 1)
})

test("poke: streak continues within the window, resets after it lapses", () => {
  let s = state({ lastTickMs: 0, pokeStreak: 0, pokeStreakAt: 0 })
  s = Model.poke(s, 0)
  assert.equal(s.pokeStreak, 1)
  s = Model.poke(s, 1000) // within POKE_STREAK_WINDOW_MS
  assert.equal(s.pokeStreak, 2)
  s = Model.poke(s, 1000 + Model.POKE_STREAK_WINDOW_MS + 1) // lapsed
  assert.equal(s.pokeStreak, 1)
})

test("poke: increments totalPokes and nudges happiness up", () => {
  const s = state({ happiness: 50, totalPokes: 4, lastTickMs: 0 })
  const next = Model.poke(s, 0)
  assert.equal(next.totalPokes, 5)
  assert.equal(next.happiness, 54)
})

test("isAnnoyedPoke: fires every POKE_STREAK_ANNOY-th poke in a streak", () => {
  assert.equal(Model.isAnnoyedPoke({ pokeStreak: Model.POKE_STREAK_ANNOY }), true)
  assert.equal(Model.isAnnoyedPoke({ pokeStreak: Model.POKE_STREAK_ANNOY - 1 }), false)
  assert.equal(Model.isAnnoyedPoke({ pokeStreak: 0 }), false)
})

test("withInteraction / feed / play wake a sleeping pet unless it's manually asleep", () => {
  const asleep = state({ asleep: true, manualSleep: false, energy: 50 })
  const poked = Model.poke(asleep, 0)
  assert.equal(poked.asleep, false)

  const manual = state({ asleep: true, manualSleep: true, energy: 50 })
  const stillAsleep = Model.poke(manual, 0)
  assert.equal(stillAsleep.asleep, true)
})

test("setSleep: manual toggle overrides energy-based asleep state", () => {
  const s = state({ energy: 90 })
  const asleep = Model.setSleep(s, true)
  assert.equal(asleep.asleep, true)
  const awake = Model.setSleep(asleep, false)
  assert.equal(awake.asleep, false) // energy is high, so waking sticks
})

test("setSleep: an explicit wake rouses an energy-exhausted pet", () => {
  // Regression: energy <= 15 used to pin asleep=true through a manual wake,
  // and nothing the user could do restored energy fast enough.
  const drained = state({ energy: 3, manualSleep: false, asleep: true })
  const awake = Model.setSleep(drained, false)
  assert.equal(awake.asleep, false)
  assert.ok(awake.energy > 15, "wake lifts energy clear of the sleep threshold")
  assert.equal(awake.manualSleep, false)
})

test("selectPet: rejects an unknown id, keeps the current pet", () => {
  const s = state({ petId: "cat" })
  assert.equal(Model.selectPet(s, "dog").petId, "dog")
  assert.equal(Model.selectPet(s, "not-a-pet").petId, "cat")
})

test("setPosition: clamps fractions into [0,1]", () => {
  const next = Model.setPosition(state(), 1.5, -0.5)
  assert.equal(next.posFracX, 1)
  assert.equal(next.posFracY, 0)
})

// ── age-up ─────────────────────────────────────────────────────────────────

test("ageUp: a no-op below AGE_UP_POKE_THRESHOLD", () => {
  const s = state({ totalPokes: Model.AGE_UP_POKE_THRESHOLD - 1, agedUp: false, accessoryId: null })
  const next = Model.ageUp(s)
  assert.equal(next.agedUp, false)
  assert.equal(next.accessoryId, null)
})

test("ageUp: crossing the threshold marks it aged and equips the top hat", () => {
  const s = state({ totalPokes: Model.AGE_UP_POKE_THRESHOLD, agedUp: false, accessoryId: null })
  const next = Model.ageUp(s)
  assert.equal(next.agedUp, true)
  assert.equal(next.accessoryId, "top_hat")
})

test("ageUp: idempotent, and never re-equips over a user-chosen accessory", () => {
  // Already aged, and the user later picked a different hat -- ageUp must not touch it.
  const already = state({ totalPokes: Model.AGE_UP_POKE_THRESHOLD + 5, agedUp: true, accessoryId: "crown" })
  const next = Model.ageUp(already)
  assert.equal(next.agedUp, true)
  assert.equal(next.accessoryId, "crown")
})

test("ageUp: returns a new object and never mutates its input", () => {
  const s = state({ totalPokes: Model.AGE_UP_POKE_THRESHOLD, agedUp: false, accessoryId: null })
  const next = Model.ageUp(s)
  assert.notEqual(next, s)
  assert.equal(s.agedUp, false)
  assert.equal(s.accessoryId, null)
})

test("poke: the 50th poke fires the age-up exactly once", () => {
  let s = state({ totalPokes: Model.AGE_UP_POKE_THRESHOLD - 1, agedUp: false, accessoryId: null, lastTickMs: 0 })
  s = Model.poke(s, 0) // the 50th poke
  assert.equal(s.totalPokes, Model.AGE_UP_POKE_THRESHOLD)
  assert.equal(s.agedUp, true)
  assert.equal(s.accessoryId, "top_hat")
  s = Model.poke(s, Model.POKE_STREAK_WINDOW_MS + 1) // a further poke must not re-fire
  assert.equal(s.agedUp, true)
  assert.equal(s.accessoryId, "top_hat")
})

test("pickAgeUpLine: wraps AGE_UP_LINE in the pet's own voice()", () => {
  const pet = Model.petById("cat")
  assert.equal(Model.pickAgeUpLine(pet), pet.voice(Model.AGE_UP_LINE))
})

test("ageUp: a no-op below AGE_UP2_POKE_THRESHOLD when already aged", () => {
  const s = state({ totalPokes: Model.AGE_UP2_POKE_THRESHOLD - 1, agedUp: true, accessoryId: "top_hat" })
  const next = Model.ageUp(s)
  assert.equal(next.agedUp2, false)
  assert.equal(next.accessoryId, "top_hat")
})

test("ageUp: crossing the second threshold marks it twice-aged and equips the halo", () => {
  const s = state({ totalPokes: Model.AGE_UP2_POKE_THRESHOLD, agedUp: true, accessoryId: "top_hat" })
  const next = Model.ageUp(s)
  assert.equal(next.agedUp2, true)
  assert.equal(next.accessoryId, "halo")
})

test("ageUp: the second stage is idempotent, and never re-equips over a user-chosen accessory", () => {
  const already = state({ totalPokes: Model.AGE_UP2_POKE_THRESHOLD + 5, agedUp: true, agedUp2: true, accessoryId: "crown" })
  const next = Model.ageUp(already)
  assert.equal(next.agedUp2, true)
  assert.equal(next.accessoryId, "crown")
})

test("ageUp: when both thresholds cross in one poke, the second stage wins", () => {
  const s = state({ totalPokes: Model.AGE_UP2_POKE_THRESHOLD, agedUp: false, accessoryId: null })
  const next = Model.ageUp(s)
  assert.equal(next.agedUp, true)
  assert.equal(next.agedUp2, true)
  assert.equal(next.accessoryId, "halo")
})

test("poke: the 500th poke fires the second age-up exactly once", () => {
  let s = state({ totalPokes: Model.AGE_UP2_POKE_THRESHOLD - 1, agedUp: true, agedUp2: false, accessoryId: "top_hat", lastTickMs: 0 })
  s = Model.poke(s, 0) // the 500th poke
  assert.equal(s.totalPokes, Model.AGE_UP2_POKE_THRESHOLD)
  assert.equal(s.agedUp2, true)
  assert.equal(s.accessoryId, "halo")
  s = Model.poke(s, Model.POKE_STREAK_WINDOW_MS + 1) // a further poke must not re-fire
  assert.equal(s.agedUp2, true)
  assert.equal(s.accessoryId, "halo")
})

test("pickAgeUp2Line: wraps AGE_UP2_LINE in the pet's own voice()", () => {
  const pet = Model.petById("cat")
  assert.equal(Model.pickAgeUp2Line(pet), pet.voice(Model.AGE_UP2_LINE))
})

// ── mood / stats ─────────────────────────────────────────────────────────

test("moodLabel: asleep beats every other signal", () => {
  assert.equal(Model.moodLabel(state({ asleep: true, happiness: 100, fullness: 100 })), "asleep")
})

test("moodLabel: hungry beats grumpy when fullness is critical", () => {
  assert.equal(Model.moodLabel(state({ fullness: 10, happiness: 10 })), "hungry")
})

test("moodLabel: ecstatic requires both happiness and fullness to be high", () => {
  assert.equal(Model.moodLabel(state({ happiness: 90, fullness: 90 })), "ecstatic")
  assert.equal(Model.moodLabel(state({ happiness: 90, fullness: 55 })), "content")
})

test("moodFace: one face per mood, blank for asleep and unknown", () => {
  assert.equal(Model.moodFace("ecstatic"), "󰱱")
  assert.equal(Model.moodFace("content"), "󰱱")
  assert.equal(Model.moodFace("meh"), "󰱴")
  assert.equal(Model.moodFace("hungry"), "󰇹")
  assert.equal(Model.moodFace("grumpy"), "󰱶")
  assert.equal(Model.moodFace("asleep"), "")
  assert.equal(Model.moodFace("nonsense"), "")
})

test("ageDays / minutesIdle compute from the reference clock, never negative", () => {
  const s = state({ bornMs: 0, lastInteractionMs: 0 })
  assert.equal(Model.ageDays(s, 3 * 24 * HOUR), 3)
  assert.equal(Model.minutesIdle(s, 10 * MIN), 10)
  assert.equal(Model.ageDays(s, -1000), 0)
})

// ── phrase pickers ───────────────────────────────────────────────────────

test("pickGreeting / pickFeedLine / pickPlayLine: seeded picks are deterministic and in-bank", () => {
  const pet = Model.petById("cat")
  const line = Model.pickGreeting(pet, 0)
  assert.ok(pet.greet.includes(line))
  assert.equal(Model.pickFeedLine(pet, 0), pet.feed[0])
  assert.equal(Model.pickPlayLine(pet, 0), pet.play[0])
})

test("pickPokeLine: returns the milestone line on an annoyed streak, else a poke line", () => {
  const pet = Model.petById("dog")
  const annoyed = state({ pokeStreak: Model.POKE_STREAK_ANNOY })
  assert.equal(Model.pickPokeLine(pet, annoyed, 0), pet.milestone)
  const normal = state({ pokeStreak: 1 })
  assert.ok(pet.poke.includes(Model.pickPokeLine(pet, normal, 0)))
})

test("pickAmbientLine: low battery takes priority over everything else", () => {
  const pet = Model.petById("robot")
  const line = Model.pickAmbientLine(pet, { isLowBattery: true, minutesIdleValue: 999, moodLabelValue: "hungry" }, 0)
  assert.equal(line, pet.lowBattery)
})

test("pickAmbientLine: long idle beats mood when battery is fine", () => {
  const pet = Model.petById("owl")
  const line = Model.pickAmbientLine(pet, { isLowBattery: false, minutesIdleValue: 45, moodLabelValue: "grumpy" }, 0)
  assert.equal(line, pet.longIdle)
})

test("pickAmbientLine: falls back to a voiced generic tip when nothing else applies", () => {
  const pet = Model.petById("frog")
  const line = Model.pickAmbientLine(pet, { isLowBattery: false, minutesIdleValue: 2, moodLabelValue: "content" }, 0)
  assert.equal(line, pet.voice(Model.CLIPPY_TIPS[0]))
})

// ── time-of-day chatter ────────────────────────────────────────────────────

test("timePeriod: maps hours to the four buckets", () => {
  assert.equal(Model.timePeriod(5), "morning")
  assert.equal(Model.timePeriod(11), "morning")
  assert.equal(Model.timePeriod(12), "afternoon")
  assert.equal(Model.timePeriod(16), "afternoon")
  assert.equal(Model.timePeriod(17), "evening")
  assert.equal(Model.timePeriod(21), "evening")
  assert.equal(Model.timePeriod(22), "lateNight")
  assert.equal(Model.timePeriod(23), "lateNight")
  assert.equal(Model.timePeriod(0), "lateNight")
  assert.equal(Model.timePeriod(4), "lateNight")
})

test("timePeriod: rejects missing and out-of-range hours", () => {
  assert.equal(Model.timePeriod(24), null)
  assert.equal(Model.timePeriod(-1), null)
  assert.equal(Model.timePeriod(undefined), null)
  assert.equal(Model.timePeriod(NaN), null)
})

test("pickTimeLine: seeded and in-bank, empty for a missing hour", () => {
  assert.equal(Model.pickTimeLine(9, 0), Model.TIME_LINES.morning[0])
  assert.equal(Model.pickTimeLine(14, 3), Model.TIME_LINES.afternoon[3])
  assert.equal(Model.pickTimeLine(19, 4), Model.TIME_LINES.evening[4])
  assert.equal(Model.pickTimeLine(23, 1), Model.TIME_LINES.lateNight[1])
  assert.equal(Model.pickTimeLine(undefined, 0), "")
  assert.equal(Model.pickTimeLine(25, 0), "")
})

test("pickAmbientLine: the time branch fires for a third of seeds, voiced by the pet", () => {
  const pet = Model.petById("cat")
  const ctx = { isLowBattery: false, minutesIdleValue: 2, moodLabelValue: "content", hourValue: 9 }
  assert.equal(Model.pickAmbientLine(pet, ctx, 0), pet.voice(Model.TIME_LINES.morning[0]))
  // 300 % 1000 is not < 300 -> generic tip even with a valid hour
  assert.equal(Model.pickAmbientLine(pet, ctx, 300), pet.voice(Model.CLIPPY_TIPS[300 % Model.CLIPPY_TIPS.length]))
  // time-branch seed but no hour -> falls through to the generic tip
  assert.equal(Model.pickAmbientLine(pet, Object.assign({}, ctx, { hourValue: undefined }), 0), pet.voice(Model.CLIPPY_TIPS[0]))
})

test("pickAmbientLine: battery, idle, and mood still outrank the time branch", () => {
  const pet = Model.petById("robot")
  const base = { isLowBattery: false, minutesIdleValue: 2, moodLabelValue: "content", hourValue: 9 }
  assert.equal(Model.pickAmbientLine(pet, Object.assign({}, base, { isLowBattery: true }), 0), pet.lowBattery)
  assert.equal(Model.pickAmbientLine(pet, Object.assign({}, base, { minutesIdleValue: 45 }), 0), pet.longIdle)
  assert.equal(Model.pickAmbientLine(pet, Object.assign({}, base, { moodLabelValue: "grumpy" }), 0), pet.voice("Not feeling it today. A pat might help."))
})

// ── seasonal events ───────────────────────────────────────────────────────

test("seasonalEvent: returns the right event for each holiday date", () => {
  assert.equal(Model.seasonalEvent(1, 1).id, "new_year")
  assert.equal(Model.seasonalEvent(2, 14).id, "valentines")
  assert.equal(Model.seasonalEvent(10, 31).id, "halloween")
  assert.equal(Model.seasonalEvent(12, 25).id, "christmas")
})

test("seasonalEvent: null for a non-holiday date and for missing/invalid input", () => {
  assert.equal(Model.seasonalEvent(7, 4), null)
  assert.equal(Model.seasonalEvent(3, 15), null)
  assert.equal(Model.seasonalEvent(undefined, undefined), null)
  assert.equal(Model.seasonalEvent(NaN, NaN), null)
  assert.equal(Model.seasonalEvent(0, 0), null)
})

test("pickSeasonalLine: voiced and in-bank on a holiday, empty otherwise", () => {
  const pet = Model.petById("cat")
  const line = Model.pickSeasonalLine(pet, 12, 25, 0)
  assert.equal(line, pet.voice(Model.SEASONAL_LINES.christmas[0]))
  assert.equal(Model.pickSeasonalLine(pet, 7, 4, 0), "")
  assert.equal(Model.pickSeasonalLine(pet, undefined, undefined, 0), "")
})

test("pickAmbientLine: seasonal branch fires for half the seeds when a holiday is active", () => {
  const pet = Model.petById("cat")
  const ctx = { isLowBattery: false, minutesIdleValue: 2, moodLabelValue: "content", hourValue: 9, monthValue: 12, dayValue: 25 }
  assert.equal(Model.pickAmbientLine(pet, ctx, 0), pet.voice(Model.SEASONAL_LINES.christmas[0]))
  assert.equal(Model.pickAmbientLine(pet, ctx, 499), pet.voice(Model.SEASONAL_LINES.christmas[499 % Model.SEASONAL_LINES.christmas.length]))
  assert.equal(Model.pickAmbientLine(pet, ctx, 500), pet.voice(Model.CLIPPY_TIPS[500 % Model.CLIPPY_TIPS.length]))
})

test("pickAmbientLine: no seasonal event -> time-of-day and generic tips behave as before", () => {
  const pet = Model.petById("cat")
  const ctx = { isLowBattery: false, minutesIdleValue: 2, moodLabelValue: "content", hourValue: 9, monthValue: 7, dayValue: 4 }
  assert.equal(Model.pickAmbientLine(pet, ctx, 0), pet.voice(Model.TIME_LINES.morning[0]))
  assert.equal(Model.pickAmbientLine(pet, ctx, 400), pet.voice(Model.CLIPPY_TIPS[400 % Model.CLIPPY_TIPS.length]))
})

test("pickAmbientLine: battery, idle, and mood still outrank the seasonal branch", () => {
  const pet = Model.petById("robot")
  const base = { isLowBattery: false, minutesIdleValue: 2, moodLabelValue: "content", hourValue: 9, monthValue: 12, dayValue: 25 }
  assert.equal(Model.pickAmbientLine(pet, Object.assign({}, base, { isLowBattery: true }), 0), pet.lowBattery)
  assert.equal(Model.pickAmbientLine(pet, Object.assign({}, base, { minutesIdleValue: 45 }), 0), pet.longIdle)
  assert.equal(Model.pickAmbientLine(pet, Object.assign({}, base, { moodLabelValue: "grumpy" }), 0), pet.voice("Not feeling it today. A pat might help."))
})

test("pickZoomLine: comes from the shared pool, wrapped in the pet's own voice()", () => {
  const fox = Model.petById("fox")
  const line = Model.pickZoomLine(fox, 0)
  assert.ok(Model.ZOOM_LINES.some((z) => line === fox.voice(z)), "wrapped zoom line matches one entry")
})

test("sleepyLine / wakeLine return the pet's own singleton lines", () => {
  const pet = Model.petById("penguin")
  assert.equal(Model.sleepyLine(pet), pet.sleepy)
  assert.equal(Model.wakeLine(pet), pet.wake)
})

// ── achievements ───────────────────────────────────────────────────────────

test("ACHIEVEMENTS: every description that names a threshold has it interpolated, not undefined", () => {
  for (const a of Model.ACHIEVEMENTS) {
    assert.doesNotMatch(a.description, /undefined/, a.id)
    assert.doesNotMatch(a.name, /undefined/, a.id)
  }
})

test("unlockedAchievementIds: empty for a fresh pet, grows monotonically with counters", () => {
  // night_owl reads the persisted nightOwlEver flag (false by default here),
  // not the wall-clock hour, so this no longer depends on what time it runs.
  const fresh = state({ totalPokes: 0, totalFeeds: 0, totalPlays: 0, pokeStreak: 0, bornMs: 0 })
  assert.deepEqual(Model.unlockedAchievementIds(fresh, 0), [])

  const oneOfEach = state({ totalPokes: 1, totalFeeds: 1, totalPlays: 1, bornMs: 0 })
  const ids = Model.unlockedAchievementIds(oneOfEach, 0)
  assert.ok(ids.includes("first_pet"))
  assert.ok(ids.includes("first_feed"))
  assert.ok(ids.includes("first_play"))
  assert.ok(!ids.includes("pat_pat_pat")) // needs 50, not 1
})

test("night_owl: sticks once earned instead of flipping back with the wall-clock hour", () => {
  const nightHour = new Date(2026, 0, 1, 3, 0, 0).getTime()  // 3am
  const dayHour = new Date(2026, 0, 1, 14, 0, 0).getTime()   // 2pm

  const awake = state({ nightOwlEver: false })
  assert.ok(!Model.unlockedAchievementIds(awake, dayHour).includes("night_owl"))

  const afterNightPoke = Model.poke(awake, nightHour)
  assert.equal(afterNightPoke.nightOwlEver, true)
  assert.ok(Model.unlockedAchievementIds(afterNightPoke, nightHour).includes("night_owl"))

  // A later daytime interaction must not clear the flag already earned.
  const afterDayPoke = Model.poke(afterNightPoke, dayHour)
  assert.equal(afterDayPoke.nightOwlEver, true)
  assert.ok(Model.unlockedAchievementIds(afterDayPoke, dayHour).includes("night_owl"))
})

test("newlyUnlocked: reports only what crossed the line between prev and next", () => {
  const prev = state({ totalPokes: 0 })
  const next = state({ totalPokes: 1 })
  const unlocked = Model.newlyUnlocked(prev, next, 0)
  assert.equal(unlocked.length, 1)
  assert.equal(unlocked[0].id, "first_pet")

  // No change -> nothing newly unlocked, even though first_pet stays unlocked.
  assert.deepEqual(Model.newlyUnlocked(next, next, 0), [])
})

test("newlyUnlocked: age-based achievements use the same nowMs for both sides", () => {
  const s = state({ bornMs: 0 })
  // At day 3 exactly, "dedicated" is unlocked on both sides -> not newly unlocked.
  assert.deepEqual(Model.newlyUnlocked(s, s, 3 * 24 * HOUR), [])
})

test("dedicated / best_friend: unlock at 3 and 7 days respectively", () => {
  const s = state({ bornMs: 0 })
  assert.ok(!Model.unlockedAchievementIds(s, 2 * 24 * HOUR).includes("dedicated"))
  assert.ok(Model.unlockedAchievementIds(s, 3 * 24 * HOUR).includes("dedicated"))
  assert.ok(!Model.unlockedAchievementIds(s, 6 * 24 * HOUR).includes("best_friend"))
  assert.ok(Model.unlockedAchievementIds(s, 7 * 24 * HOUR).includes("best_friend"))
})

// ── leveling ───────────────────────────────────────────────────────────────

test("levelInfo: level 1 with no interactions, rises with the interaction total", () => {
  const l0 = Model.levelInfo(state({ totalPokes: 0, totalFeeds: 0, totalPlays: 0 }))
  assert.equal(l0.level, 1)
  assert.equal(l0.title, Model.LEVEL_TITLES[0])

  const l1 = Model.levelInfo(state({ totalPokes: 15, totalFeeds: 0, totalPlays: 0 }))
  assert.equal(l1.level, 2)
  assert.equal(l1.title, Model.LEVEL_TITLES[1])
})

test("levelInfo: caps its title at the last tier past the title list length", () => {
  const huge = Model.levelInfo(state({ totalPokes: 100000, totalFeeds: 0, totalPlays: 0 }))
  assert.equal(huge.title, Model.LEVEL_TITLES[Model.LEVEL_TITLES.length - 1])
})

test("didLevelUp: true only when the derived level actually crosses a threshold", () => {
  assert.equal(Model.didLevelUp(state({ totalPokes: 14 }), state({ totalPokes: 15 })), true)
  assert.equal(Model.didLevelUp(state({ totalPokes: 14 }), state({ totalPokes: 14 })), false)
  assert.equal(Model.didLevelUp(state({ totalPokes: 15 }), state({ totalPokes: 16 })), false)
})

test("didLevelUp: feeds and plays count toward the level too", () => {
  assert.equal(Model.didLevelUp(state({ totalPokes: 10, totalFeeds: 4 }), state({ totalPokes: 10, totalFeeds: 5 })), true)
  assert.equal(Model.didLevelUp(state({ totalFeeds: 29 }), state({ totalFeeds: 29, totalPlays: 1 })), true)
})

test("pickLevelUpLine: interpolates level and title, wrapped in the pet's voice", () => {
  const pet = Model.petById("cat")
  const expected = Model.LEVEL_UP_LINE.replace("{level}", "2").replace("{title}", Model.LEVEL_TITLES[1])
  assert.equal(Model.pickLevelUpLine(pet, 2), pet.voice(expected))
})

test("pickLevelUpLine: clamps missing or zero levels to 1", () => {
  const pet = Model.petById("cat")
  const level1 = pet.voice(Model.LEVEL_UP_LINE.replace("{level}", "1").replace("{title}", Model.LEVEL_TITLES[0]))
  assert.equal(Model.pickLevelUpLine(pet, 0), level1)
  assert.equal(Model.pickLevelUpLine(pet, undefined), level1)
})

test("pickLevelUpLine: caps the title at the last one for huge levels", () => {
  const pet = Model.petById("cat")
  const last = Model.LEVEL_TITLES[Model.LEVEL_TITLES.length - 1]
  const expected = Model.LEVEL_UP_LINE.replace("{level}", "999").replace("{title}", last)
  assert.equal(Model.pickLevelUpLine(pet, 999), pet.voice(expected))
})

// ── wardrobe ───────────────────────────────────────────────────────────────

test("isAccessoryUnlocked: false for an unknown id, false until its achievement unlocks", () => {
  assert.equal(Model.isAccessoryUnlocked("not-a-real-accessory", state(), 0), false)
  const locked = state({ totalPokes: 0 })
  assert.equal(Model.isAccessoryUnlocked("sunglasses", locked, 0), false) // needs pat_pat_pat (50 pokes)
  const unlocked = state({ totalPokes: 50 })
  assert.equal(Model.isAccessoryUnlocked("sunglasses", unlocked, 0), true)
})

test("equipAccessory: refuses a locked accessory, allows unequipping with null", () => {
  const locked = state({ totalPokes: 0 })
  const stillNone = Model.equipAccessory(locked, "sunglasses", 0)
  assert.equal(stillNone.accessoryId, null)

  const unlocked = state({ totalPokes: 50 })
  const equipped = Model.equipAccessory(unlocked, "sunglasses", 0)
  assert.equal(equipped.accessoryId, "sunglasses")

  const unequipped = Model.equipAccessory(equipped, null, 0)
  assert.equal(unequipped.accessoryId, null)
})

// ── shiny ──────────────────────────────────────────────────────────────────

test("rollShiny: seeded rolls are deterministic and threshold-correct", () => {
  assert.equal(Model.rollShiny(0), true)     // r = 0    < 0.05
  assert.equal(Model.rollShiny(49), true)    // r = 0.049 < 0.05
  assert.equal(Model.rollShiny(50), false)   // r = 0.05, not < 0.05
  assert.equal(Model.rollShiny(500), false)  // r = 0.5
})

test("selectPet: rerolls shiny only when actually switching to a different pet", () => {
  const s = state({ petId: "cat", shiny: true })
  // Reselecting the same pet must not reroll (and must not clear shiny).
  const same = Model.selectPet(s, "cat", 500)
  assert.equal(same.shiny, true)

  const switched = Model.selectPet(s, "dog", 500) // r = 0.5 -> not shiny
  assert.equal(switched.petId, "dog")
  assert.equal(switched.shiny, false)

  const switchedLucky = Model.selectPet(s, "fox", 0) // r = 0 -> shiny
  assert.equal(switchedLucky.shiny, true)
})

test("pickShinyLine: comes from the pet's own voice() wrapper", () => {
  const pet = Model.petById("robot")
  assert.equal(Model.pickShinyLine(pet), pet.voice("You caught the SHINY version of me. Incredible luck."))
})

// ── new state fields survive parsing ────────────────────────────────────────

test("parseState: adopts shiny and a known accessoryId, rejects an unknown one", () => {
  const s1 = Model.parseState(JSON.stringify({ shiny: true, accessoryId: "crown" }))
  assert.equal(s1.shiny, true)
  assert.equal(s1.accessoryId, "crown")

  const s2 = Model.parseState(JSON.stringify({ accessoryId: "not-a-real-accessory" }))
  assert.equal(s2.accessoryId, null) // falls back to the default, not the garbage id

  const s3 = Model.parseState(JSON.stringify({ accessoryId: null }))
  assert.equal(s3.accessoryId, null)
})

test("parseState: screenWatchEnabled defaults off, screenLookFreqMin clamps to [5, 180]", () => {
  assert.equal(Model.defaultState().screenWatchEnabled, false)

  const s1 = Model.parseState(JSON.stringify({ screenWatchEnabled: true, screenLookFreqMin: 1000 }))
  assert.equal(s1.screenWatchEnabled, true)
  assert.equal(s1.screenLookFreqMin, 180)

  const s2 = Model.parseState(JSON.stringify({ screenLookFreqMin: 0 }))
  assert.equal(s2.screenLookFreqMin, Model.defaultState().screenLookFreqMin) // 0 is falsy, ignored not clamped
})

test("parseState: roamMode defaults to off, only accepts a known mode", () => {
  assert.equal(Model.defaultState().roamMode, "off")
  assert.equal(Model.parseState(JSON.stringify({ roamMode: "gallop" })).roamMode, "gallop")
  assert.equal(Model.parseState(JSON.stringify({ roamMode: "sprint" })).roamMode, "off") // unknown -> default
})

// ── screen-look system prompt ────────────────────────────────────────────

test("screenLookSystemPrompt: every pet produces a non-throwing prompt naming itself", () => {
  for (const pet of Model.PETS) {
    const prompt = Model.screenLookSystemPrompt(pet)
    assert.ok(prompt.includes(pet.name), pet.id + " prompt names itself")
    assert.ok(prompt.includes(pet.tagline), pet.id + " prompt includes its tagline")
    assert.ok(prompt.length > 0 && prompt.length < 2000, pet.id + " prompt is a reasonable size")
  }
})
