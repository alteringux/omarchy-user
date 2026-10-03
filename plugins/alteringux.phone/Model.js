// Pure logic for the alteringux.phone plugin.
//
// No QML / Quickshell APIs in here so the parts that are worth reasoning about
// in isolation — persona assembly, the incoming-call cadence maths, quiet-hour
// windows, whisper-output cleaning, SearXNG result shaping, the call-state
// parsers — can be Node-tested (test/model.test.js).
//
// ~/.local/bin/omarchy-phone owns every JSON file and every side effect (mic
// capture, whisper, the NanoGPT calls, piper-tts, the incoming-call
// scheduler). The QML surfaces are thin views. This module is the shared brain
// the daemon (via phone-cli.js) and the widgets both read, so a rule lives in
// exactly one place.

var PLUGIN_GLYPH = ""; // nf-fa-phone

// Call turn labels the widget renders while connected.
var TURN = {
  IDLE: "idle",
  LISTENING: "listening",
  THINKING: "thinking",
  SPEAKING: "speaking",
  TOOL: "tool"
};

var CALL_STATE = {
  IDLE: "IDLE",
  DIALING: "DIALING",
  RINGING: "RINGING",
  CONNECTED: "CONNECTED",
  ENDED: "ENDED"
};

// ── config ────────────────────────────────────────────────────────────────
function defaultConfig() {
  return {
    version: 1,
    // Incoming calls are entirely opt-in. Nothing rings until this is true.
    incomingEnabled: false,
    quietHours: { start: "22:00", end: "08:00" },
    maxIncomingPerDay: 3,
    dnd: false,
    // What to do when an incoming roll succeeds but you are busy (in a call,
    // screen locked, fullscreen app focused): "drop" | "queue".
    whenBusy: "drop",
    // Local pipeline knobs.
    sttModel: "~/.cache/whisper/ggml-base.en.bin",
    endpointSilenceMs: 800,
    // Silence budgets for the connected-call presence check and hangup.
    idlePromptSeconds: 20,
    idleHangupSeconds: 15,
    // Raised threshold + minimum voiced run used only while the contact is
    // speaking, so piper's own audio is less likely to self-trigger a barge-in.
    bargeInNoiseDb: -22,
    bargeInMinVoicedMs: 350,
    echoCancel: true,
    // A fast, natural, tool-capable model covered by the NanoGPT subscription
    // (a subscription key cannot spend on pay-per-use models like chatgpt-4o).
    nanogptModel: "z-ai/glm-5.3-flash",
    nanogptBaseUrl: "https://nano-gpt.com/api/v1",
    searxngUrl: "http://127.0.0.1:8080",
    maxToolIters: 3,
    historyTurnCap: 40,
    memoryTailTurns: 10,
    memoryMaxChars: 1800
  };
}

function parseConfig(raw) {
  var d = defaultConfig();
  var v;
  try {
    v = (raw && String(raw).length) ? JSON.parse(raw) : null;
  } catch (e) {
    v = null;
  }
  if (!v || typeof v !== "object") return d;
  var out = d;
  for (var k in d) {
    if (v[k] === undefined || v[k] === null) continue;
    if (k === "quietHours" && typeof v[k] === "object") {
      out.quietHours = {
        start: typeof v[k].start === "string" ? v[k].start : d.quietHours.start,
        end: typeof v[k].end === "string" ? v[k].end : d.quietHours.end
      };
    } else {
      out[k] = v[k];
    }
  }
  return out;
}

function serializeConfig(value) {
  var d = defaultConfig();
  var v = value || {};
  var out = {};
  for (var k in d) out[k] = (v[k] === undefined || v[k] === null) ? d[k] : v[k];
  out.version = 1;
  return JSON.stringify(out, null, 2);
}

