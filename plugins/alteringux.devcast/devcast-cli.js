#!/usr/bin/env node
// fs-side bridge for omarchy-devcast: reads a Claude Code transcript, runs the
// pure Model.parseTranscript engine, and writes cast.json + a self-contained
// replay.html (the player template with the cast JSON injected). Also serves
// `stats` for the bar widget. Never throws to the shell — prints an {error}.
"use strict"

const fs = require("fs")
const path = require("path")
const http = require("http")
const readline = require("readline")
const { spawn } = require("child_process")
const Model = require("./Model.js")

function fail(msg) {
  process.stdout.write(JSON.stringify({ error: String(msg) }) + "\n")
  process.exit(1)
}

const op = process.argv[2] || ""

if (op === "build") {
  // argv: build <transcriptPath> <outDir> [--no-redact] [--thinking]
  //       [--no-reads] [--max-gap MS] [--title STR]
  const transcriptPath = process.argv[3]
  const outDir = process.argv[4]
  if (!transcriptPath || !outDir) fail("build needs <transcriptPath> <outDir>")

  const opt = Model.defaultOptions()
  let titleOverride = ""
  const rest = process.argv.slice(5)
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === "--no-redact") opt.redact = false
    else if (rest[i] === "--thinking") opt.includeThinking = true
    else if (rest[i] === "--no-reads") opt.includeReads = false
    else if (rest[i] === "--max-gap") opt.maxGapMs = Math.max(500, +rest[++i] || opt.maxGapMs)
    else if (rest[i] === "--title") titleOverride = rest[++i] || ""
  }

  let raw
  try {
    raw = fs.readFileSync(transcriptPath, "utf8")
  } catch (e) {
    fail("cannot read transcript: " + e.message)
  }

  const cast = Model.parseTranscript(raw, opt)
  if (titleOverride) cast.meta.title = titleOverride
  if (!cast.steps.length) fail("transcript produced no replay steps")

  let template
  try {
    template = fs.readFileSync(path.join(__dirname, "player-template.html"), "utf8")
  } catch (e) {
    fail("cannot read player-template.html: " + e.message)
  }

  fs.mkdirSync(outDir, { recursive: true })
  const castPath = path.join(outDir, "cast.json")
  const htmlPath = path.join(outDir, "replay.html")
  fs.writeFileSync(castPath, JSON.stringify(cast, null, 1))

  // Inject. The cast goes inside a <script type="application/json"> so only
  // "</script" needs neutralising; JSON has no such substring but a transcript
  // string might. Use function replacements so `$` sequences in the data
  // ($&, $1, $' …) are NOT interpreted by String.replace.
  const titleHtml = escapeHtml(cast.meta.title || "devcast")
  const castJson = JSON.stringify(cast).replace(/<\/script/gi, "<\\/script")
  const injected = template
    .replace(/__TITLE__/g, function () { return titleHtml })
    .replace("__CAST__", function () { return castJson })
  fs.writeFileSync(htmlPath, injected)

  process.stdout.write(
    JSON.stringify({
      ok: true,
      outDir: outDir,
      castPath: castPath,
      htmlPath: htmlPath,
      meta: cast.meta,
      stats: cast.stats,
      warnings: cast.warnings || {},
      summary: Model.summaryLine(cast)
    }) + "\n"
  )
  process.exit(0)
}

