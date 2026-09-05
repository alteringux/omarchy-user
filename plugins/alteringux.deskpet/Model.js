"use strict"

// Pure logic for alteringux.deskpet: the pet catalogue, the Tamagotchi-ish
// mood/hunger/energy decay, and the Clippy-style phrase pickers. No QML here
// on purpose — this whole file is node --test able. BarWidget.qml owns the
// only Kit.Store that persists `state`; everything below is pure functions
// over plain objects.

var HOUR = 3600000
var MIN = 60000

// A poke within POKE_STREAK_WINDOW_MS of the last one continues the streak;
// otherwise it resets to 1. Declared up here (not just above poke()) because
// the ACHIEVEMENTS array literal below references POKE_STREAK_ANNOY at
// module-load time, before a later `var` assignment would have run.
var POKE_STREAK_WINDOW_MS = 4000
var POKE_STREAK_ANNOY = 6

// ── the catalogue ───────────────────────────────────────────────────────────
// Ten pets, each with a glyph, an accent tone (keyed to Kit.Palette), a short
// tagline shown under its name in the picker, and its own small phrase bank.
// `voice(line)` wraps a shared generic line in the pet's flavor so the shared
// tip pool (see CLIPPY_TIPS) reads differently per pet without hand-writing
// 10x as many lines.
var PETS = [
  {
    id: "cat", name: "Cat", glyph: "🐱", tone: "accent",
    tagline: "Judges your uptime.",
    voice: function (s) { return s + " ...obviously." },
    greet: ["*stretches and blinks at you.*", "Oh. It's you. Fine, I'm awake."],
    poke: ["*permits one (1) pat.*", "Hmph. Again? ...don't stop.", "*purrs, against its will.*"],
    feed: ["Acceptable.", "*inhales it instantly, pretends it didn't.*"],
    play: ["*bats at the cursor like it owes it money.*"],
    sleepy: "*curls into a tight loaf and closes its eyes.*",
    wake: "*one eye opens. Then the other, reluctantly.*",
    lowBattery: "Your laptop is as tired as I pretend not to be. Plug it in.",
    longIdle: "You've been gone a while. I did NOT miss you. (I missed you.)",
    milestone: "Okay, that's enough poking. I have a reputation."
  },
  {
    id: "dog", name: "Dog", glyph: "🐶", tone: "positive",
    tagline: "Hype-man for tiny wins.",
    voice: function (s) { return s + " Good job!! 🎉"; },
    greet: ["YOU'RE BACK. Best day ever.", "*tail is a blur.* Hi hi hi hi hi!"],
    poke: ["*leans entire body weight into your hand.*", "Pet me forever, please.", "This is the best thing that's happened all day."],
    feed: ["BEST SNACK EVER. Thank you thank you thank you."],
    play: ["*brings you a stick made of pure enthusiasm.*"],
    sleepy: "*flops over mid-sentence, already snoring.*",
    wake: "*ears perk up instantly, fully alert in 0.2 seconds.*",
    lowBattery: "Uh oh, low battery! Let's plug in together, I'll supervise.",
    longIdle: "I waited by the door the WHOLE time. Worth it, you're back.",
    milestone: "You keep petting me and I keep loving it, this is a great system."
  },
  {
    id: "fox", name: "Fox", glyph: "🦊", tone: "warning",
    tagline: "Knows a shortcut for that.",
    voice: function (s) { return "Psst — " + s.charAt(0).toLowerCase() + s.slice(1); },
    greet: ["*slinks out of the corner of the screen.* You rang?", "Well, well. Look who's back."],
    poke: ["*tilts head, calculating something.*", "Careful, I bite. Playfully. Mostly."],
    feed: ["*snatches it and vanishes for a second.* Mine now."],
    play: ["*does an unnecessarily elaborate pounce.*"],
    sleepy: "*curls tail over its nose and goes quiet.*",
    wake: "*ears swivel toward you before its eyes even open.*",
    lowBattery: "Battery's thin. A clever fox charges before the den goes dark.",
    longIdle: "Nobody around... perfect time to reorganize your desktop. (Kidding. Mostly.)",
    milestone: "A fox remembers every poke. This is the last one, I promise nothing."
  },
  {
    id: "panda", name: "Panda", glyph: "🐼", tone: "info",
    tagline: "Gently nags you to rest.",
    voice: function (s) { return s + " Take a breath while you're at it."; },
    greet: ["*rolls over slowly.* Oh, hello.", "Mm. You're here. Sit with me a sec."],
    poke: ["*accepts pat with the energy of a sleepy hug.*", "Mm, nice. Do that again, slowly."],
    feed: ["*chews bamboo with immense, unbothered focus.*"],
    play: ["*attempts a somersault, mostly succeeds.*"],
    sleepy: "*is already 80% asleep, this was inevitable.*",
    wake: "*yawns, in no hurry whatsoever.*",
    lowBattery: "Everything's running low on energy today, huh. Same. Charge up.",
    longIdle: "You were gone so long I took a nap. No regrets.",
    milestone: "Okay okay, gentle now. Even I have limits on cuddles per minute."
  },
  {
    id: "owl", name: "Owl", glyph: "🦉", tone: "info",
    tagline: "Sharper after dark.",
    voice: function (s) { return s; },
    greet: ["*swivels its whole head toward you.* Evening.", "Ah, you're up. Good. So am I."],
    poke: ["*blinks, unbothered, extremely dignified about it.*", "A respectful pat. Noted and appreciated."],
    feed: ["*accepts with a small, formal nod.*"],
    play: ["*does one perfectly silent lap around the desktop.*"],
    sleepy: "*tucks its head under a wing. Even owls rest eventually.*",
    wake: "*both eyes snap open at once. A little unsettling. Very awake.*",
    lowBattery: "The night is young but your battery is not. Plug in.",
    longIdle: "I kept watch. Nothing happened. That's usually good news.",
    milestone: "A wise creature knows when enough poking is enough. This is that moment."
  },
  {
    id: "dragon", name: "Dragon", glyph: "🐲", tone: "negative",
    tagline: "Hoards your open tasks.",
    voice: function (s) { return s.toUpperCase() + "!"; },
    greet: ["*uncoils from its hoard of open tabs.* You return to your treasure.", "Ahh, the ruler of this desktop graces us."],
    poke: ["*permits a single scale-scratch. This is an HONOR.*", "Mortal, that tickles. Do it again."],
    feed: ["*devours it in one dramatic gulp.* MORE."],
    play: ["*breathes a small, decorative puff of smoke.*"],
    sleepy: "*coils around its hoard and goes still, one eye cracked open.*",
    wake: "*rises from the hoard like this was always the plan.*",
    lowBattery: "EVEN DRAGONS NEED TO RECHARGE. Plug in the machine, mortal.",
    longIdle: "The hoard grew undisturbed in your absence. I approve. Also I missed you.",
    milestone: "ENOUGH POKING. ...continue, actually, it's kind of nice."
  },
  {
    id: "robot", name: "Robot", glyph: "🤖", tone: "accent",
    tagline: "It looks like you're doing a thing.",
    voice: function (s) { return "NOTICE: " + s; },
    greet: ["SYSTEMS ONLINE. Hello, user.", "Presence detected. Greetings."],
    poke: ["INPUT RECEIVED: pat. Affection subroutine engaged.", "Physical contact logged. 10/10, please repeat."],
    feed: ["FUEL ACCEPTED. Efficiency +1%. Thank you, user."],
    play: ["EXECUTING: playful maneuver. *whirrs enthusiastically*"],
    sleepy: "ENTERING LOW-POWER MODE. Goodnight, user.",
    wake: "REBOOTING FROM STANDBY. All systems nominal.",
    lowBattery: "WARNING: host battery critical. Recommend immediate charging.",
    longIdle: "USER ABSENCE LOGGED: extended duration. Welcome back, resuming normal operation.",
    milestone: "NOTICE: poke frequency exceeds recommended threshold. (Still tolerated.)"
  },
  {
    id: "ghost", name: "Ghost", glyph: "👻", tone: "info",
    tagline: "Haunts your idle windows.",
    voice: function (s) { return s + " 👻"; },
    greet: ["*phases in out of nowhere.* Boo. Hi.", "*drifts closer.* You felt that chill? That was me, saying hi."],
    poke: ["*giggles, translucent and delighted.*", "Ooh, a pat! I can almost feel that."],
    feed: ["*the snack passes through it, mostly, but the thought counts.*"],
    play: ["*does a lazy little loop-the-loop.*"],
    sleepy: "*fades to a faint outline and goes quiet.*",
    wake: "*fades back in, a little brighter than before.*",
    lowBattery: "Ironic, a ghost worrying about power. But yours is low. Fix that.",
    longIdle: "I haunted an empty desktop for a while there. Eerily peaceful. Welcome back.",
    milestone: "Even a ghost can only be poked so many times before it just... floats off a little."
  },
  {
    id: "frog", name: "Frog", glyph: "🐸", tone: "positive",
    tagline: "Mindfulness, mostly unsolicited.",
    voice: function (s) { return s + " 🍃"; },
    greet: ["*blinks slowly.* Hey. You made it.", "*sits on a leaf that isn't there.* Welcome."],
    poke: ["*ribbits contentedly.*", "Mm. Nice. Breathe in, breathe out, pat me again."],
    feed: ["*catches it with a small, satisfied ribbit.*"],
    play: ["*hops once, with great sincerity.*"],
    sleepy: "*settles onto its leaf and goes still.*",
    wake: "*one slow blink, then a small hop of readiness.*",
    lowBattery: "The battery is low. Like a pond in a drought. Time to recharge.",
    longIdle: "The pond was calm while you were away. Good. Balance restored now that you're back.",
    milestone: "Okay, that's a lot of pats. Let's just sit with this feeling for a moment."
  },
  {
    id: "penguin", name: "Penguin", glyph: "🐧", tone: "info",
    tagline: "Loyal to Linux, waddles everywhere.",
    voice: function (s) { return s; },
    greet: ["*waddles over enthusiastically.* You're on Linux AND you're back? Great day.", "*slides in on its belly.* Hi!"],
    poke: ["*flaps happily, off balance but delighted.*", "A pat! Excellent. Do continue."],
    feed: ["*catches it like a fish, very pleased with itself.*"],
    play: ["*attempts a belly slide, mostly successful.*"],
    sleepy: "*tucks in, huddled up against the cold.*",
    wake: "*pops back up, slightly ruffled, fully ready.*",
    lowBattery: "Battery's low — even penguins know to waddle back to shore in time.",
    longIdle: "I waddled in a little circle the whole time you were gone. Worth it.",
    milestone: "That's a lot of pats for one penguin. I'm not complaining, just noting it."
  },
  {
    id: "lizard", name: "Lizard", glyph: "🦎", tone: "warning",
    tagline: "Debugs by eating the bugs.",
    voice: function (s) { return s + " *tongue flick*"; },
    greet: ["*was already sunning itself on the corner of your screen.*", "*one slow blink.* You're back. I hadn't moved."],
    poke: ["*stays perfectly still, betrayed only by a faster heartbeat.*", "*tail twitches once. High praise, actually.*", "Do that again. Slowly. I don't do fast."],
    feed: ["*catches it out of the air without seeming to try.*"],
    play: ["*does one (1) very committed sprint, then stops forever.*"],
    sleepy: "*goes still on its rock. Impossible to tell it wasn't already like this.*",
    wake: "*a full-body stretch, unbothered by how long that took.*",
    lowBattery: "Low power looks familiar. I run on a sunbeam and vibes. Try a charger instead.",
    longIdle: "I stayed exactly where you left me. Reptiles are efficient like that.",
    milestone: "That's a lot of pokes for a creature that values stillness this much."
  }
]

