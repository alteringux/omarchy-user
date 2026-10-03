// Plain-node tests for the pure logic in Model.js. Run with:
//   node plugins/alteringux.phone/test/model.test.js
// Model.js is loaded as a QML JS import in the plugin; the guarded
// `module.exports` at its foot exists purely for this harness.
const assert = require("assert")
const Model = require("../Model.js")

let passed = 0
function test(name, fn) {
  try {
    fn()
    passed++
    console.log("ok - " + name)
  } catch (e) {
    console.error("FAIL - " + name)
    console.error(e)
    process.exitCode = 1
  }
}

// ── config ──────────────────────────────────────────────────────────────
test("parseConfig: empty -> defaults, incoming off", () => {
  const c = Model.parseConfig("")
  assert.strictEqual(c.incomingEnabled, false)
  assert.strictEqual(c.endpointSilenceMs, 800)
  assert.strictEqual(c.quietHours.start, "22:00")
})

test("parseConfig: partial merges onto defaults without dropping siblings", () => {
  const c = Model.parseConfig(JSON.stringify({ incomingEnabled: true, quietHours: { start: "23:30" } }))
  assert.strictEqual(c.incomingEnabled, true)
  assert.strictEqual(c.quietHours.start, "23:30")
  assert.strictEqual(c.quietHours.end, "08:00", "end must survive a partial quietHours patch")
  assert.strictEqual(c.maxIncomingPerDay, 3)
})

test("parseConfig: garbage -> defaults", () => {
  assert.strictEqual(Model.parseConfig("{not json").incomingEnabled, false)
})

test("serializeConfig round-trips", () => {
  const src = Model.defaultConfig()
  src.incomingEnabled = true
  src.nanogptModel = "claude-3-5-sonnet"
  const back = Model.parseConfig(Model.serializeConfig(src))
  assert.strictEqual(back.incomingEnabled, true)
  assert.strictEqual(back.nanogptModel, "claude-3-5-sonnet")
})

test("serializeConfig preserves silence budgets", () => {
  const src = Model.defaultConfig()
  src.idlePromptSeconds = 31
  src.idleHangupSeconds = 17
  const back = Model.parseConfig(Model.serializeConfig(src))
  assert.strictEqual(back.idlePromptSeconds, 31)
  assert.strictEqual(back.idleHangupSeconds, 17)
})

// ── contact ─────────────────────────────────────────────────────────────
test("parseContact: empty -> defaults with empty persona", () => {
  const c = Model.parseContact("")
  assert.strictEqual(c.speaksFirst, true)
  assert.strictEqual(c.looseGuard, false)
  assert.deepStrictEqual(c.persona.rules, [])
})

test("mergeContact: persona merged field-by-field, rules replaced, junk rules dropped", () => {
  const base = Model.defaultContact()
  base.persona.backstory = "old bio"
  base.persona.personality = "kept"
  const merged = Model.mergeContact(base, {
    name: "Amanda",
    persona: { backstory: "new bio", rules: ["always skeptical", "  ", 5] }
  })
  assert.strictEqual(merged.name, "Amanda")
  assert.strictEqual(merged.persona.backstory, "new bio")
  assert.strictEqual(merged.persona.personality, "kept")
  assert.deepStrictEqual(merged.persona.rules, ["always skeptical"])
})

test("validateContact: flags missing name/voice/persona and bad frequency", () => {
  const errs = Model.validateContact({ voice: "", frequency: "sometimes", persona: {} })
  assert.ok(errs.some(e => /name is required/.test(e)))
  assert.ok(errs.some(e => /voice is required/.test(e)))
  assert.ok(errs.some(e => /frequency must be one of/.test(e)))
  assert.ok(errs.some(e => /backstory or a personality/.test(e)))
})

test("validateContact: a real seed passes", () => {
  const errs = Model.validateContact({
    name: "Amanda", voice: "en_US-amy-medium", frequency: "rare",
    persona: { backstory: "warm competent friend", personality: "sharp" }
  })
  assert.deepStrictEqual(errs, [])
})

test("slugify", () => {
  assert.strictEqual(Model.slugify("Dr. Sable!"), "dr-sable")
  assert.strictEqual(Model.slugify("  Multi  Word  "), "multi-word")
})

// ── persona assembly ────────────────────────────────────────────────────
test("assembleSystemPrompt: includes identity, rules, guard, memory, tools", () => {
  const c = Model.mergeContact(Model.defaultContact(), {
    name: "Amanda",
    persona: { backstory: "You grew up in Perth.", personality: "warm", speechStyle: "short sentences", rules: ["never lie to the caller"] }
  })
  const s = Model.assembleSystemPrompt(c, "He is learning the guitar.")
  assert.ok(/You are Amanda/.test(s))
  assert.ok(/grew up in Perth/.test(s))
  assert.ok(/never lie to the caller/.test(s))
  assert.ok(/Stay fully in character/.test(s), "guard block present when looseGuard false")
  assert.ok(/learning the guitar/.test(s), "memory injected")
  assert.ok(/web_search/.test(s), "tool note present")
})

test("assembleSystemPrompt: looseGuard drops the guard block only", () => {
  const c = Model.mergeContact(Model.defaultContact(), {
    name: "Vex", looseGuard: true,
    persona: { backstory: "a gremlin in the phone", personality: "contrarian" }
  })
  const s = Model.assembleSystemPrompt(c, "")
  assert.ok(!/Stay fully in character/.test(s), "no guard block under looseGuard")
  assert.ok(/You are Vex/.test(s), "identity still there")
  assert.ok(/web_search/.test(s), "tools still there")
})

