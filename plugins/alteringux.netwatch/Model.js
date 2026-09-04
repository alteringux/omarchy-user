// Pure logic for the netwatch plugin: config/state defaults, the counter-delta
// → rate → rollup engine (`ingest`), and the read-side projections the bar
// widget and panel render (`status`, `report`, `sparkline`). No QML / Quickshell
// APIs so it can be reasoned about and unit-tested with `node --test`.
//
// The one non-obvious idea: /proc/net/dev only exposes *cumulative* byte
// counters since boot. "How much today" is not something the kernel tracks — we
// sample the counter on a cadence, take the delta since the previous sample,
// and accumulate those deltas into our own hour/day/month buckets. A delta that
// comes back negative (reboot, interface reset, 32-bit wrap) is discarded, not
// stored as a negative.

var MB = 1e6
var GB = 1e9
var MBPS_TO_BPS = 125000 // 1 Mbit/s = 1e6/8 bytes/s

function num(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function defaultConfig() {
  return {
    iface: "auto", // "auto" = follow the default route; or a fixed name e.g. "wlp2s0"
    sampleIntervalSec: 20, // cadence the systemd timer / widget calls `sample`
    monthlyQuotaGB: 0, // 0 = unlimited; >0 drives the quota % + 80/100 alerts
    quotaCountsTx: true, // count upload toward the cap too (typical for mobile plans)
    spikeMbps: 50, // sustained combined rate above this raises an info alert
    ratesRingSize: 180, // ~1h of 20s samples kept for the live sparkline
    hourlyCap: 72, // 3 days of hourly buckets
    dailyCap: 90,
    monthlyCap: 24,
    webhook: "" // optional n8n webhook URL; POSTed the status on every sample
  }
}

function defaultState() {
  return {
    version: 1,
    iface: "",
    up: false,
    isVpn: false,
    updatedAt: 0,
    rx: { rate: 0, total: 0 },
    tx: { rate: 0, total: 0 },
    rates: [], // ring of { ts, rx, tx } — rx/tx are bytes/sec
    buckets: { hourly: {}, daily: {}, monthly: {} }, // key -> { rx, tx } in bytes
    peak: { rx: 0, tx: 0, ts: 0 },
    quota: { pct: 0, usedBytes: 0, limitBytes: 0 },
    alerts: { month: "", quota80: 0, quota100: 0, spikeTs: 0 }
  }
}

// ── tolerant parsers ───────────────────────────────────────────────────────

function parseConfig(raw) {
  var parsed = defaultConfig()
  if (!raw || raw.length === 0) return parsed
  try {
    var stored = typeof raw === "string" ? JSON.parse(raw) : raw
    if (stored && typeof stored === "object") {
      for (var key in parsed) if (stored[key] !== undefined) parsed[key] = stored[key]
    }
  } catch (e) {
    console.warn("netwatch: config parse failed:", e)
  }
  // Guard the numerics a hand-edit could break.
  parsed.sampleIntervalSec = Math.max(1, num(parsed.sampleIntervalSec, 20))
  parsed.monthlyQuotaGB = Math.max(0, num(parsed.monthlyQuotaGB, 0))
  parsed.spikeMbps = Math.max(0, num(parsed.spikeMbps, 50))
  parsed.ratesRingSize = Math.max(10, num(parsed.ratesRingSize, 180))
  parsed.hourlyCap = Math.max(1, num(parsed.hourlyCap, 72))
  parsed.dailyCap = Math.max(1, num(parsed.dailyCap, 90))
  parsed.monthlyCap = Math.max(1, num(parsed.monthlyCap, 24))
  return parsed
}

function parseState(raw) {
  var parsed = defaultState()
  if (!raw || raw.length === 0) return parsed
  try {
    var stored = typeof raw === "string" ? JSON.parse(raw) : raw
    if (stored && typeof stored === "object") {
      parsed.iface = typeof stored.iface === "string" ? stored.iface : ""
      parsed.up = !!stored.up
      parsed.isVpn = !!stored.isVpn
      parsed.updatedAt = num(stored.updatedAt, 0)
      if (stored.rx && typeof stored.rx === "object")
        parsed.rx = { rate: num(stored.rx.rate, 0), total: num(stored.rx.total, 0) }
      if (stored.tx && typeof stored.tx === "object")
        parsed.tx = { rate: num(stored.tx.rate, 0), total: num(stored.tx.total, 0) }
      if (Array.isArray(stored.rates)) parsed.rates = stored.rates
      if (stored.buckets && typeof stored.buckets === "object") {
        parsed.buckets.hourly = stored.buckets.hourly || {}
        parsed.buckets.daily = stored.buckets.daily || {}
        parsed.buckets.monthly = stored.buckets.monthly || {}
      }
      if (stored.peak && typeof stored.peak === "object")
        parsed.peak = { rx: num(stored.peak.rx, 0), tx: num(stored.peak.tx, 0), ts: num(stored.peak.ts, 0) }
      if (stored.quota && typeof stored.quota === "object")
        parsed.quota = {
          pct: num(stored.quota.pct, 0),
          usedBytes: num(stored.quota.usedBytes, 0),
          limitBytes: num(stored.quota.limitBytes, 0)
        }
      if (stored.alerts && typeof stored.alerts === "object")
        parsed.alerts = {
          month: typeof stored.alerts.month === "string" ? stored.alerts.month : "",
          quota80: num(stored.alerts.quota80, 0),
          quota100: num(stored.alerts.quota100, 0),
          spikeTs: num(stored.alerts.spikeTs, 0)
        }
    }
  } catch (e) {
    console.warn("netwatch: state parse failed:", e)
  }
  return parsed
}

// Last raw counter reading, kept between `sample` invocations so a delta can be
// taken. { ts, iface, rxBytes, txBytes }.
function parseSample(raw) {
  if (!raw || raw.length === 0) return null
  try {
    var s = typeof raw === "string" ? JSON.parse(raw) : raw
    if (!s || typeof s !== "object") return null
    return {
      ts: num(s.ts, 0),
      iface: typeof s.iface === "string" ? s.iface : "",
      rxBytes: num(s.rxBytes, 0),
      txBytes: num(s.txBytes, 0)
    }
  } catch (e) {
    return null
  }
}

// ── time keys (local time, no dependencies) ────────────────────────────────

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}
function dayKey(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}
function hourKey(d) {
  return dayKey(d) + "T" + pad2(d.getHours())
}
function monthKey(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1)
}