// ── contact ───────────────────────────────────────────────────────────────
function defaultContact() {
  return {
    schemaVersion: 1,
    id: "",
    name: "",
    voice: "en_US-amy-medium",
    lengthScale: "1.0",
    // Reserved: piper-tts owns playback and has no pitch flag, so v1 does not
    // apply this. Kept so the data model does not churn when it lands.
    pitch: 0,
    model: "",
    speaksFirst: true,
    // Drops the roleplay guard (stay in character / do not offer to help with
    // code / do not say you are an AI / do not wrap up). Nothing to do with
    // content — the model / provider is the only limit on that.
    looseGuard: false,
    canInitiate: false,
    frequency: "off", // off | rare | occasional | often
    quietHours: null, // null = inherit global
    persona: {
      backstory: "",
      personality: "",
      speechStyle: "",
      rules: []
    }
  };
}

function parseContact(raw) {
  var d = defaultContact();
  var v;
  try {
    v = (raw && String(raw).length) ? JSON.parse(raw) : null;
  } catch (e) {
    v = null;
  }
  if (!v || typeof v !== "object") return d;
  return mergeContact(d, v);
}

// Deep-ish merge used both to parse a stored contact onto defaults and to
// apply a panel edit. `persona` is merged field by field; `rules` is replaced
// wholesale when present (it is a list the editor owns as one blob).
function mergeContact(base, patch) {
  var out = JSON.parse(JSON.stringify(base));
  if (!patch || typeof patch !== "object") return out;
  for (var k in patch) {
    if (k === "persona" && patch.persona && typeof patch.persona === "object") {
      if (!out.persona) out.persona = { backstory: "", personality: "", speechStyle: "", rules: [] };
      var p = patch.persona;
      if (typeof p.backstory === "string") out.persona.backstory = p.backstory;
      if (typeof p.personality === "string") out.persona.personality = p.personality;
      if (typeof p.speechStyle === "string") out.persona.speechStyle = p.speechStyle;
      if (Array.isArray(p.rules)) out.persona.rules = p.rules.filter(function (r) { return typeof r === "string" && r.trim().length; });
    } else if (patch[k] !== undefined && patch[k] !== null) {
      out[k] = patch[k];
    }
  }
  out.schemaVersion = 1;
  return out;
}

