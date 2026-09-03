const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../Model.js")

test("parseStatus: not-running line -> empty", () => {
  const s = M.parseStatus("cliamp is not running (no socket at /home/x/.config/cliamp/cliamp.sock)")
  assert.equal(s.running, false)
  assert.equal(s.playing, false)
  assert.equal(s.label, "")
})

test("parseStatus: empty / garbage -> empty", () => {
  assert.equal(M.parseStatus("").running, false)
  assert.equal(M.parseStatus(null).running, false)
  assert.equal(M.parseStatus("not json").running, false)
})

test("parseStatus: playing stream", () => {
  const raw = JSON.stringify({
    ok: true, state: "playing",
    track: { title: "Lofi Stream", path: "http://radio/stream", stream: true },
    position: 5.62, total: 11, visualizer: "Bars", shuffle: false, repeat: "Off", speed: 1
  })
  const s = M.parseStatus(raw)
  assert.equal(s.running, true)
  assert.equal(s.playing, true)
  assert.equal(s.paused, false)
  assert.equal(s.title, "Lofi Stream")
  assert.equal(s.label, "Lofi Stream")
  assert.equal(s.total, 11)
  assert.equal(s.visualizer, "Bars")
})

test("parseStatus: paused local track with artist", () => {
  const raw = JSON.stringify({
    ok: true, state: "paused",
    track: { title: "Redshift", artist: "Com Truise", path: "/m/x.flac" },
    position: 30, total: 200, repeat: "All", shuffle: true
  })
  const s = M.parseStatus(raw)
  assert.equal(s.paused, true)
  assert.equal(s.playing, false)
  assert.equal(s.label, "Com Truise — Redshift")
  assert.equal(s.shuffle, true)
  assert.equal(s.repeat, "All")
})

test("parseStatus: no title falls back to filename stem", () => {
  const raw = JSON.stringify({ ok: true, state: "playing", track: { path: "/music/03 - Something.mp3" } })
  assert.equal(M.parseStatus(raw).title, "03 - Something")
})

test("parseStatus: leading log noise before JSON is tolerated", () => {
  const s = M.parseStatus('warn: whatever\n{"ok":true,"state":"playing","track":{"title":"T"}}')
  assert.equal(s.running, true)
  assert.equal(s.title, "T")
})

test("parseStatus: ok:false -> empty", () => {
  assert.equal(M.parseStatus('{"ok":false}').running, false)
})

test("parseBands: valid frame -> 10 clamped floats", () => {
  const b = M.parseBands('{"ok":true,"visualizer":"Bars","bands":[0.71,0.55,0.5,0.41,0.21,0.05,0,0,0,0]}')
  assert.equal(b.length, M.BAND_COUNT)
  assert.equal(b[0], 0.71)
  assert.ok(b.every(v => v >= 0 && v <= 1))
})

test("parseBands: over/under range values are clamped", () => {
  const b = M.parseBands('{"bands":[2,-1,0.5,0,0,0,0,0,0,0]}')
  assert.equal(b[0], 1)
  assert.equal(b[1], 0)
})

test("parseBands: short array is padded to 10", () => {
  const b = M.parseBands('{"bands":[0.9,0.8]}')
  assert.equal(b.length, 10)
  assert.equal(b[2], 0)
})

test("parseBands: junk / non-frame lines -> null", () => {
  assert.equal(M.parseBands(""), null)
  assert.equal(M.parseBands("cliamp is not running"), null)
  assert.equal(M.parseBands("{}"), null)
  assert.equal(M.parseBands('{"bands":[]}'), null)
  assert.equal(M.parseBands(null), null)
})

test("idleBands: bounded, 10 wide, moves with phase", () => {
  const a = M.idleBands(0, 0.2)
  const b = M.idleBands(1.5, 0.2)
  assert.equal(a.length, 10)
  assert.ok(a.every(v => v >= 0 && v <= 0.2001))
  assert.notDeepEqual(a, b)
})

test("idleBands: amp 0 collapses flat", () => {
  assert.ok(M.idleBands(2, 0).every(v => v === 0))
})

test("progressFraction", () => {
  assert.equal(M.progressFraction(0, 0), 0)
  assert.equal(M.progressFraction(5, 10), 0.5)
  assert.equal(M.progressFraction(20, 10), 1)
  assert.equal(M.progressFraction(-1, 10), 0)
})

test("formatTime", () => {
  assert.equal(M.formatTime(0), "0:00")
  assert.equal(M.formatTime(5), "0:05")
  assert.equal(M.formatTime(65), "1:05")
  assert.equal(M.formatTime(600), "10:00")
})

test("barLabel / stateMeta", () => {
  assert.equal(M.barLabel(M.emptyStatus()), "cliamp")
  assert.equal(M.stateMeta(M.emptyStatus()), "Not running")
  assert.equal(M.stateMeta({ running: true, playing: true }), "Playing")
  assert.equal(M.stateMeta({ running: true, paused: true }), "Paused")
  assert.equal(M.stateMeta({ running: true }), "Stopped")
})