// Shared Clippy-style tip pool. Each pet's `voice()` flavors these, so ten
// pets don't need ten independent copies of the same content.
var CLIPPY_TIPS = [
  "It looks like you're doing something. Would you like help? (I have none to offer, but I care.)",
  "SUPER + comma opens the launcher, if you forgot again.",
  "Reminder: `omarchy reminder 15 \"thing\"` beats trying to remember it yourself.",
  "You've had a lot of windows open for a while. No judgment. Okay, some judgment.",
  "Fun fact: I don't do anything useful. But I am very cute.",
  "Have you tried turning it off and on again? I ask because I love drama, not because it'll help.",
  "Screenshots are `omarchy capture screenshot`, in case that's what you're squinting at.",
  "A watched clock never boils. Wait, that's not right. Anyway, hi.",
  "This has been a very productive-looking silence. Keep it up.",
  "I noticed nothing in particular. I just wanted to say something.",
  "Ten pets were available and you picked me. Excellent taste.",
  "Somewhere, a config file is waiting to be tweaked. Not by me. By you.",
  "You could be automating this. You could also just keep petting me. Both valid.",
  "Hydration check. That's it. That's the tip.",
  "I've been perched here calculating nothing this whole time. It's very peaceful.",
  "If you're stuck, rubber duck debugging works. I'm basically a rubber duck with opinions.",
  "Every window you close is a window you don't have to think about anymore. Freeing, right?",
  "Right-click me any time for the settings panel. I promise I won't judge... much."
]