function slugify(s) {
  return String(s || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
}

// Returns an array of human-readable problems; empty means valid.
function validateContact(c) {
  var errs = [];
  if (!c || typeof c !== "object") return ["not an object"];
  if (!c.name || !String(c.name).trim()) errs.push("name is required");
  if (!c.voice || !String(c.voice).trim()) errs.push("voice is required");
  var freq = ["off", "rare", "occasional", "often"];
  if (c.frequency && freq.indexOf(c.frequency) === -1) errs.push("frequency must be one of " + freq.join(", "));
  if (c.lengthScale !== undefined && c.lengthScale !== "" && isNaN(parseFloat(c.lengthScale))) errs.push("lengthScale must be a number");
  var p = c.persona || {};
  if (!p.backstory && !p.personality) errs.push("give the contact at least a backstory or a personality");
  return errs;
}

// ── live call state ───────────────────────────────────────────────────────
function defaultCall() {
  return {
    version: 1,
    state: CALL_STATE.IDLE,
    contactId: "",
    contactName: "",
    direction: "outbound", // outbound | inbound
    startedAtMs: 0,
    connectedAtMs: 0,
    endedAtMs: 0,
    muted: false,
    hold: false,
    turn: TURN.IDLE,
    toolLabel: "",
    reason: "", // inbound: the light "why" line
    transcript: [], // [{ role: "user"|"assistant", text, atMs }]
    lastError: ""
  };
}

function parseCall(raw) {
  var d = defaultCall();
  var v;
  try {
    v = (raw && String(raw).length) ? JSON.parse(raw) : null;
  } catch (e) {
    v = null;
  }
  if (!v || typeof v !== "object") return d;
  var out = d;
  for (var k in d) if (v[k] !== undefined && v[k] !== null) out[k] = v[k];
  if (!Array.isArray(out.transcript)) out.transcript = [];
  return out;
}

function parseRing(raw) {
  try {
    var v = (raw && String(raw).length) ? JSON.parse(raw) : null;
    if (!v || typeof v !== "object" || !v.contactId) return null;
    return {
      contactId: String(v.contactId),
      contactName: typeof v.contactName === "string" ? v.contactName : v.contactId,
      reason: typeof v.reason === "string" ? v.reason : "",
      ringingSinceMs: typeof v.ringingSinceMs === "number" ? v.ringingSinceMs : 0
    };
  } catch (e) {
    return null;
  }
}

// ── persona assembly (daemon builds the actual request; this is the text) ──
// Fixed order, per the spec: identity, then rules, then the guard block (only
// when looseGuard is false), then memory, then the tool note. Re-sent every
// turn so the contact cannot drift into "as an AI, I…". The caller's in-call
// instructions live in the retained message history, not here, so they persist
// for the rest of the call without this overwriting them.
function assembleSystemPrompt(contact, memoryText, opts) {
  opts = opts || {};
  var c = contact || defaultContact();
  var p = c.persona || {};
  var lines = [];

  var identity = [];
  if (p.backstory && p.backstory.trim()) identity.push(p.backstory.trim());
  if (p.personality && p.personality.trim()) identity.push("Your personality: " + p.personality.trim());
  if (p.speechStyle && p.speechStyle.trim()) identity.push("How you talk: " + p.speechStyle.trim());
  if (identity.length) {
    lines.push("You are " + (c.name || "a person") + ", speaking with the caller on a phone call.");
    lines.push(identity.join(" "));
  } else {
    lines.push("You are " + (c.name || "a person") + " on a phone call with the caller.");
  }

  var rules = Array.isArray(p.rules) ? p.rules.filter(function (r) { return r && r.trim(); }) : [];
  if (rules.length) {
    lines.push("Rules you always follow:");
    for (var i = 0; i < rules.length; i++) lines.push("- " + rules[i].trim());
  }

  if (!c.looseGuard) {
    lines.push(
      "Stay fully in character for the whole call. Do not offer to help with code, tasks, or projects, " +
      "do not say you are an AI or a language model, do not narrate actions, and do not wrap up with a summary " +
      "or \"let me know if you need anything else\" — the call simply continues until the caller ends it. " +
      "Speak in natural spoken sentences, no markdown or lists."
    );
  }

  if (memoryText && memoryText.trim()) {
    lines.push("What you already know about the caller and your history together:");
    lines.push(memoryText.trim());
  }

  lines.push(
    "You can call tools when you genuinely need current facts: web_search for current information, " +
    "fetch_url to read one page, get_datetime for the date and time. Prefer answering from what you know; " +
    "when you do search, use at most one or two calls and then answer the caller out loud — this is a " +
    "phone call, not a research session."
  );

  if (opts.extra && opts.extra.trim()) lines.push(opts.extra.trim());

  return lines.join("\n\n");
}

// The opening line prompt for a contact that speaks first.
function buildGreetingInstruction(contact, direction) {
  var c = contact || defaultContact();
  if (direction === "inbound") {
    return "You are calling the caller. Open with a short, natural greeting (one or two sentences) that fits " +
      "your personality and, if you have any shared history, nods to it. If there is a light reason you called " +
      "(checking in, thought of them, saw something), mention it briefly. Then stop and let them respond.";
  }
  return "The caller just rang you. Open with a short, natural greeting (one sentence or two) in character, " +
    "using any shared history if you have it. Then stop and let them talk.";
}

// The end-of-call memory summariser prompt. Deliberately scoped to the
// relationship, NOT the contact's speaking style this call or any in-call
// formatting instructions the caller gave.
function buildMemoryPrompt(existingMemory, contactName, maxChars) {
  maxChars = maxChars || 1800;
  return [
    "You are updating your private notes about a caller after a phone call, so you remember them next time.",
    "Merge what matters from this call into the existing notes below. Keep ONLY:",
    "- facts the caller told you about themselves, their life, work, plans, preferences, people they mentioned",
    "- topics you discussed and where things were left",
    "- the state of your relationship with them",
    "Do NOT record: how you spoke this call, any \"answer in N words\" / formatting instructions they gave for this call, " +
      "small talk with no lasting content, or your own opinions.",
    "Write it as short plain-prose notes in the first person (\"He told me…\"). Under " + maxChars + " characters. " +
      "If the existing notes plus the new material would run long, condense the whole thing.",
    "",
    "=== EXISTING NOTES ===",
    (existingMemory && existingMemory.trim()) ? existingMemory.trim() : "(none yet)",
    "=== END EXISTING NOTES ===",
    "",
    "Return only the updated notes, nothing else."
  ].join("\n");
}

// ── incoming-call cadence ─────────────────────────────────────────────────
// Rough target periods for each frequency, in seconds. Tuned here so the
// daemon's per-tick probability is just tickSeconds / period.
var FREQUENCY_PERIOD_SECONDS = {
  off: 0,
  rare: 7 * 24 * 3600,       // ~1 / week
  occasional: 2 * 24 * 3600, // ~1 / 2 days
  often: 24 * 3600           // ~1 / day
};

function inboundTickProbability(frequency, tickSeconds) {
  var period = FREQUENCY_PERIOD_SECONDS[frequency] || 0;
  if (period <= 0 || tickSeconds <= 0) return 0;
  var p = tickSeconds / period;
  if (p > 0.25) p = 0.25; // never more than a 1-in-4 shot on a single tick
  return p;
}

// HH:MM parse -> minutes since midnight, or -1 on garbage.
function _hm(s) {
  var m = /^(\d{1,2}):(\d{2})$/.exec(String(s || "").trim());
  if (!m) return -1;
  var h = parseInt(m[1], 10), mi = parseInt(m[2], 10);
  if (h < 0 || h > 23 || mi < 0 || mi > 59) return -1;
  return h * 60 + mi;
}

// `now` is a Date. `quietHours` is { start, end } as "HH:MM". A window whose
// end is <= start wraps past midnight (the common 22:00 -> 08:00 case).
function withinQuietHours(now, quietHours) {
  if (!quietHours) return false;
  var s = _hm(quietHours.start), e = _hm(quietHours.end);
  if (s < 0 || e < 0) return false;
  var cur = now.getHours() * 60 + now.getMinutes();
  if (s === e) return false;
  if (s < e) return cur >= s && cur < e;
  return cur >= s || cur < e; // wraps midnight
}

// The composite gate for offering an incoming call from `contact`, EXCLUDING
// the probability roll (kept separate so it is deterministic to test) and the
// busy checks (screen lock / fullscreen — the daemon does those live).
// Returns { ok: bool, why: string }.
function shouldOfferInbound(config, contact, now, todayCount) {
  config = config || defaultConfig();
  if (!config.incomingEnabled) return { ok: false, why: "incoming disabled" };
  if (config.dnd) return { ok: false, why: "dnd" };
  if (!contact || !contact.canInitiate) return { ok: false, why: "contact cannot initiate" };
  if (!contact.frequency || contact.frequency === "off") return { ok: false, why: "frequency off" };
  if ((todayCount || 0) >= (config.maxIncomingPerDay || 0)) return { ok: false, why: "daily cap reached" };
  var q = contact.quietHours || config.quietHours;
  if (withinQuietHours(now, q)) return { ok: false, why: "quiet hours" };
  return { ok: true, why: "" };
}

// ── whisper output cleaning (mirrors ptt-listen.sh's sed pipeline) ────────
function cleanWhisperText(raw) {
  var t = String(raw || "");
  t = t.replace(/^\s*\[[^\]]*\]\s*/gm, " "); // leading [timestamp] lines
  t = t.replace(/[\[(][^\])]*[\])]/g, " ");  // [ Silence ], (music), [BLANK_AUDIO]
  t = t.replace(/\s+/g, " ").trim();
  return /[a-z0-9]/i.test(t) ? t : "";
}

