// Pure logic for the News Bar plugin: tolerant parsing of the state file
// written by bin/newsbar_fetch.py, relative-age formatting, and a cheap
// change signature the QML side uses to avoid rebuilding the marquee when a
// refresh produced the same headlines. Kept free of QML/Quickshell APIs so
// it can be unit-tested in plain node (see test/model.test.js). The guarded
// module.exports at the bottom is a no-op inside QML.

function defaultState() {
  return { version: 1, updatedAt: null, error: null, headlines: [] };
}

function sanitizeHeadline(raw) {
  if (!raw || typeof raw !== "object") return null;
  var source = String(raw.source || "").trim();
  var title = String(raw.title || "").trim();
  var url = String(raw.url || "").trim();
  if (!title || !/^https?:\/\//i.test(url)) return null;
  var readingMinutes = parseInt(raw.readingMinutes, 10);
  if (!(readingMinutes > 0)) readingMinutes = 0;
  return {
    source: source || "News",
    title: title,
    url: url,
    published: String(raw.published || "").trim(),
    category: String(raw.category || "").trim().slice(0, 24),
    summary: String(raw.summary || "").trim().slice(0, 320),
    readingMinutes: readingMinutes
  };
}

// Fold a sector label onto one of a small fixed set of buckets the bar
// colour-codes. Anything unrecognised falls through to "other" (still shown,
// just in the neutral sector colour).
var CATEGORY_BUCKETS = {
  world: "world", uk: "world", us: "world", africa: "world", asia: "world",
  europe: "world", americas: "world", australia: "world",
  "middle east": "world",
  business: "business", markets: "business", economy: "business",
  politics: "politics", opinion: "politics",
  tech: "tech", technology: "tech", science: "science", climate: "science",
  environment: "science",
  health: "health",
  sport: "sport", sports: "sport",
  culture: "culture", life: "culture", travel: "culture", media: "culture",
  education: "culture"
};

function normalizeCategory(cat) {
  var key = String(cat || "").trim().toLowerCase();
  if (!key) return "";
  return CATEGORY_BUCKETS[key] || "other";
}

// Tolerant: a half-written or malformed file yields an empty headline list
// rather than throwing, so the bar just shows its "waiting" state.
function parseState(raw) {
  var state = defaultState();
  if (!raw || !String(raw).trim()) return state;
  var parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    state.error = "state file unreadable";
    return state;
  }
  if (!parsed || typeof parsed !== "object") return state;
  state.updatedAt = parsed.updatedAt || null;
  state.error = parsed.error || null;
  if (Array.isArray(parsed.headlines)) {
    for (var i = 0; i < parsed.headlines.length; i++) {
      var h = sanitizeHeadline(parsed.headlines[i]);
      if (h) state.headlines.push(h);
    }
  }
  return state;
}

// "just now" / "5m" / "3h" / "2d". Empty string when the timestamp is missing
// or unparseable, or clearly in the future (clock skew between feed and host).
function relativeAge(iso, nowMs) {
  if (!iso) return "";
  var then = Date.parse(iso);
  if (isNaN(then)) return "";
  var now = typeof nowMs === "number" ? nowMs : Date.now();
  var secs = Math.round((now - then) / 1000);
  if (secs < -300) return "";
  if (secs < 60) return "just now";
  var mins = Math.round(secs / 60);
  if (mins < 60) return mins + "m";
  var hours = Math.round(mins / 60);
  if (hours < 24) return hours + "h";
  var days = Math.round(hours / 24);
  return days + "d";
}

// "12 min read" for short pieces; "3h 5m read" / "6h read" once it runs past an
// hour (Literotica's newest listing regularly turns up multi-page novels).
function formatReadTime(mins) {
  if (!(mins > 0)) return "";
  if (mins < 60) return mins + " min read";
  var h = Math.floor(mins / 60);
  var m = mins % 60;
  return (m ? h + "h " + m + "m" : h + "h") + " read";
}

function withAges(headlines, nowMs) {
  return (headlines || []).map(function (h) {
    return {
      source: h.source,
      title: h.title,
      url: h.url,
      published: h.published,
      category: h.category || "",
      categoryBucket: normalizeCategory(h.category),
      summary: h.summary || "",
      age: relativeAge(h.published, nowMs),
      readingMinutes: h.readingMinutes || 0,
      readTime: formatReadTime(h.readingMinutes || 0)
    };
  });
}

// Cheap identity of a headline set. The QML side compares this across
// refreshes and only rebuilds the (doubled, animated) marquee track when it
// changes, so an unchanged refresh doesn't restart the scroll.
function signature(headlines) {
  return (headlines || [])
    .map(function (h) { return h.url; })
    .join("");
}

// One display string per headline for the crawl:
// "BBC  Headline text  · 3h  · 12 min read" (read time only on ero-news).
function headlineLabel(h) {
  var age = h.age ? "  · " + h.age : "";
  var read = h.readTime ? "  · " + h.readTime : "";
  return h.source + "   " + h.title + age + read;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    defaultState: defaultState,
    sanitizeHeadline: sanitizeHeadline,
    normalizeCategory: normalizeCategory,
    parseState: parseState,
    relativeAge: relativeAge,
    formatReadTime: formatReadTime,
    withAges: withAges,
    signature: signature,
    headlineLabel: headlineLabel
  };
}