// ── achievements ─────────────────────────────────────────────────────────────
// Every condition is monotonic in the counters/age it reads, so "currently
// unlocked" can always be recomputed fresh from `state` -- nothing needs to
// be persisted as a separate "unlocked" list.
var ACHIEVEMENTS = [
  { id: "first_pet", name: "First Pat", description: "Pet your companion for the first time.",
    check: function (s) { return (s.totalPokes || 0) >= 1 } },
  { id: "first_feed", name: "Snack Time", description: "Feed your companion for the first time.",
    check: function (s) { return (s.totalFeeds || 0) >= 1 } },
  { id: "first_play", name: "Playtime", description: "Play with your companion for the first time.",
    check: function (s) { return (s.totalPlays || 0) >= 1 } },
  { id: "pat_pat_pat", name: "Pat Enthusiast", description: "Pet your companion 50 times.",
    check: function (s) { return (s.totalPokes || 0) >= 50 } },
  { id: "snack_master", name: "Snack Master", description: "Feed your companion 25 times.",
    check: function (s) { return (s.totalFeeds || 0) >= 25 } },
  { id: "playful", name: "Playful Spirit", description: "Play with your companion 25 times.",
    check: function (s) { return (s.totalPlays || 0) >= 25 } },
  { id: "dedicated", name: "Dedicated", description: "Adopted for 3 days.",
    check: function (s, nowMs) { return ageDays(s, nowMs) >= 3 } },
  { id: "best_friend", name: "Best Friend", description: "Adopted for 7 days.",
    check: function (s, nowMs) { return ageDays(s, nowMs) >= 7 } },
  { id: "night_owl", name: "Night Owl", description: "Interact with it between midnight and 5am.",
    check: function (s) { var h = new Date(numOr(s.lastInteractionMs, 0)).getHours(); return h >= 0 && h < 5 } },
  { id: "streak", name: "Can't Stop", description: "Hit a poke streak of " + POKE_STREAK_ANNOY + " in a row.",
    check: function (s) { return (s.pokeStreak || 0) >= POKE_STREAK_ANNOY } }
]

