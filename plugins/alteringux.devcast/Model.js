// Pure logic for the devcast plugin: turn a Claude Code session transcript
// (~/.claude/projects/<slug>/<session-id>.jsonl — one JSON object per line)
// into an ordered list of replay "steps", plus a redaction pass and summary
// stats. No QML / Node-fs APIs so it can be unit-tested with `node --test`.
//
// Transcript shapes that matter (everything else is metadata we skip):
//   { type:"assistant", timestamp, message:{ content:[ blocks ] } }
//     block: { type:"thinking", thinking } | { type:"text", text }
//           | { type:"tool_use", id, name, input }
//   { type:"user", timestamp, isMeta?, message:{ content: string | [ blocks ] } }
//     block: { type:"text", text } | { type:"tool_result", tool_use_id, is_error, content }
//   { type:"ai-title", aiTitle }
//   { type:"system", isMeta, subtype, ... }

// ── redaction ─────────────────────────────────────────────────────────────

var SECRET_PATTERNS = [
  [/sk-(?:ant-)?[A-Za-z0-9_-]{16,}/g, "sk-••••"],
  [/ghp_[A-Za-z0-9]{20,}/g, "ghp_••••"],
  [/github_pat_[A-Za-z0-9_]{20,}/g, "github_pat_••••"],
  [/xox[baprs]-[A-Za-z0-9-]{10,}/g, "xox•-••••"],
  [/AKIA[0-9A-Z]{16}/g, "AKIA••••"],
  [/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g, "eyJ•••.jwt.•••"],
  // key: value / key=value where the key names a credential
  [/((?:authorization|api[-_ ]?key|access[-_ ]?token|auth[-_ ]?token|secret|password|passwd|bearer|client[-_ ]?secret)\s*[:=]\s*)("?)([^\s"']{4,})\2/gi, "$1$2••••$2"],
  // ENV_VAR=... when the var name looks credential-ish
  [/\b([A-Z0-9_]*(?:SECRET|TOKEN|PASSWORD|PASSWD|API_?KEY|APIKEY)[A-Z0-9_]*=)(\S+)/g, "$1••••"],
  // long opaque blobs
  [/\b[A-Fa-f0-9]{40,}\b/g, "••••"],
  [/\b[A-Za-z0-9+/]{64,}={0,2}\b/g, "••••"]
]

function redactString(str) {
  if (typeof str !== "string" || !str) return { text: str || "", hits: 0 }
  var hits = 0
  var out = str
  for (var i = 0; i < SECRET_PATTERNS.length; i++) {
    out = out.replace(SECRET_PATTERNS[i][0], function () {
      hits++
      // support $1/$2 backrefs in the replacement string
      var repl = SECRET_PATTERNS[i][1]
      var args = arguments
      return repl.replace(/\$(\d)/g, function (m, n) {
        return args[Number(n)] !== undefined ? args[Number(n)] : ""
      })
    })
  }
  return { text: out, hits: hits }
}

// ── helpers ──────────────────────────────────────────────────────────────

function basename(p) {
  if (!p) return ""
  var parts = String(p).split("/")
  return parts[parts.length - 1] || String(p)
}

var EXT_LANG = {
  js: "javascript", mjs: "javascript", ts: "typescript", jsx: "javascript",
  json: "json", sh: "bash", bash: "bash", zsh: "bash", py: "python",
  qml: "qml", lua: "lua", md: "markdown", html: "html", css: "css",
  toml: "toml", yaml: "yaml", yml: "yaml", conf: "ini", ini: "ini"
}
function langForPath(p) {
  var ext = basename(p).split(".").pop().toLowerCase()
  return EXT_LANG[ext] || "text"
}

function lineCount(s) {
  if (!s) return 0
  return String(s).replace(/\n$/, "").split("\n").length
}

function truncateBody(text, maxLines) {
  var lines = String(text || "").split("\n")
  if (lines.length <= maxLines) return { text: String(text || ""), truncated: 0 }
  var kept = lines.slice(0, maxLines).join("\n")
  return { text: kept, truncated: lines.length - maxLines }
}

function isoToMs(ts) {
  var n = Date.parse(ts || "")
  return isFinite(n) ? n : null
}

// A Claude Code slash-command prompt is wrapped in <command-name>/<command-*>
// tags with a big skill body appended. Pull out the human-visible gist.
function cleanPromptText(raw) {
  var s = String(raw || "")
  var m = s.match(/<command-name>([^<]+)<\/command-name>/)
  var args = s.match(/<command-args>([\s\S]*?)<\/command-args>/)
  if (m) {
    var name = m[1].trim()
    var a = args && args[1] ? args[1].trim() : ""
    return "/" + name.replace(/^\//, "") + (a ? " " + a : "")
  }
  // strip system-reminder / attachment noise
  s = s.replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, "").trim()
  s = s.replace(/<local-command-[\s\S]*?<\/local-command-[a-z]+>/g, "").trim()
  return s
}

// ── tool-step rendering ──────────────────────────────────────────────────

// Build a readable "diff" for an Edit without a real diff algorithm: the
// removed block prefixed with "- ", the added block with "+ ".
function editDiff(input) {
  var edits = Array.isArray(input.edits) ? input.edits : [input]
  return edits.map(function (edit) {
    var oldL = String(edit && edit.old_string || "").split("\n")
    var newL = String(edit && edit.new_string || "").split("\n")
    var out = []
    for (var i = 0; i < oldL.length; i++) out.push("- " + oldL[i])
    for (var j = 0; j < newL.length; j++) out.push("+ " + newL[j])
    return out.join("\n")
  }).join("\n")
}

function toolStepFrom(block) {
  var name = block.name || "tool"
  var input = block.input || {}
  var step = { kind: "tool", tool: name, title: "", lang: "text", body: "", note: "", linesAdded: 0, linesRemoved: 0, files: [] }

  switch (name) {
    case "Bash":
      step.title = input.description || "shell"
      step.lang = "bash"
      step.body = String(input.command || "")
      break
    case "Edit":
    case "MultiEdit":
      step.title = basename(input.file_path)
      step.lang = "diff"
      step.body = editDiff(input)
      step.files = [basename(input.file_path)]
      var edits = Array.isArray(input.edits) ? input.edits : [input]
      for (var e = 0; e < edits.length; e++) {
        step.linesAdded += lineCount(edits[e] && edits[e].new_string)
        step.linesRemoved += lineCount(edits[e] && edits[e].old_string)
        if (edits[e] && edits[e].replace_all) step.note = "replace all"
      }
      break
    case "Write":
      step.title = basename(input.file_path) + "  (write)"
      step.lang = langForPath(input.file_path)
      var t = truncateBody(input.content, 320)
      step.body = t.text
      if (t.truncated) step.note = "+" + t.truncated + " more lines"
      step.files = [basename(input.file_path)]
      step.linesAdded = lineCount(input.content)
      break
    case "Read":
      step.title = basename(input.file_path)
      step.lang = "text"
      step.body = "(read" + (input.offset ? " from line " + input.offset : "") + (input.limit ? ", " + input.limit + " lines" : "") + ")"
      break
    case "Skill":
      step.title = "skill: " + (input.skill || "?")
      step.body = input.args ? String(input.args) : ""
      break
    case "Task":
    case "Agent":
      step.title = (input.subagent_type || "agent") + ": " + (input.description || "")
      step.lang = "text"
      step.body = String(input.prompt || "")
      break
    case "Glob":
    case "Grep":
      step.title = name + "  " + (input.pattern || "")
      step.body = [input.path && "path: " + input.path, input.glob && "glob: " + input.glob, input.output_mode && "mode: " + input.output_mode].filter(Boolean).join("\n")
      break
    case "AskUserQuestion":
      step.title = "ask the user"
      step.lang = "text"
      try {
        step.body = (input.questions || [])
          .map(function (q) {
            return "Q: " + q.question + "\n" + (q.options || []).map(function (o) { return "  • " + o.label }).join("\n")
          })
          .join("\n\n")
      } catch (e) {
        step.body = ""
      }
      break
    case "TodoWrite":
      step.title = "todo list"
      step.lang = "text"
      try {
        step.body = (input.todos || []).map(function (td) {
          var mark = td.status === "completed" ? "[x]" : td.status === "in_progress" ? "[~]" : "[ ]"
          return mark + " " + (td.content || "")
        }).join("\n")
      } catch (e) { step.body = "" }
      break
    default:
      step.title = name
      step.lang = "json"
      step.generic = true // no dedicated renderer — feeds the "unknown-tool" signal
      try {
        step.body = JSON.stringify(input, null, 2)
      } catch (e) {
        step.body = String(input)
      }
      var tt = truncateBody(step.body, 120)
      step.body = tt.text
      if (tt.truncated) step.note = "+" + tt.truncated + " more lines"
  }
  return step
}

// ── main parse ───────────────────────────────────────────────────────────

function defaultOptions() {
  return {
    redact: true,
    includeThinking: false,
    includeReads: true,
    maxGapMs: 6000, // clamp idle gaps for playback pacing
    tailPadMs: 2500, // hold on the last step
    typewriterCps: 45 // chars/sec used to size a step's dwell time
  }
}

// parseTranscript(text, options) -> { meta, steps, stats }
//   meta:  { title, sessionId, project, gitBranch, version, startedAt, endedAt }
//   steps: [{ kind:"prompt"|"narration"|"thinking"|"tool", ts, t, playT, dwell,
//             text?, tool?, title?, lang?, body?, note?, result? }]
//   stats: { durationMs, playDurationMs, counts, tools, files, linesAdded,
//            linesRemoved, redactions }
function parseTranscript(text, options) {
  var opt = Object.assign(defaultOptions(), options || {})
  var lines = String(text || "").split("\n")
  var records = []
  for (var i = 0; i < lines.length; i++) {
    var ln = lines[i].trim()
    if (!ln) continue
    try {
      records.push(JSON.parse(ln))
    } catch (e) {
      /* skip a torn line */
    }
  }

  var meta = { title: "", sessionId: "", project: "", gitBranch: "", version: "", startedAt: null, endedAt: null }
  var toolResults = {} // id -> { output, isError }
  var redactions = 0

  function red(s) {
    if (!opt.redact) return s || ""
    var r = redactString(s)
    redactions += r.hits
    return r.text
  }

  // pass 1 — metadata + tool results
  for (var p = 0; p < records.length; p++) {
    var r = records[p]
    if (!r || typeof r !== "object") continue
    if (r.type === "ai-title" && r.aiTitle && !meta.title) {
      // drop any leading decoration (fork glyphs, arrows, whitespace) before
      // the first real letter/digit/quote
      meta.title = String(r.aiTitle).replace(/^[^\p{L}\p{N}"']+/u, "").trim()
    }
    if (r.sessionId && !meta.sessionId) meta.sessionId = r.sessionId
    if (r.cwd && !meta.project) meta.project = r.cwd
    if (r.gitBranch && !meta.gitBranch) meta.gitBranch = r.gitBranch
    if (r.version && !meta.version) meta.version = r.version
    if (r.type === "user" && r.message && Array.isArray(r.message.content)) {
      for (var c = 0; c < r.message.content.length; c++) {
        var blk = r.message.content[c]
        if (blk && blk.type === "tool_result") {
          var body = ""
          if (typeof blk.content === "string") body = blk.content
          else if (Array.isArray(blk.content)) {
            body = blk.content.map(function (x) { return x && x.type === "text" ? x.text : "" }).join("\n")
          }
          var trunc = truncateBody(body, 60)
          toolResults[blk.tool_use_id] = {
            output: trunc.text,
            truncatedLines: trunc.truncated,
            isError: blk.is_error === true
          }
        }
      }
    }
  }

  // pass 2 — ordered steps
  var raw = []
  for (var q = 0; q < records.length; q++) {
    var rec = records[q]
    if (!rec || typeof rec !== "object") continue
    var ts = isoToMs(rec.timestamp)

    if (rec.type === "user" && rec.message && !rec.isMeta) {
      var content = rec.message.content
      var promptText = ""
      if (typeof content === "string") promptText = content
      else if (Array.isArray(content)) {
        var hasToolResult = content.some(function (b) { return b && b.type === "tool_result" })
        if (hasToolResult) continue // handled via pass 1
        promptText = content.map(function (b) { return b && b.type === "text" ? b.text : "" }).join("\n")
      }
      promptText = cleanPromptText(promptText)
      var trimmed = promptText ? promptText.trim() : ""
      // Drop session-management commands (/clear, /compact, …) — they aren't
      // part of how anything got built.
      if (trimmed && !(/^\/?(clear|compact|resume|cost|help|init|context|export)\b/i.test(trimmed) && trimmed.length < 24)) {
        raw.push({ kind: "prompt", ts: ts, text: red(trimmed) })
      }
      continue
    }

    if (rec.type === "assistant" && rec.message && Array.isArray(rec.message.content)) {
      for (var b2 = 0; b2 < rec.message.content.length; b2++) {
        var block = rec.message.content[b2]
        if (!block || typeof block !== "object") continue
        if (block.type === "thinking") {
          if (!opt.includeThinking) continue
          if (block.thinking && block.thinking.trim())
            raw.push({ kind: "thinking", ts: ts, text: red(block.thinking.trim()) })
        } else if (block.type === "text") {
          if (block.text && block.text.trim())
            raw.push({ kind: "narration", ts: ts, text: red(block.text.trim()) })
        } else if (block.type === "tool_use") {
          if (block.name === "Read" && !opt.includeReads) continue
          var step = toolStepFrom(block)
          step.ts = ts
          step.body = red(step.body)
          step.title = red(step.title)
          var res = toolResults[block.id]
          if (res) {
            step.result = {
              output: red(res.output),
              truncatedLines: res.truncatedLines,
              isError: res.isError
            }
          }
          raw.push(step)
        }
      }
      continue
    }
  }

  // timing: real offset `t`, compressed `playT`, per-step `dwell`
  var startTs = null
  var endTs = null
  for (var s0 = 0; s0 < raw.length; s0++) {
    if (raw[s0].ts != null) {
      if (startTs == null) startTs = raw[s0].ts
      endTs = raw[s0].ts
    }
  }
  if (startTs == null) startTs = 0

  var playCursor = 0
  var prevTs = startTs
  for (var s = 0; s < raw.length; s++) {
    var st = raw[s]
    var realOffset = st.ts != null ? st.ts - startTs : (s > 0 ? raw[s - 1].t : 0)
    var gap = st.ts != null ? Math.max(0, st.ts - prevTs) : 1200
    var playGap = Math.min(gap, opt.maxGapMs)
    if (s === 0) playGap = 0
    playCursor += playGap
    st.t = realOffset
    st.playT = playCursor
    if (st.ts != null) prevTs = st.ts

    // dwell: how long this step stays on screen during playback — enough to
    // "read" its text, floored/capped to keep pace lively.
    var chars = (st.text || "").length + (st.body || "").length * 0.5
    st.dwell = Math.max(1200, Math.min(9000, Math.round((chars / opt.typewriterCps) * 1000)))
  }
  // ensure playT is monotonic & leaves room for each dwell
  for (var s2 = 1; s2 < raw.length; s2++) {
    var minStart = raw[s2 - 1].playT + Math.min(raw[s2 - 1].dwell, opt.maxGapMs)
    if (raw[s2].playT < minStart) raw[s2].playT = minStart
  }

  meta.startedAt = startTs || null
  meta.endedAt = endTs || null

  // No ai-title line in the transcript → name the cast after its first prompt.
  if (!meta.title) {
    var firstPrompt = raw.find(function (s) { return s.kind === "prompt" && s.text })
    if (firstPrompt) {
      meta.title = firstPrompt.text.split("\n")[0].replace(/^\/\S+\s*/, "").slice(0, 64).trim()
    }
    if (!meta.title) meta.title = "session"
  }

  // stats
  var counts = { prompt: 0, narration: 0, thinking: 0, tool: 0 }
  var tools = {}
  var files = {}
  var linesAdded = 0
  var linesRemoved = 0
  for (var s3 = 0; s3 < raw.length; s3++) {
    var x = raw[s3]
    counts[x.kind] = (counts[x.kind] || 0) + 1
    if (x.kind === "tool") {
      tools[x.tool] = (tools[x.tool] || 0) + 1
      linesAdded += x.linesAdded || 0
      linesRemoved += x.linesRemoved || 0
      ;(x.files || []).forEach(function (f) { if (f) files[f] = true })
    }
  }

  var stats = {
    durationMs: endTs && startTs ? endTs - startTs : 0,
    playDurationMs: raw.length ? raw[raw.length - 1].playT + opt.tailPadMs : 0,
    counts: counts,
    tools: tools,
    files: Object.keys(files),
    linesAdded: linesAdded,
    linesRemoved: linesRemoved,
    redactions: redactions,
    steps: raw.length
  }

  // warnings — the quality signal the self-improvement loop (improve.json /
  // omarchy-plugin-improve) turns into "insight" entries.
  var unknownTools = {}
  var unpairedTools = 0
  var heavyTruncations = 0
  for (var w = 0; w < raw.length; w++) {
    var y = raw[w]
    if (y.kind !== "tool") continue
    if (y.generic) unknownTools[y.tool] = (unknownTools[y.tool] || 0) + 1
    if (!y.result) unpairedTools++
    var m1 = /\+(\d+) (?:more )?lines/.exec(y.note || "")
    if (m1 && Number(m1[1]) > 120) heavyTruncations++
    if (y.result && Number(y.result.truncatedLines) > 120) heavyTruncations++
  }
  var warnings = {
    unknownTools: Object.keys(unknownTools),
    unpairedTools: unpairedTools,
    heavyTruncations: heavyTruncations,
    redactionRate: raw.length ? Math.round((redactions / raw.length) * 100) / 100 : 0,
    noSteps: raw.length === 0
  }

  return { meta: meta, steps: raw, stats: stats, warnings: warnings }
}

// Human duration: 1h 04m / 3m 20s / 45s
function formatDuration(ms) {
  var s = Math.round((Number(ms) || 0) / 1000)
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  if (h > 0) return h + "h " + String(m).padStart(2, "0") + "m"
  if (m > 0) return m + "m " + String(sec).padStart(2, "0") + "s"
  return sec + "s"
}

// Tolerant parse for devcast-index.json (written by ~/.local/bin/omarchy-devcast,
// watched by the bar widget). A malformed / missing file degrades to empty.
function parseIndex(raw) {
  var empty = { version: 1, updatedAt: 0, count: 0, latest: null, casts: [], catalog: null }
  if (!raw || raw.length === 0) return empty
  try {
    var o = typeof raw === "string" ? JSON.parse(raw) : raw
    if (!o || typeof o !== "object") return empty
    var cat = null
    if (o.catalog && typeof o.catalog === "object") {
      cat = {
        totalSessions: Number(o.catalog.totalSessions) || 0,
        built: Number(o.catalog.built) || 0,
        stale: Number(o.catalog.stale) || 0,
        unbuilt: Number(o.catalog.unbuilt) || 0,
        updatedAt: Number(o.catalog.updatedAt) || 0,
        recent: Array.isArray(o.catalog.recent) ? o.catalog.recent : []
      }
    }
    return {
      version: 1,
      updatedAt: Number(o.updatedAt) || 0,
      count: Number(o.count) || (Array.isArray(o.casts) ? o.casts.length : 0),
      latest: o.latest || (Array.isArray(o.casts) ? o.casts[0] || null : null),
      casts: Array.isArray(o.casts) ? o.casts : [],
      catalog: cat
    }
  } catch (e) {
    return empty
  }
}

function summaryLine(cast) {
  if (!cast || !cast.stats) return "no data"
  var st = cast.stats
  var parts = [
    st.steps + " steps",
    formatDuration(st.durationMs),
    (st.counts.tool || 0) + " tool calls"
  ]
  if (st.files.length) parts.push(st.files.length + " files")
  if (st.linesAdded || st.linesRemoved) parts.push("+" + st.linesAdded + "/-" + st.linesRemoved)
  if (st.redactions) parts.push(st.redactions + " redacted")
  return parts.join(" · ")
}

if (typeof module !== "undefined") {
  module.exports = {
    parseTranscript: parseTranscript,
    parseIndex: parseIndex,
    redactString: redactString,
    cleanPromptText: cleanPromptText,
    editDiff: editDiff,
    toolStepFrom: toolStepFrom,
    langForPath: langForPath,
    formatDuration: formatDuration,
    summaryLine: summaryLine,
    defaultOptions: defaultOptions
  }
}
