"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

// Build a JSONL transcript string from an array of record objects.
function jsonl(records) {
  return records.map((r) => JSON.stringify(r)).join("\n") + "\n"
}

const T0 = "2026-09-04T10:00:00.000Z"
const t = (sec) => new Date(Date.parse(T0) + sec * 1000).toISOString()

test("parses a prompt → narration → tool sequence in order with paired results", () => {
  const tx = jsonl([
    { type: "ai-title", aiTitle: "⑂ Build a widget" },
    { type: "user", timestamp: t(0), message: { role: "user", content: "make me a network widget" } },
    {
      type: "assistant",
      timestamp: t(2),
      message: { role: "assistant", content: [{ type: "text", text: "On it — creating the file." }] }
    },
    {
      type: "assistant",
      timestamp: t(3),
      message: {
        role: "assistant",
        content: [{ type: "tool_use", id: "tu1", name: "Write", input: { file_path: "/home/x/app.js", content: "const a = 1\nconst b = 2\n" } }]
      }
    },
    {
      type: "user",
      timestamp: t(4),
      message: { role: "user", content: [{ type: "tool_result", tool_use_id: "tu1", is_error: false, content: "File created" }] }
    }
  ])

  const cast = Model.parseTranscript(tx)
  assert.equal(cast.meta.title, "Build a widget")
  assert.deepEqual(cast.steps.map((s) => s.kind), ["prompt", "narration", "tool"])
  assert.equal(cast.steps[0].text, "make me a network widget")
  assert.equal(cast.steps[2].tool, "Write")
  assert.equal(cast.steps[2].lang, "javascript")
  assert.equal(cast.steps[2].result.output, "File created")
  assert.equal(cast.steps[2].result.isError, false)
  assert.equal(cast.stats.counts.tool, 1)
  assert.equal(cast.stats.linesAdded, 2)
  assert.deepEqual(cast.stats.files, ["app.js"])
})

test("Bash tool step keeps the command and marks an error result", () => {
  const tx = jsonl([
    {
      type: "assistant",
      timestamp: t(1),
      message: { role: "assistant", content: [{ type: "tool_use", id: "b1", name: "Bash", input: { command: "ss -tunp | head", description: "list sockets" } }] }
    },
    {
      type: "user",
      timestamp: t(2),
      message: { role: "user", content: [{ type: "tool_result", tool_use_id: "b1", is_error: true, content: "Exit code 1\nboom" }] }
    }
  ])
  const cast = Model.parseTranscript(tx)
  const s = cast.steps[0]
  assert.equal(s.tool, "Bash")
  assert.equal(s.lang, "bash")
  assert.equal(s.body, "ss -tunp | head")
  assert.equal(s.title, "list sockets")
  assert.equal(s.result.isError, true)
})

test("Edit step renders a -/+ diff and counts lines both ways", () => {
  const tx = jsonl([
    {
      type: "assistant",
      timestamp: t(1),
      message: {
        role: "assistant",
        content: [{ type: "tool_use", id: "e1", name: "Edit", input: { file_path: "/p/Model.js", old_string: "a\nb", new_string: "a\nB\nc", replace_all: false } }]
      }
    }
  ])
  const cast = Model.parseTranscript(tx)
  const s = cast.steps[0]
  assert.equal(s.lang, "diff")
  assert.equal(s.body, "- a\n- b\n+ a\n+ B\n+ c")
  assert.equal(s.linesRemoved, 2)
  assert.equal(s.linesAdded, 3)
})

test("thinking blocks are excluded by default and included with the option", () => {
  const tx = jsonl([
    { type: "assistant", timestamp: t(1), message: { role: "assistant", content: [{ type: "thinking", thinking: "secret reasoning" }] } },
    { type: "assistant", timestamp: t(2), message: { role: "assistant", content: [{ type: "text", text: "done" }] } }
  ])
  assert.equal(Model.parseTranscript(tx).steps.length, 1)
  const withThinking = Model.parseTranscript(tx, { includeThinking: true })
  assert.equal(withThinking.steps.length, 2)
  assert.equal(withThinking.steps[0].kind, "thinking")
})

test("isMeta user lines and tool_result-only user lines are not prompts", () => {
  const tx = jsonl([
    { type: "user", timestamp: t(0), isMeta: true, message: { role: "user", content: "<system-reminder>ignore me</system-reminder>" } },
    { type: "user", timestamp: t(1), message: { role: "user", content: [{ type: "tool_result", tool_use_id: "z", content: "x" }] } },
    { type: "user", timestamp: t(2), message: { role: "user", content: "real question" } }
  ])
  const cast = Model.parseTranscript(tx)
  assert.equal(cast.steps.length, 1)
  assert.equal(cast.steps[0].text, "real question")
})