// Prune a { key -> {rx,tx} } map to its `cap` most recent keys. ISO keys sort
// chronologically as plain strings, so a lexical sort is a time sort.
function capBuckets(map, cap) {
  var keys = Object.keys(map).sort()
  if (keys.length <= cap) return map
  var keep = keys.slice(keys.length - cap)
  var out = {}
  for (var i = 0; i < keep.length; i++) out[keep[i]] = map[keep[i]]
  return out
}

function addToBucket(map, key, rx, tx) {
  var cur = map[key] || { rx: 0, tx: 0 }
  map[key] = { rx: cur.rx + rx, tx: cur.tx + tx }
}

// ── the engine ────────────────────────────────────────────────────────────

// ingest(state, prevSample, cur, config, now) -> { state, sample, alerts }
//   cur: { ts, rxBytes, txBytes, iface, up, isVpn } — raw cumulative counters
//   Discards the delta (records the sample only) on the first run, an interface
//   change, or a counter that went backwards.
function ingest(state, prevSample, cur, config, now) {
  var s = JSON.parse(JSON.stringify(state || defaultState()))
  var cfg = parseConfig(config || {})
  var t = num(now, Date.now())
  var alerts = []

  s.iface = cur.iface || s.iface
  s.up = !!cur.up
  s.isVpn = !!cur.isVpn
  s.updatedAt = t
  s.rx.total = num(cur.rxBytes, 0)
  s.tx.total = num(cur.txBytes, 0)

  var sample = { ts: num(cur.ts, t), iface: cur.iface || "", rxBytes: num(cur.rxBytes, 0), txBytes: num(cur.txBytes, 0) }

  var usable =
    prevSample &&
    prevSample.iface === sample.iface &&
    sample.ts > prevSample.ts &&
    sample.rxBytes >= prevSample.rxBytes &&
    sample.txBytes >= prevSample.txBytes

  if (usable) {
    var dt = (sample.ts - prevSample.ts) / 1000
    var rxDelta = sample.rxBytes - prevSample.rxBytes
    var txDelta = sample.txBytes - prevSample.txBytes
    var rxRate = dt > 0 ? rxDelta / dt : 0
    var txRate = dt > 0 ? txDelta / dt : 0

    s.rx.rate = rxRate
    s.tx.rate = txRate

    s.rates.push({ ts: t, rx: rxRate, tx: txRate })
    if (s.rates.length > cfg.ratesRingSize) s.rates = s.rates.slice(s.rates.length - cfg.ratesRingSize)

    var d = new Date(t)
    addToBucket(s.buckets.hourly, hourKey(d), rxDelta, txDelta)
    addToBucket(s.buckets.daily, dayKey(d), rxDelta, txDelta)
    addToBucket(s.buckets.monthly, monthKey(d), rxDelta, txDelta)
    s.buckets.hourly = capBuckets(s.buckets.hourly, cfg.hourlyCap)
    s.buckets.daily = capBuckets(s.buckets.daily, cfg.dailyCap)
    s.buckets.monthly = capBuckets(s.buckets.monthly, cfg.monthlyCap)

    if (rxRate > s.peak.rx || txRate > s.peak.tx) {
      s.peak = { rx: Math.max(rxRate, s.peak.rx), tx: Math.max(txRate, s.peak.tx), ts: t }
    }

    // ── quota accounting + 80 / 100% alerts, reset each calendar month ──
    var mk = monthKey(new Date(t))
    if (s.alerts.month !== mk) {
      s.alerts.month = mk
      s.alerts.quota80 = 0
      s.alerts.quota100 = 0
    }
    var monthBucket = s.buckets.monthly[mk] || { rx: 0, tx: 0 }
    var used = monthBucket.rx + (cfg.quotaCountsTx ? monthBucket.tx : 0)
    var limit = cfg.monthlyQuotaGB * GB
    var pct = limit > 0 ? (used / limit) * 100 : 0
    s.quota = { pct: pct, usedBytes: used, limitBytes: limit }

    if (limit > 0) {
      if (pct >= 100 && !s.alerts.quota100) {
        s.alerts.quota100 = t
        alerts.push({
          kind: "quota100",
          level: "critical",
          attention: true,
          msg: "Monthly data cap reached (" + formatBytes(limit) + ")"
        })
      } else if (pct >= 80 && !s.alerts.quota80) {
        s.alerts.quota80 = t
        alerts.push({
          kind: "quota80",
          level: "warning",
          attention: true,
          msg: "Monthly data at " + Math.round(pct) + "% (" + formatBytes(used) + " / " + cfg.monthlyQuotaGB + " GB)"
        })
      }
    }

    // ── sustained-spike alert: last 3 ring samples all over the threshold,
    //    10-minute cooldown so it doesn't chatter ──
    var spikeBps = cfg.spikeMbps * MBPS_TO_BPS
    if (spikeBps > 0 && s.rates.length >= 3) {
      var tail = s.rates.slice(s.rates.length - 3)
      var sustained = tail.every(function (r) {
        return r.rx + r.tx >= spikeBps
      })
      if (sustained && t - s.alerts.spikeTs > 10 * 60 * 1000) {
        s.alerts.spikeTs = t
        alerts.push({
          kind: "spike",
          level: "info",
          attention: false,
          msg: "Sustained " + compactRate(rxRate + txRate) + "/s (over " + cfg.spikeMbps + " Mbps) on " + s.iface
        })
      }
    }
  } else {
    // No usable delta this round — rate decays to 0 so a stale widget doesn't
    // keep showing the last burst forever.
    s.rx.rate = 0
    s.tx.rate = 0
  }

  return { state: s, sample: sample, alerts: alerts }
}

