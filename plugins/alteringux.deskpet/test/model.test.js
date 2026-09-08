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

test("parseState: empty / garbage / non-object -> defaults", () => {
  // defaultState() stamps Date.now() into a few fields, so compare structure
  // (keys + non-timestamp values) rather than a wall-clock-sensitive deepEqual.
  const d = Model.defaultState()
  const timestampKeys = new Set(["lastTickMs", "lastInteractionMs", "bornMs"])
  for (const raw of ["", "not json", "[1,2,3]", "null"]) {
    const s = Model.parseState(raw)
    assert.deepEqual(Object.keys(s).sort(), Object.keys(d).sort(), raw)
    for (const key of Object.keys(d)) {
      if (timestampKeys.has(key)) { assert.equal(typeof s[key], "number", key); continue }
      assert.deepEqual(s[key], d[key], key)
    }
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
  assert.equal(Model.moodFace("ecstatic"), "🙂")
  assert.equal(Model.moodFace("content"), "🙂")
  assert.equal(Model.moodFace("meh"), "😐")
  assert.equal(Model.moodFace("hungry"), "😋")
  assert.equal(Model.moodFace("grumpy"), "🙁")
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
  // Pin lastInteractionMs to a fixed daytime moment -- night_owl's check reads
  // the wall-clock hour, so leaving it defaulted to "now" would make this
  // test flaky depending on what time it happens to run.
  const noon = new Date(2026, 0, 1, 12, 0, 0).getTime()
  const fresh = state({ totalPokes: 0, totalFeeds: 0, totalPlays: 0, pokeStreak: 0, bornMs: 0, lastInteractionMs: noon })
  assert.deepEqual(Model.unlockedAchievementIds(fresh, 0), [])

  const oneOfEach = state({ totalPokes: 1, totalFeeds: 1, totalPlays: 1, bornMs: 0, lastInteractionMs: noon })
  const ids = Model.unlockedAchievementIds(oneOfEach, 0)
  assert.ok(ids.includes("first_pet"))
  assert.ok(ids.includes("first_feed"))
  assert.ok(ids.includes("first_play"))
  assert.ok(!ids.includes("pat_pat_pat")) // needs 50, not 1
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