if (op === "scan") {
  // scan <transcriptPath> -> cheap catalogue metadata, streamed line-by-line so
  // a 30 MB transcript costs no more memory than a 3 KB one. Regex-first; only
  // JSON.parse the handful of lines a field actually needs.
  const p = process.argv[3]
  if (!p) fail("scan needs <transcriptPath>")
  let st
  try {
    st = fs.statSync(p)
  } catch (e) {
    fail("cannot stat: " + e.message)
  }

  const out = {
    sessionId: "",
    title: "",
    project: "",
    gitBranch: "",
    firstTs: null,
    lastTs: null,
    lines: 0,
    toolUses: 0,
    prompts: 0,
    bytes: st.size,
    sourceMtimeMs: Math.round(st.mtimeMs)
  }
  let firstUserPrompt = ""

  const rl = readline.createInterface({
    input: fs.createReadStream(p, { encoding: "utf8" }),
    crlfDelay: Infinity
  })
  rl.on("line", (line) => {
    if (!line) return
    out.lines++

    const tsm = line.match(/"timestamp":"([^"]+)"/)
    if (tsm) {
      const ms = Date.parse(tsm[1])
      if (isFinite(ms)) {
        if (out.firstTs == null) out.firstTs = ms
        out.lastTs = ms
      }
    }

    // tool_use blocks: one "type":"tool_use" per call
    const tu = line.match(/"type":"tool_use"/g)
    if (tu) out.toolUses += tu.length

    if (!out.sessionId) {
      const sm = line.match(/"sessionId":"([^"]+)"/)
      if (sm) out.sessionId = sm[1]
    }
    if (!out.title) {
      const am = line.match(/"aiTitle":"((?:[^"\\]|\\.)*)"/)
      if (am) {
        try {
          out.title = JSON.parse('"' + am[1] + '"').replace(/^[^\p{L}\p{N}"']+/u, "").trim()
        } catch (e) {}
      }
    }
    if (!out.project || !out.gitBranch) {
      const cm = line.match(/"cwd":"((?:[^"\\]|\\.)*)"/)
      if (cm && !out.project) {
        try { out.project = JSON.parse('"' + cm[1] + '"') } catch (e) {}
      }
      const gm = line.match(/"gitBranch":"([^"]*)"/)
      if (gm && gm[1] && !out.gitBranch) out.gitBranch = gm[1]
    }

    // rough prompt count: non-meta user lines that aren't tool results
    if (
      line.indexOf('"type":"user"') !== -1 &&
      line.indexOf('"isMeta":true') === -1 &&
      line.indexOf('"tool_result"') === -1
    ) {
      out.prompts++
      if (!firstUserPrompt) {
        try {
          const rec = JSON.parse(line)
          const c = rec && rec.message && rec.message.content
          const raw = typeof c === "string" ? c : Array.isArray(c) ? (c.find((b) => b && b.type === "text") || {}).text || "" : ""
          const cleaned = Model.cleanPromptText(raw).trim()
          if (cleaned && !/^\/?(clear|compact|resume|cost|help|init|context|export)\b/i.test(cleaned)) {
            firstUserPrompt = cleaned
          }
        } catch (e) {}
      }
    }
  })
  rl.on("close", () => {
    if (!out.title && firstUserPrompt) {
      out.title = firstUserPrompt.split("\n")[0].replace(/^\/\S+\s*/, "").trim()
    }
    if (!out.title) out.title = "session"
    process.stdout.write(JSON.stringify(out) + "\n")
    process.exit(0)
  })
  rl.on("error", (e) => fail("read error: " + e.message))
  return
}