test("buildMemoryPrompt: forbids recording in-call style directives", () => {
  const p = Model.buildMemoryPrompt("old notes", "Amanda", 1800)
  assert.ok(/answer in N words/i.test(p))
  assert.ok(/old notes/.test(p))
  assert.ok(/1800 characters/.test(p))
})

// ── incoming-call cadence ───────────────────────────────────────────────
test("inboundTickProbability: off is zero, rarer is smaller, capped at 0.25", () => {
  assert.strictEqual(Model.inboundTickProbability("off", 60), 0)
  const rare = Model.inboundTickProbability("rare", 60)
  const often = Model.inboundTickProbability("often", 60)
  assert.ok(rare > 0 && rare < often)
  assert.ok(Model.inboundTickProbability("often", 999999) <= 0.25)
})

test("withinQuietHours: midnight-wrapping window", () => {
  const q = { start: "22:00", end: "08:00" }
  assert.strictEqual(Model.withinQuietHours(new Date(2026, 0, 1, 23, 0), q), true)
  assert.strictEqual(Model.withinQuietHours(new Date(2026, 0, 1, 3, 0), q), true)
  assert.strictEqual(Model.withinQuietHours(new Date(2026, 0, 1, 12, 0), q), false)
  assert.strictEqual(Model.withinQuietHours(new Date(2026, 0, 1, 8, 0), q), false)
})

test("withinQuietHours: same-day window and garbage", () => {
  assert.strictEqual(Model.withinQuietHours(new Date(2026, 0, 1, 13, 0), { start: "12:00", end: "14:00" }), true)
  assert.strictEqual(Model.withinQuietHours(new Date(2026, 0, 1, 13, 0), { start: "x", end: "y" }), false)
  assert.strictEqual(Model.withinQuietHours(new Date(2026, 0, 1, 13, 0), null), false)
})

test("shouldOfferInbound: composite gate", () => {
  const cfg = Model.defaultConfig()
  cfg.incomingEnabled = true
  const contact = Model.mergeContact(Model.defaultContact(), { canInitiate: true, frequency: "often" })
  const noon = new Date(2026, 0, 1, 12, 0)

  assert.strictEqual(Model.shouldOfferInbound(cfg, contact, noon, 0).ok, true)
  assert.strictEqual(Model.shouldOfferInbound(cfg, contact, noon, 3).ok, false, "daily cap")
  assert.strictEqual(Model.shouldOfferInbound(Object.assign({}, cfg, { dnd: true }), contact, noon, 0).ok, false)
  assert.strictEqual(Model.shouldOfferInbound(Object.assign({}, cfg, { incomingEnabled: false }), contact, noon, 0).ok, false)
  assert.strictEqual(Model.shouldOfferInbound(cfg, Model.mergeContact(contact, { canInitiate: false }), noon, 0).ok, false)
  assert.strictEqual(Model.shouldOfferInbound(cfg, contact, new Date(2026, 0, 1, 2, 0), 0).ok, false, "quiet hours")
})

// ── whisper cleaning ────────────────────────────────────────────────────
test("cleanWhisperText: strips bracket markers, keeps words", () => {
  assert.strictEqual(Model.cleanWhisperText("[BLANK_AUDIO]"), "")
  assert.strictEqual(Model.cleanWhisperText("(music)  [ Silence ]"), "")
  assert.strictEqual(Model.cleanWhisperText("  what's the weather [_TT_9]  "), "what's the weather")
  assert.strictEqual(Model.cleanWhisperText("[00:00:00.000 --> 00:00:02.000]  hello there"), "hello there")
})

// ── searx shaping ──────────────────────────────────────────────────────
test("parseSearxResults: top-n {title,url,content}", () => {
  const json = JSON.stringify({
    results: [
      { title: "A", url: "https://a", content: "alpha  beta" },
      { title: "B", url: "https://b" },
      { url: "https://c", title: "" },
      { title: "D" } // no url -> skipped
    ]
  })
  const rows = Model.parseSearxResults(json, 2)
  assert.strictEqual(rows.length, 2)
  assert.deepStrictEqual(rows[0], { title: "A", url: "https://a", content: "alpha beta" })
  assert.strictEqual(rows[1].url, "https://b")
})

test("parseSearxResults: garbage -> []", () => {
  assert.deepStrictEqual(Model.parseSearxResults("nope", 5), [])
})

// ── misc ───────────────────────────────────────────────────────────────
test("formatCallClock", () => {
  assert.strictEqual(Model.formatCallClock(0), "0:00")
  assert.strictEqual(Model.formatCallClock(65000), "1:05")
  assert.strictEqual(Model.formatCallClock(134000), "2:14")
})

test("toolSpecs / toolLabelFor", () => {
  const specs = Model.toolSpecs()
  assert.strictEqual(specs.length, 3)
  assert.strictEqual(specs[0].function.name, "web_search")
  assert.strictEqual(Model.toolLabelFor("fetch_url"), "reading a page")
})

test("parseVoiceList: basenames, de-duped", () => {
  const raw = "/home/x/.local/share/piper-voices/en_US-amy-medium.onnx\n/home/x/.local/share/piper-voices/en_GB-cori-high.onnx\n\n"
  assert.deepStrictEqual(Model.parseVoiceList(raw), ["en_US-amy-medium", "en_GB-cori-high"])
})

test("parseCall / parseRing tolerate junk", () => {
  assert.strictEqual(Model.parseCall("").state, "IDLE")
  assert.strictEqual(Model.parseCall("{bad").state, "IDLE")
  assert.strictEqual(Model.parseRing(""), null)
  assert.strictEqual(Model.parseRing(JSON.stringify({ contactId: "amanda", contactName: "Amanda" })).contactName, "Amanda")
})

console.log("\n" + passed + " passed")