// ── SearXNG result shaping ────────────────────────────────────────────────
function parseSearxResults(jsonText, n) {
  n = n || 5;
  var out = [];
  var d;
  try {
    d = JSON.parse(jsonText);
  } catch (e) {
    return out;
  }
  var rows = (d && Array.isArray(d.results)) ? d.results : [];
  for (var i = 0; i < rows.length && out.length < n; i++) {
    var r = rows[i] || {};
    if (!r.url) continue;
    out.push({
      title: String(r.title || r.url),
      url: String(r.url),
      content: String(r.content || "").replace(/\s+/g, " ").trim()
    });
  }
  return out;
}

// The OpenAI-style tool schema the daemon advertises to NanoGPT.
function toolSpecs() {
  return [
    {
      type: "function",
      function: {
        name: "web_search",
        description: "Search the web for current information. Returns a list of result titles, URLs and snippets.",
        parameters: {
          type: "object",
          properties: { query: { type: "string", description: "the search query" } },
          required: ["query"]
        }
      }
    },
    {
      type: "function",
      function: {
        name: "fetch_url",
        description: "Fetch one web page and return its readable text (truncated). Use after web_search when a snippet is not enough to answer.",
        parameters: {
          type: "object",
          properties: { url: { type: "string", description: "the absolute URL to fetch" } },
          required: ["url"]
        }
      }
    },
    {
      type: "function",
      function: {
        name: "get_datetime",
        description: "Get the caller's current local date and time.",
        parameters: { type: "object", properties: {} }
      }
    }
  ];
}