if (op === "catalog") {
  // catalog <projectsDir> [--prev <catalog.json>] [--built <tsv>] [--rebuild]
  // Streams every <projectsDir>/*/*.jsonl into one catalogue, reusing a prior
  // entry when the file's mtime is unchanged, and attaching built/stale from
  // the built-map TSV (sessionId \t castDir \t buildMtimeMs).
  const projectsDir = process.argv[3]
  if (!projectsDir) fail("catalog needs <projectsDir>")
  const args = process.argv.slice(4)
  let prevPath = "",
    builtPath = "",
    rebuild = false
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--prev") prevPath = args[++i]
    else if (args[i] === "--built") builtPath = args[++i]
    else if (args[i] === "--rebuild") rebuild = true
  }

  const prevByPath = {}
  if (prevPath && !rebuild) {
    try {
      const prev = JSON.parse(fs.readFileSync(prevPath, "utf8"))
      // Version 1 fallback titles were clipped before reaching the UI.
      if (prev.version === 2)
        for (const s of prev.sessions || []) if (s.sourcePath) prevByPath[s.sourcePath] = s
    } catch (e) {}
  }
  const builtBySession = {}
  if (builtPath) {
    try {
      for (const ln of fs.readFileSync(builtPath, "utf8").split("\n")) {
        const [sid, dir, mt] = ln.split("\t")
        if (sid && dir) builtBySession[sid] = { dir, mt: Number(mt) || 0 }
      }
    } catch (e) {}
  }

  // enumerate <projectsDir>/*/*.jsonl
  const files = []
  let projects = []
  try {
    projects = fs.readdirSync(projectsDir)
  } catch (e) {
    fail("cannot read projects dir: " + e.message)
  }
  for (const proj of projects) {
    const pdir = path.join(projectsDir, proj)
    let ents = []
    try {
      if (!fs.statSync(pdir).isDirectory()) continue
      ents = fs.readdirSync(pdir)
    } catch (e) {
      continue
    }
    for (const e of ents) if (e.endsWith(".jsonl")) files.push(path.join(pdir, e))
  }

  function scanOne(p) {
    return new Promise((resolve) => {
      let st
      try {
        st = fs.statSync(p)
      } catch (e) {
        return resolve(null)
      }
      const mtimeMs = Math.round(st.mtimeMs)
      const prev = prevByPath[p]
      if (prev && prev.sourceMtimeMs === mtimeMs) return resolve({ ...prev, bytes: st.size })

      const o = {
        sessionId: "",
        title: "",
        project: "",
        gitBranch: "",
        firstTs: null,
        lastTs: null,
        lines: 0,
        toolUses: 0,
        prompts: 0,
        bytes: st.size,
        sourceMtimeMs: mtimeMs,
        sourcePath: p
      }
      let firstUserPrompt = ""
      const rl = readline.createInterface({ input: fs.createReadStream(p, { encoding: "utf8" }), crlfDelay: Infinity })
      rl.on("line", (line) => {
        if (!line) return
        o.lines++
        const tsm = line.match(/"timestamp":"([^"]+)"/)
        if (tsm) {
          const ms = Date.parse(tsm[1])
          if (isFinite(ms)) {
            if (o.firstTs == null) o.firstTs = ms
            o.lastTs = ms
          }
        }
        const tu = line.match(/"type":"tool_use"/g)
        if (tu) o.toolUses += tu.length
        if (!o.sessionId) {
          const sm = line.match(/"sessionId":"([^"]+)"/)
          if (sm) o.sessionId = sm[1]
        }
        if (!o.title) {
          const am = line.match(/"aiTitle":"((?:[^"\\]|\\.)*)"/)
          if (am) {
            try {
              o.title = JSON.parse('"' + am[1] + '"').replace(/^[^\p{L}\p{N}"']+/u, "").trim()
            } catch (e) {}
          }
        }
        if (!o.project) {
          const cm = line.match(/"cwd":"((?:[^"\\]|\\.)*)"/)
          if (cm) {
            try {
              o.project = JSON.parse('"' + cm[1] + '"')
            } catch (e) {}
          }
        }
        if (!o.gitBranch) {
          const gm = line.match(/"gitBranch":"([^"]*)"/)
          if (gm && gm[1]) o.gitBranch = gm[1]
        }
        if (
          line.indexOf('"type":"user"') !== -1 &&
          line.indexOf('"isMeta":true') === -1 &&
          line.indexOf('"tool_result"') === -1
        ) {
          o.prompts++
          if (!firstUserPrompt) {
            try {
              const rec = JSON.parse(line)
              const c = rec && rec.message && rec.message.content
              const raw =
                typeof c === "string"
                  ? c
                  : Array.isArray(c)
                  ? (c.find((b) => b && b.type === "text") || {}).text || ""
                  : ""
              const cleaned = Model.cleanPromptText(raw).trim()
              if (cleaned && !/^\/?(clear|compact|resume|cost|help|init|context|export)\b/i.test(cleaned))
                firstUserPrompt = cleaned
            } catch (e) {}
          }
        }
      })
      rl.on("close", () => {
        if (!o.title && firstUserPrompt)
          o.title = firstUserPrompt.split("\n")[0].replace(/^\/\S+\s*/, "").trim()
        if (!o.title) o.title = "session"
        resolve(o)
      })
      rl.on("error", () => resolve(o))
    })
  }

  ;(async () => {
    const sessions = []
    const POOL = 8
    for (let i = 0; i < files.length; i += POOL) {
      const batch = await Promise.all(files.slice(i, i + POOL).map(scanOne))
      for (const s of batch) {
        if (!s) continue
        const b = s.sessionId && builtBySession[s.sessionId]
        const stale = !!(b && s.sourceMtimeMs > b.mt)
        // `built` is the path the UI may open. A stale path is still kept on
        // disk for replacement, but must not be presented as current.
        s.built = b && !stale ? b.dir : null
        s.stale = stale
        sessions.push(s)
      }
    }
    sessions.sort((a, b) => (b.lastTs || 0) - (a.lastTs || 0))
    process.stdout.write(
      JSON.stringify({ version: 2, updatedAt: Date.now(), count: sessions.length, sessions }) + "\n"
    )
    process.exit(0)
  })()
  return
}

if (op === "stats") {
  // argv: stats <castJsonPath>
  const castPath = process.argv[3]
  if (!castPath) fail("stats needs <castJsonPath>")
  let cast
  try {
    cast = JSON.parse(fs.readFileSync(castPath, "utf8"))
  } catch (e) {
    fail("cannot read cast: " + e.message)
  }
  process.stdout.write(
    JSON.stringify({
      meta: cast.meta,
      stats: cast.stats,
      summary: Model.summaryLine(cast),
      duration: Model.formatDuration(cast.stats && cast.stats.durationMs)
    }) + "\n"
  )
  process.exit(0)
}

if (op === "export-frames") {
  // export-frames <chromiumBin> <htmlPath> <framesDir> <fps> <w> <h> <theme> <totalMs> <maxFrames>
  // Drives ONE headless chromium over the DevTools protocol (Node's global
  // WebSocket, no npm) — navigate once, then seek + screenshot per frame. Far
  // faster than one chromium invocation per frame.
  const [bin, htmlPath, framesDir, fpsS, wS, hS, theme, totalS, maxS] = process.argv.slice(3)
  if (!bin || !htmlPath || !framesDir) fail("export-frames: missing args")
  const fps = Math.max(1, +fpsS || 8)
  const W = Math.max(160, +wS || 1280)
  const H = Math.max(120, +hS || 720)
  const totalMs = Math.max(1000, +totalS || 10000)
  const maxFrames = Math.max(2, +maxS || 240)
  let frames = Math.min(maxFrames, Math.ceil((totalMs / 1000) * fps) + 1)

  exportFrames({ bin, htmlPath, framesDir, fps, W, H, theme, frames })
    .then((n) => {
      process.stdout.write(JSON.stringify({ ok: true, frames: n }) + "\n")
      process.exit(0)
    })
    .catch((e) => fail("export-frames: " + (e && e.message ? e.message : e)))
  return
}