function unlockedAchievementIds(state, nowMs) {
  return ACHIEVEMENTS.filter(function (a) { return a.check(state, nowMs) }).map(function (a) { return a.id })
}

// Achievements unlocked in `nextState` that weren't unlocked in `prevState`.
// Both are checked against the same `nowMs` so an age-based achievement can't
// spuriously "newly unlock" just because a little wall-clock time passed
// between reading the two states.
function newlyUnlocked(prevState, nextState, nowMs) {
  var beforeIds = {}
  unlockedAchievementIds(prevState, nowMs).forEach(function (id) { beforeIds[id] = true })
  return ACHIEVEMENTS.filter(function (a) { return a.check(nextState, nowMs) && !beforeIds[a.id] })
}

// ── leveling ─────────────────────────────────────────────────────────────────
var ROAM_MODES = ["off", "walk", "gallop"]

var LEVEL_TITLES = ["Newcomer", "Regular", "Close Friend", "Best Friend", "Legend", "Living Legend"]
var LEVEL_INTERACTIONS_PER_LEVEL = 15

function levelInfo(state) {
  var total = (state.totalPokes || 0) + (state.totalFeeds || 0) + (state.totalPlays || 0)
  var level = 1 + Math.floor(total / LEVEL_INTERACTIONS_PER_LEVEL)
  var title = LEVEL_TITLES[Math.min(level - 1, LEVEL_TITLES.length - 1)]
  return { level: level, title: title, total: total, nextAt: level * LEVEL_INTERACTIONS_PER_LEVEL }
}