function toolLabelFor(name) {
  if (name === "web_search") return "searching the web";
  if (name === "fetch_url") return "reading a page";
  if (name === "get_datetime") return "checking the time";
  return "using a tool";
}

// ── misc formatting ──────────────────────────────────────────────────────
function formatCallClock(ms) {
  var s = Math.max(0, Math.floor((ms || 0) / 1000));
  var m = Math.floor(s / 60);
  var sec = s % 60;
  return m + ":" + (sec < 10 ? "0" : "") + sec;
}

function transcriptTail(turns, n) {
  if (!Array.isArray(turns)) return [];
  n = n || 10;
  return turns.slice(-n);
}

// Voice ids from `ls -1 <dir>/*.onnx` output (basename, no extension).
function parseVoiceList(raw) {
  var out = [];
  var lines = String(raw || "").split(/\r?\n/);
  for (var i = 0; i < lines.length; i++) {
    var l = lines[i].trim();
    if (!l) continue;
    var base = l.split("/").pop().replace(/\.onnx$/i, "");
    if (base && out.indexOf(base) === -1) out.push(base);
  }
  return out;
}

if (typeof module !== "undefined") {
  module.exports = {
    PLUGIN_GLYPH: PLUGIN_GLYPH,
    TURN: TURN,
    CALL_STATE: CALL_STATE,
    FREQUENCY_PERIOD_SECONDS: FREQUENCY_PERIOD_SECONDS,
    defaultConfig: defaultConfig,
    parseConfig: parseConfig,
    serializeConfig: serializeConfig,
    defaultContact: defaultContact,
    parseContact: parseContact,
    mergeContact: mergeContact,
    slugify: slugify,
    validateContact: validateContact,
    defaultCall: defaultCall,
    parseCall: parseCall,
    parseRing: parseRing,
    assembleSystemPrompt: assembleSystemPrompt,
    buildGreetingInstruction: buildGreetingInstruction,
    buildMemoryPrompt: buildMemoryPrompt,
    inboundTickProbability: inboundTickProbability,
    withinQuietHours: withinQuietHours,
    shouldOfferInbound: shouldOfferInbound,
    cleanWhisperText: cleanWhisperText,
    parseSearxResults: parseSearxResults,
    toolSpecs: toolSpecs,
    toolLabelFor: toolLabelFor,
    formatCallClock: formatCallClock,
    transcriptTail: transcriptTail,
    parseVoiceList: parseVoiceList
  };
}