fail("unknown op '" + op + "' (build | stats | scan | catalog | export-frames)")

async function exportFrames(o) {
  fs.mkdirSync(o.framesDir, { recursive: true })
  const port = 40000 + Math.floor(Math.random() * 20000)
  const child = spawn(
    o.bin,
    [
      "--headless=new",
      "--remote-debugging-port=" + port,
      "--remote-allow-origins=*",
      "--hide-scrollbars",
      "--disable-gpu",
      "--disable-dev-shm-usage",
      "--no-sandbox",
      "--no-first-run",
      "--force-device-scale-factor=1",
      "--window-size=" + o.W + "," + o.H,
      "about:blank"
    ],
    { stdio: "ignore" }
  )

  const cleanup = () => { try { child.kill("SIGKILL") } catch (e) {} }
  try {
    const target = await waitForTarget(port, 8000)
    const ws = new WebSocket(target)
    await new Promise((res, rej) => {
      ws.onopen = res
      ws.onerror = () => rej(new Error("devtools websocket failed"))
    })

    let msgId = 0
    const pending = new Map()
    let onLoad = null
    ws.onmessage = (ev) => {
      let m
      try { m = JSON.parse(ev.data) } catch (e) { return }
      if (m.id && pending.has(m.id)) {
        const p = pending.get(m.id)
        pending.delete(m.id)
        m.error ? p.rej(new Error(m.error.message)) : p.res(m.result)
      } else if (m.method === "Page.loadEventFired" && onLoad) {
        onLoad()
      }
    }
    const send = (method, params) =>
      new Promise((res, rej) => {
        const id = ++msgId
        pending.set(id, { res, rej })
        ws.send(JSON.stringify({ id, method, params: params || {} }))
      })

    await send("Page.enable")
    await send("Runtime.enable")
    // Pin the viewport to exactly W×H so the player's 100vh fixed layout fills
    // the frame and every screenshot is the same size (libx264 needs that).
    await send("Emulation.setDeviceMetricsOverride", {
      width: o.W,
      height: o.H,
      deviceScaleFactor: 1,
      mobile: false,
      screenWidth: o.W,
      screenHeight: o.H
    })
    const loaded = new Promise((res) => (onLoad = res))
    const fileUrl = "file://" + o.htmlPath + "?chrome=hidden&theme=" + (o.theme || "dark")
    await send("Page.navigate", { url: fileUrl })
    await Promise.race([loaded, sleep(4000)])
    await sleep(400) // font / layout settle

    const clip = { x: 0, y: 0, width: o.W, height: o.H, scale: 1 }
    for (let i = 0; i < o.frames; i++) {
      const ms = Math.round((i / o.fps) * 1000)
      await send("Runtime.evaluate", {
        expression: "window.__devcastSeek && window.__devcastSeek(" + ms + ");true"
      })
      const shot = await send("Page.captureScreenshot", { format: "png", clip: clip, captureBeyondViewport: false })
      fs.writeFileSync(
        path.join(o.framesDir, "f_" + String(i).padStart(5, "0") + ".png"),
        Buffer.from(shot.data, "base64")
      )
    }
    ws.close()
    cleanup()
    return o.frames
  } catch (e) {
    cleanup()
    throw e
  }
}

function waitForTarget(port, timeoutMs) {
  const deadline = Date.now() + timeoutMs
  return new Promise((resolve, reject) => {
    const tryOnce = () => {
      const req = http.get({ host: "127.0.0.1", port, path: "/json/list", timeout: 1000 }, (res) => {
        let body = ""
        res.on("data", (d) => (body += d))
        res.on("end", () => {
          try {
            const list = JSON.parse(body)
            const page = list.find((t) => t.type === "page" && t.webSocketDebuggerUrl)
            if (page) return resolve(page.webSocketDebuggerUrl)
          } catch (e) {}
          retry()
        })
      })
      req.on("error", retry)
      req.on("timeout", () => { req.destroy(); retry() })
    }
    const retry = () => {
      if (Date.now() > deadline) return reject(new Error("chromium devtools did not come up"))
      setTimeout(tryOnce, 250)
    }
    tryOnce()
  })
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms))
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"]/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]
  })
}