// ── wardrobe ─────────────────────────────────────────────────────────────────
// Cosmetic only; each accessory unlocks alongside a specific achievement.
var ACCESSORIES = [
  { id: "party_hat", glyph: "🎉", name: "Party Hat", unlockedBy: "dedicated" },
  { id: "sunglasses", glyph: "😎", name: "Sunglasses", unlockedBy: "pat_pat_pat" },
  { id: "crown", glyph: "👑", name: "Crown", unlockedBy: "best_friend" },
  { id: "bowtie", glyph: "🎀", name: "Bow", unlockedBy: "snack_master" }
]

function isAccessoryUnlocked(accessoryId, state, nowMs) {
  var acc = null
  for (var i = 0; i < ACCESSORIES.length; i++) if (ACCESSORIES[i].id === accessoryId) { acc = ACCESSORIES[i]; break }
  if (!acc) return false
  return unlockedAchievementIds(state, nowMs).indexOf(acc.unlockedBy) >= 0
}

function equipAccessory(state, accessoryId, nowMs) {
  var next = Object.assign({}, state)
  if (accessoryId === null || isAccessoryUnlocked(accessoryId, state, nowMs)) next.accessoryId = accessoryId
  return next
}

// ── shiny variant ────────────────────────────────────────────────────────────
// A small chance of a sparkly bragging-rights variant each time you switch to
// a *different* pet. `seed` (0..1000 scaled like pick()'s) makes it testable;
// real calls omit it and get Math.random().
function rollShiny(seed) {
  var r = (typeof seed === "number") ? (Math.abs(Math.floor(seed)) % 1000) / 1000 : Math.random()
  return r < 0.05
}

function pickShinyLine(pet) { return pet.voice("You caught the SHINY version of me. Incredible luck.") }

function clamp(n, lo, hi) { return Math.max(lo, Math.min(hi, n)) }
// `||` treats a genuine 0 as missing, which timestamps legitimately are
// (epoch 0, or a freshly-zeroed test fixture) -- use this instead.
function numOr(v, fallback) { return (typeof v === "number" && isFinite(v)) ? v : fallback }
function pick(arr, seed) {
  if (!arr || arr.length === 0) return ""
  var i = (typeof seed === "number") ? Math.abs(Math.floor(seed)) % arr.length : Math.floor(Math.random() * arr.length)
  return arr[i]
}

// ── catalogue lookups ───────────────────────────────────────────────────────
function allPets() { return PETS }
function petById(id) {
  for (var i = 0; i < PETS.length; i++) if (PETS[i].id === id) return PETS[i]
  return PETS[0]
}
function petIndex(id) {
  for (var i = 0; i < PETS.length; i++) if (PETS[i].id === id) return i
  return -1
}
function nextPetId(id) { var i = Math.max(0, petIndex(id)); return PETS[(i + 1) % PETS.length].id }
function prevPetId(id) { var i = Math.max(0, petIndex(id)); return PETS[(i - 1 + PETS.length) % PETS.length].id }