// ── read-side projections ─────────────────────────────────────────────────

function sumBuckets(map, keys) {
  var rx = 0
  var tx = 0
  for (var i = 0; i < keys.length; i++) {
    var b = map[keys[i]]
    if (b) {
      rx += num(b.rx, 0)
      tx += num(b.tx, 0)
    }
  }
  return { rx: rx, tx: tx, total: rx + tx }
}

function lastNDayKeys(n, now) {
  var out = []
  for (var i = n - 1; i >= 0; i--) {
    var d = new Date(num(now, Date.now()))
    d.setDate(d.getDate() - i)
    out.push(dayKey(d))
  }
  return out
}

// status(state, config, now) -> the flat object the bar widget + IPC render.
function status(state, config, now) {
  var s = parseState(state)
  var cfg = parseConfig(config)
  var t = num(now, Date.now())
  var d = new Date(t)

  var today = s.buckets.daily[dayKey(d)] || { rx: 0, tx: 0 }
  var week = sumBuckets(s.buckets.daily, lastNDayKeys(7, t))
  var month = s.buckets.monthly[monthKey(d)] || { rx: 0, tx: 0 }

  var ageMs = s.updatedAt ? t - s.updatedAt : Infinity
  var stale = ageMs > cfg.sampleIntervalSec * 3 * 1000

  return {
    iface: s.iface,
    up: s.up,
    isVpn: s.isVpn,
    rxRate: s.rx.rate,
    txRate: s.tx.rate,
    rxRateStr: formatRate(s.rx.rate),
    txRateStr: formatRate(s.tx.rate),
    label: (stale ? "— " : "") + "↓" + compactRate(s.rx.rate) + " ↑" + compactRate(s.tx.rate),
    today: { rx: today.rx, tx: today.tx, total: today.rx + today.tx },
    week: week,
    month: { rx: month.rx, tx: month.tx, total: month.rx + month.tx },
    peak: s.peak,
    quota: {
      enabled: cfg.monthlyQuotaGB > 0,
      pct: s.quota.pct,
      usedBytes: s.quota.usedBytes,
      limitBytes: s.quota.limitBytes,
      limitGB: cfg.monthlyQuotaGB
    },
    sampleAgeMs: ageMs === Infinity ? -1 : ageMs,
    stale: stale
  }
}

