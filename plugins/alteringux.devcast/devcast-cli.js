#!/usr/bin/env node
// fs-side bridge for omarchy-devcast: reads a Claude Code transcript, runs the
// pure Model.parseTranscript engine, and writes cast.json + a self-contained
// replay.html (the player template with the cast JSON injected). Also serves
// `stats` for the bar widget. Never throws to the shell — prints an {error}.
"use strict"

const fs = require("fs")
const path = require("path")
const http = require("http")
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

fail("unknown op '" + op + "' (build | stats | export-frames)")

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