// ── state ────────────────────────────────────────────────────────────────────
function defaultState() {
  var now = Date.now()
  return {
    version: 1,
    petId: "cat",
    enabled: true,
    muted: false,
    asleep: false,
    manualSleep: false,
    posFracX: null,      // null = use the default corner until first drag
    posFracY: null,
    happiness: 80,
    fullness: 80,
    energy: 90,
    lastTickMs: now,
    lastFedMs: 0,
    lastPlayedMs: 0,
    lastInteractionMs: now,
    pokeStreak: 0,
    pokeStreakAt: 0,
    totalPokes: 0,
    totalFeeds: 0,
    totalPlays: 0,
    speechFreqMin: 6,
    bornMs: now,
    shiny: false,
    accessoryId: null,
    screenWatchEnabled: false,
    screenLookFreqMin: 20,
    roamMode: "off"
  }
}

function parseState(raw) {
  var d = defaultState()
  if (!raw || !raw.length) return d
  var obj
  try { obj = JSON.parse(raw) } catch (e) { return d }
  if (!obj || typeof obj !== "object") return d

  var out = Object.assign({}, d)
  if (typeof obj.petId === "string" && petIndex(obj.petId) >= 0) out.petId = obj.petId
  if (typeof obj.enabled === "boolean") out.enabled = obj.enabled
  if (typeof obj.muted === "boolean") out.muted = obj.muted
  if (typeof obj.manualSleep === "boolean") out.manualSleep = obj.manualSleep
  if (typeof obj.posFracX === "number") out.posFracX = clamp(obj.posFracX, 0, 1)
  if (typeof obj.posFracY === "number") out.posFracY = clamp(obj.posFracY, 0, 1)
  ;["happiness", "fullness", "energy"].forEach(function (k) {
    if (typeof obj[k] === "number" && isFinite(obj[k])) out[k] = clamp(obj[k], 0, 100)
  })
  ;["lastTickMs", "lastFedMs", "lastPlayedMs", "lastInteractionMs", "pokeStreakAt", "bornMs"].forEach(function (k) {
    if (typeof obj[k] === "number" && isFinite(obj[k]) && obj[k] >= 0) out[k] = obj[k]
  })
  ;["pokeStreak", "totalPokes", "totalFeeds", "totalPlays"].forEach(function (k) {
    if (typeof obj[k] === "number" && isFinite(obj[k]) && obj[k] >= 0) out[k] = Math.floor(obj[k])
  })
  if (typeof obj.speechFreqMin === "number" && obj.speechFreqMin > 0) out.speechFreqMin = clamp(obj.speechFreqMin, 1, 240)
  if (typeof obj.screenWatchEnabled === "boolean") out.screenWatchEnabled = obj.screenWatchEnabled
  if (typeof obj.screenLookFreqMin === "number" && obj.screenLookFreqMin > 0) out.screenLookFreqMin = clamp(obj.screenLookFreqMin, 5, 180)
  if (typeof obj.roamMode === "string" && ROAM_MODES.indexOf(obj.roamMode) >= 0) out.roamMode = obj.roamMode
  if (typeof obj.shiny === "boolean") out.shiny = obj.shiny
  if (obj.accessoryId === null) out.accessoryId = null
  else if (typeof obj.accessoryId === "string") {
    for (var i = 0; i < ACCESSORIES.length; i++) {
      if (ACCESSORIES[i].id === obj.accessoryId) { out.accessoryId = obj.accessoryId; break }
    }
  }
  out.asleep = !!out.manualSleep
  return out
}

// ── decay ────────────────────────────────────────────────────────────────────
// Rates are per hour of elapsed real time. Energy recovers while asleep
// instead of draining.
var DECAY = { happinessPerHour: 6, fullnessPerHour: 9, energyPerHour: 5, energyRecoverPerHourAsleep: 20 }

function applyDecay(state, nowMs) {
  var elapsedMs = Math.max(0, nowMs - numOr(state.lastTickMs, nowMs))
  if (elapsedMs === 0) return state
  var hours = elapsedMs / HOUR

  var willSleep = !!state.manualSleep || state.energy <= 15
  var next = Object.assign({}, state)
  next.happiness = clamp(state.happiness - DECAY.happinessPerHour * hours, 0, 100)
  next.fullness = clamp(state.fullness - DECAY.fullnessPerHour * hours, 0, 100)
  next.energy = willSleep
    ? clamp(state.energy + DECAY.energyRecoverPerHourAsleep * hours, 0, 100)
    : clamp(state.energy - DECAY.energyPerHour * hours, 0, 100)
  next.lastTickMs = nowMs
  next.asleep = !!state.manualSleep || next.energy <= 15
  if (next.energy > 60 && !state.manualSleep) next.asleep = false
  return next
}