// report(state, range, now) -> { range, total, peak, series:[{label,rx,tx}] }
//   range: "today" (24 hourly points) | "week" (7 daily) | "month" (daily, MTD)
function report(state, range, now) {
  var s = parseState(state)
  var t = num(now, Date.now())
  var d = new Date(t)
  var series = []

  if (range === "week") {
    var keys = lastNDayKeys(7, t)
    for (var i = 0; i < keys.length; i++) {
      var b = s.buckets.daily[keys[i]] || { rx: 0, tx: 0 }
      series.push({ label: keys[i].slice(5), rx: b.rx, tx: b.tx })
    }
  } else if (range === "month") {
    var mk = monthKey(d)
    var daysInMonth = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()
    for (var day = 1; day <= daysInMonth; day++) {
      var key = mk + "-" + pad2(day)
      var mb = s.buckets.daily[key] || { rx: 0, tx: 0 }
      series.push({ label: pad2(day), rx: mb.rx, tx: mb.tx })
    }
  } else {
    range = "today"
    var dk = dayKey(d)
    for (var h = 0; h < 24; h++) {
      var hb = s.buckets.hourly[dk + "T" + pad2(h)] || { rx: 0, tx: 0 }
      series.push({ label: pad2(h), rx: hb.rx, tx: hb.tx })
    }
  }

  var total = { rx: 0, tx: 0 }
  var peak = { rx: 0, tx: 0, label: "" }
  for (var j = 0; j < series.length; j++) {
    total.rx += series[j].rx
    total.tx += series[j].tx
    if (series[j].rx + series[j].tx > peak.rx + peak.tx) {
      peak = { rx: series[j].rx, tx: series[j].tx, label: series[j].label }
    }
  }
  total.total = total.rx + total.tx

  return { range: range, total: total, peak: peak, series: series }
}

// sparkline(state, n) -> { rx:[bps...], tx:[bps...], max, n } from the live ring.
function sparkline(state, n) {
  var s = parseState(state)
  var count = Math.max(1, num(n, 40))
  var tail = s.rates.slice(Math.max(0, s.rates.length - count))
  var rx = []
  var tx = []
  var max = 1
  for (var i = 0; i < tail.length; i++) {
    rx.push(tail[i].rx)
    tx.push(tail[i].tx)
    if (tail[i].rx > max) max = tail[i].rx
    if (tail[i].tx > max) max = tail[i].tx
  }
  return { rx: rx, tx: tx, max: max, n: tail.length }
}

// ── formatting ────────────────────────────────────────────────────────────

// Decimal units (1 kB = 1000 B) to match how ISPs and `ip`/`vnstat` count.
function formatBytes(n) {
  var v = num(n, 0)
  if (v < 1000) return v.toFixed(0) + " B"
  if (v < 1e6) return (v / 1e3).toFixed(1) + " kB"
  if (v < 1e9) return (v / 1e6).toFixed(1) + " MB"
  if (v < 1e12) return (v / 1e9).toFixed(2) + " GB"
  return (v / 1e12).toFixed(2) + " TB"
}

function formatRate(bps) {
  var v = num(bps, 0)
  if (v < 1) return "0 B/s"
  if (v < 1e3) return v.toFixed(0) + " B/s"
  if (v < 1e6) return (v / 1e3).toFixed(1) + " kB/s"
  if (v < 1e9) return (v / 1e6).toFixed(2) + " MB/s"
  return (v / 1e9).toFixed(2) + " GB/s"
}

// Very short, for the bar label: "1.2M", "930k", "0".
function compactRate(bps) {
  var v = num(bps, 0)
  if (v < 1e3) return "0"
  if (v < 1e6) return (v / 1e3).toFixed(0) + "k"
  if (v < 1e9) return (v / 1e6).toFixed(1) + "M"
  return (v / 1e9).toFixed(1) + "G"
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultConfig: defaultConfig,
    defaultState: defaultState,
    parseConfig: parseConfig,
    parseState: parseState,
    parseSample: parseSample,
    ingest: ingest,
    status: status,
    report: report,
    sparkline: sparkline,
    formatBytes: formatBytes,
    formatRate: formatRate,
    compactRate: compactRate,
    dayKey: dayKey,
    hourKey: hourKey,
    monthKey: monthKey
  }
}
