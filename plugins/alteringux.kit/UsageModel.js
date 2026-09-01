// Pure ranking / decay math for Kit.Usage — QML-free so it unit-tests under
// Node like every plugin's Model.js. Usage.qml owns the on-disk JSON (via
// Kit.Store) and calls into here.
//
// Doc shape:
//   { actions: { "<name>": { count:int, lastAt:ms, recent:[ms,...] } }, firstAt: ms }
//
// `recent` is a capped ring of the last RECENT_CAP use timestamps — it feeds
// the recency half of the blended score. `count` / `lastAt` are the lifetime
// tallies used for the "is this feature dead?" check.

var RECENT_CAP = 20;
var HALF_LIFE_DAYS = 7;      // a use this old contributes half to the recency score
var DEAD_AFTER_DAYS = 21;    // idle at least this long ...
var DEAD_UNDER_COUNT = 3;    // ... and used fewer than this many times ever => "dead"
var DAY_MS = 86400000;

function now_(t) { return (typeof t === "number" && isFinite(t)) ? t : Date.now(); }

function defaultDoc() { return { actions: {}, firstAt: 0 }; }

// Tolerant parse: "" / missing / malformed / partially-garbled all degrade to
// a sane doc, never throw. Only well-formed action entries are adopted.
function parse(raw) {
  var doc = defaultDoc();
  if (!raw || !raw.length) return doc;
  try {
    var s = JSON.parse(raw);
    if (s && typeof s === "object" && s.actions && typeof s.actions === "object") {
      for (var k in s.actions) {
        var a = s.actions[k] || {};
        doc.actions[k] = {
          count:  (isFinite(a.count)  && a.count  > 0) ? Math.floor(a.count) : 0,
          lastAt: (isFinite(a.lastAt) && a.lastAt > 0) ? a.lastAt : 0,
          recent: Array.isArray(a.recent)
            ? a.recent.filter(function (n) { return isFinite(n) && n > 0; }).slice(-RECENT_CAP)
            : []
        };
      }
    }
    if (s && isFinite(s.firstAt) && s.firstAt > 0) doc.firstAt = s.firstAt;
  } catch (e) { /* corrupt -> empty doc */ }
  return doc;
}

// Returns a NEW doc with one use of `action` folded in. Clones through
// parse(JSON.stringify(...)) so the caller's object is never mutated and the
// result is always in canonical shape.
function record(doc, action, at) {
  var d = parse(JSON.stringify(doc || defaultDoc()));
  var name = String(action || "").trim();
  if (!name) return d;
  var t = now_(at);
  if (!d.firstAt) d.firstAt = t;
  var a = d.actions[name] || (d.actions[name] = { count: 0, lastAt: 0, recent: [] });
  a.count += 1;
  a.lastAt = t;
  a.recent.push(t);
  if (a.recent.length > RECENT_CAP) a.recent = a.recent.slice(-RECENT_CAP);
  return d;
}

function decayWeight(ageMs) {
  var days = ageMs / DAY_MS;
  return days > 0 ? Math.pow(0.5, days / HALF_LIFE_DAYS) : 1;
}

// Blended score: recency-decayed sum over the ring, plus a small lifetime-
// count credit (log-scaled) so a long-idle but heavily-used action doesn't
// collapse to zero and vanish from the ranking.
function score(doc, action, at) {
  var d = (doc && doc.actions) ? doc : defaultDoc();
  var a = d.actions[String(action || "")];
  if (!a) return 0;
  var t = now_(at), s = 0;
  for (var i = 0; i < a.recent.length; i++) s += decayWeight(t - a.recent[i]);
  return s + Math.log(1 + a.count) * 0.25;
}

// Action names sorted by descending score. `subset`, when a non-empty array,
// restricts and orders only those names (names with no history sort last).
function rank(doc, subset, at) {
  var d = (doc && doc.actions) ? doc : defaultDoc();
  var names = (Array.isArray(subset) && subset.length) ? subset.slice() : Object.keys(d.actions);
  var t = now_(at);
  return names
    .map(function (n) { return { n: n, s: score(d, n, t) }; })
    .sort(function (x, y) { return y.s - x.s; })
    .map(function (o) { return o.n; });
}

function top(doc, n, at) { return rank(doc, null, at).slice(0, Math.max(0, n | 0)); }

// True when a feature is safe to demote/hide: never used, or idle for
// DEAD_AFTER_DAYS AND used fewer than DEAD_UNDER_COUNT times in its life.
function isDead(doc, action, at) {
  var d = (doc && doc.actions) ? doc : defaultDoc();
  var a = d.actions[String(action || "")];
  if (!a || !a.count) return true;
  var idleDays = (now_(at) - a.lastAt) / DAY_MS;
  return idleDays >= DEAD_AFTER_DAYS && a.count < DEAD_UNDER_COUNT;
}

// Exposed only for the Node test harness under test/; QML's JS import has no
// `module` global, so this is inert there.
if (typeof module !== "undefined") {
  module.exports = {
    RECENT_CAP: RECENT_CAP,
    HALF_LIFE_DAYS: HALF_LIFE_DAYS,
    DEAD_AFTER_DAYS: DEAD_AFTER_DAYS,
    DEAD_UNDER_COUNT: DEAD_UNDER_COUNT,
    DAY_MS: DAY_MS,
    defaultDoc: defaultDoc,
    parse: parse,
    record: record,
    score: score,
    rank: rank,
    top: top,
    isDead: isDead
  };
}