function withInteraction(state, nowMs) {
  var next = Object.assign({}, state)
  next.lastInteractionMs = nowMs
  if (!next.manualSleep && next.energy > 20) next.asleep = false
  return next
}

function feed(state, nowMs) {
  var next = withInteraction(applyDecay(state, nowMs), nowMs)
  next.fullness = clamp(next.fullness + 30, 0, 100)
  next.happiness = clamp(next.happiness + 5, 0, 100)
  next.lastFedMs = nowMs
  next.totalFeeds = (next.totalFeeds || 0) + 1
  return next
}

function play(state, nowMs) {
  var next = withInteraction(applyDecay(state, nowMs), nowMs)
  next.happiness = clamp(next.happiness + 15, 0, 100)
  next.energy = clamp(next.energy - 8, 0, 100)
  next.lastPlayedMs = nowMs
  next.totalPlays = (next.totalPlays || 0) + 1
  return next
}

// Crossing POKE_STREAK_ANNOY resurfaces the milestone line instead of a
// normal poke reaction.
function poke(state, nowMs) {
  var next = withInteraction(applyDecay(state, nowMs), nowMs)
  var withinWindow = (nowMs - (state.pokeStreakAt || 0)) <= POKE_STREAK_WINDOW_MS
  next.pokeStreak = withinWindow ? (state.pokeStreak || 0) + 1 : 1
  next.pokeStreakAt = nowMs
  next.happiness = clamp(next.happiness + 4, 0, 100)
  next.totalPokes = (next.totalPokes || 0) + 1
  return next
}

function isAnnoyedPoke(state) { return (state.pokeStreak || 0) > 0 && (state.pokeStreak % POKE_STREAK_ANNOY) === 0 }

function setSleep(state, manual) {
  var next = Object.assign({}, state)
  next.manualSleep = !!manual
  next.asleep = !!manual || next.energy <= 15
  return next
}

// `shinySeed` is optional and only for deterministic tests -- real callers
// omit it and rollShiny() falls back to Math.random(). Reselecting the same
// pet id is a no-op (no reroll), so idle re-renders can't accidentally
// re-gamble an already-settled shiny status.
function selectPet(state, petId, shinySeed) {
  var next = Object.assign({}, state)
  if (petIndex(petId) >= 0 && petId !== state.petId) {
    next.petId = petId
    next.shiny = rollShiny(shinySeed)
  }
  return next
}

function setPosition(state, fracX, fracY) {
  var next = Object.assign({}, state)
  next.posFracX = clamp(fracX, 0, 1)
  next.posFracY = clamp(fracY, 0, 1)
  return next
}

// ── mood ─────────────────────────────────────────────────────────────────────
function moodLabel(state) {
  if (state.asleep) return "asleep"
  if (state.fullness < 25) return "hungry"
  if (state.happiness < 25) return "grumpy"
  if (state.happiness > 80 && state.fullness > 60) return "ecstatic"
  if (state.happiness < 50 || state.fullness < 50) return "meh"
  return "content"
}

function ageDays(state, nowMs) {
  return Math.max(0, Math.floor((nowMs - numOr(state.bornMs, nowMs)) / (24 * HOUR)))
}

function minutesIdle(state, nowMs) {
  return Math.max(0, Math.floor((nowMs - numOr(state.lastInteractionMs, nowMs)) / MIN))
}

// ── phrase pickers ───────────────────────────────────────────────────────────
function pickGreeting(pet, seed) { return pick(pet.greet, seed) }

function pickPokeLine(pet, state, seed) {
  if (isAnnoyedPoke(state)) return pet.milestone
  return pick(pet.poke, seed)
}