test("slash-command prompts are reduced to /name + args", () => {
  const raw = "<command-message>omarchy</command-message>\n<command-name>/omarchy</command-name>\n<command-args>make a plugin</command-args>\nBase directory for this skill: /x\n# huge skill body ..."
  assert.equal(Model.cleanPromptText(raw), "/omarchy make a plugin")
})

test("redaction masks common secret shapes and counts them", () => {
  const tx = jsonl([
    {
      type: "assistant",
      timestamp: t(1),
      message: {
        role: "assistant",
        content: [{ type: "tool_use", id: "b1", name: "Bash", input: { command: "export API_KEY=sk-ant-abcdefghij1234567890 && curl -H 'Authorization: Bearer ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345'" } }]
      }
    }
  ])
  const cast = Model.parseTranscript(tx)
  assert.ok(!/sk-ant-abcdefghij/.test(cast.steps[0].body))
  assert.ok(!/ghp_ABCDEFGHIJ/.test(cast.steps[0].body))
  assert.ok(cast.stats.redactions >= 2)
})

test("--no-redact leaves secrets verbatim", () => {
  const tx = jsonl([
    { type: "assistant", timestamp: t(1), message: { role: "assistant", content: [{ type: "tool_use", id: "b1", name: "Bash", input: { command: "echo sk-ant-abcdefghij1234567890" } }] } }
  ])
  const cast = Model.parseTranscript(tx, { redact: false })
  assert.ok(/sk-ant-abcdefghij1234567890/.test(cast.steps[0].body))
  assert.equal(cast.stats.redactions, 0)
})

test("timing: real offsets kept, idle gaps compressed for playback, playT monotonic", () => {
  const tx = jsonl([
    { type: "user", timestamp: t(0), message: { role: "user", content: "go" } },
    { type: "assistant", timestamp: t(5), message: { role: "assistant", content: [{ type: "text", text: "step one" }] } },
    // 10-minute idle gap before the next step
    { type: "assistant", timestamp: t(605), message: { role: "assistant", content: [{ type: "text", text: "step two" }] } }
  ])
  const cast = Model.parseTranscript(tx, { maxGapMs: 6000 })
  assert.equal(cast.steps[2].t, 605000) // real offset preserved
  assert.ok(cast.steps[2].playT < 60000) // but playback gap was clamped
  assert.ok(cast.steps[1].playT < cast.steps[2].playT)
  assert.ok(cast.stats.playDurationMs >= cast.steps[2].playT)
})

test("empty / garbage transcript yields zero steps without throwing", () => {
  assert.equal(Model.parseTranscript("").steps.length, 0)
  assert.equal(Model.parseTranscript("not json\n{bad").steps.length, 0)
})

test("warnings flag an unknown tool, an unpaired call, and heavy truncation", () => {
  const bigContent = Array.from({ length: 500 }, (_, i) => "line " + i).join("\n")
  const tx = jsonl([
    { type: "assistant", timestamp: t(1), message: { role: "assistant", content: [{ type: "tool_use", id: "u1", name: "SomeNewTool", input: { foo: "bar" } }] } },
    { type: "assistant", timestamp: t(2), message: { role: "assistant", content: [{ type: "tool_use", id: "u2", name: "Bash", input: { command: "echo hi" } }] } },
    { type: "assistant", timestamp: t(3), message: { role: "assistant", content: [{ type: "tool_use", id: "u3", name: "Write", input: { file_path: "/a/big.txt", content: bigContent } }] } }
    // no tool_result for any of them
  ])
  const cast = Model.parseTranscript(tx)
  assert.deepEqual(cast.warnings.unknownTools, ["SomeNewTool"])
  assert.equal(cast.warnings.unpairedTools, 3)
  assert.ok(cast.warnings.heavyTruncations >= 1)
  assert.equal(cast.warnings.noSteps, false)
})

test("summaryLine and formatDuration", () => {
  assert.equal(Model.formatDuration(45000), "45s")
  assert.equal(Model.formatDuration(200000), "3m 20s")
  assert.equal(Model.formatDuration(3900000), "1h 05m")
  const cast = Model.parseTranscript(
    jsonl([
      { type: "user", timestamp: t(0), message: { role: "user", content: "go" } },
      { type: "assistant", timestamp: t(30), message: { role: "assistant", content: [{ type: "tool_use", id: "w", name: "Write", input: { file_path: "/a/b.js", content: "x\n" } }] } }
    ])
  )
  assert.match(Model.summaryLine(cast), /steps · .* · 1 tool calls · 1 files/)
})