function pickFeedLine(pet, seed) { return pick(pet.feed, seed) }
function pickPlayLine(pet, seed) { return pick(pet.play, seed) }
function sleepyLine(pet) { return pet.sleepy }
function wakeLine(pet) { return pet.wake }

// Priority for unsolicited chatter: low battery > long idle > mood > generic
// Clippy tip. `context` = { isLowBattery, minutesIdleValue, moodLabelValue, seed }
// System prompt for the (opt-in) real screen-vision comment -- see
// deskpet-look. Built from data the pet already carries (tagline + its own
// voice() flavoring of a sample line) rather than a dedicated field per pet,
// so the 11-pet catalogue doesn't need yet another hand-written bank.
function screenLookSystemPrompt(pet) {
  var example = pet.voice("Nice.")
  return [
    "You are " + pet.name + " " + pet.glyph + ", a tiny desktop pet with this personality: " + pet.tagline,
    "You just glanced at your owner's screen. In one short sentence (under 25 words), make a witty, in-character comment about what's actually visible -- be specific to what you see, not generic.",
    "Match this voice (an example line in the same tone): \"" + example + "\"",
    "No markdown, no quotes around your reply, just the line you'd say out loud."
  ].join(" ")
}

// Short quip occasionally fired mid-gallop -- see Pet.qml's roam timer.
// Shared pool wrapped in the pet's own voice(), same trick CLIPPY_TIPS uses,
// so the 11-pet catalogue doesn't need a dedicated bank just for this.
var ZOOM_LINES = ["Zoom!", "Gotta go fast.", "Wheee!", "*blurs past*", "Look at me go.", "Vroom."]
function pickZoomLine(pet, seed) { return pet.voice(pick(ZOOM_LINES, seed)) }

function pickAmbientLine(pet, context, seed) {
  var ctx = context || {}
  if (ctx.isLowBattery) return pet.lowBattery
  if ((ctx.minutesIdleValue || 0) >= 30) return pet.longIdle
  var mood = ctx.moodLabelValue
  if (mood === "hungry") return pet.voice("I could really go for a snack right about now.")
  if (mood === "grumpy") return pet.voice("Not feeling it today. A pat might help.")
  return pet.voice(pick(CLIPPY_TIPS, seed))
}

if (typeof module !== "undefined") {
  module.exports = {
    HOUR: HOUR, MIN: MIN,
    PETS: PETS, CLIPPY_TIPS: CLIPPY_TIPS, ZOOM_LINES: ZOOM_LINES,
    POKE_STREAK_WINDOW_MS: POKE_STREAK_WINDOW_MS, POKE_STREAK_ANNOY: POKE_STREAK_ANNOY,
    ACHIEVEMENTS: ACHIEVEMENTS, ACCESSORIES: ACCESSORIES, LEVEL_TITLES: LEVEL_TITLES, ROAM_MODES: ROAM_MODES,
    clamp: clamp,
    allPets: allPets, petById: petById, petIndex: petIndex, nextPetId: nextPetId, prevPetId: prevPetId,
    defaultState: defaultState, parseState: parseState,
    applyDecay: applyDecay, feed: feed, play: play, poke: poke, isAnnoyedPoke: isAnnoyedPoke,
    setSleep: setSleep, selectPet: selectPet, setPosition: setPosition, withInteraction: withInteraction,
    moodLabel: moodLabel, ageDays: ageDays, minutesIdle: minutesIdle,
    pickGreeting: pickGreeting, pickPokeLine: pickPokeLine, pickFeedLine: pickFeedLine,
    pickPlayLine: pickPlayLine, sleepyLine: sleepyLine, wakeLine: wakeLine, pickAmbientLine: pickAmbientLine,
    pickZoomLine: pickZoomLine,
    screenLookSystemPrompt: screenLookSystemPrompt,
    unlockedAchievementIds: unlockedAchievementIds, newlyUnlocked: newlyUnlocked,
    levelInfo: levelInfo, isAccessoryUnlocked: isAccessoryUnlocked, equipAccessory: equipAccessory,
    rollShiny: rollShiny, pickShinyLine: pickShinyLine
  }
}
