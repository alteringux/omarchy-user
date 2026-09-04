# devcast roadmap

Candidate accuracy / analytics improvements. The critic
(`omarchy-plugin-improve critic devcast`) may propose diffs against these,
ranked by what the insight digest shows, and may append new candidates.

## Accuracy

- **Real diffs.** `editStepFrom` prints the whole old block as `-` and the
  whole new block as `+`. Use the `file-history-snapshot` lines in the
  transcript (or shell out to `diff`) to emit true line-level hunks and
  correct `linesAdded` / `linesRemoved`.
- **Renderers for unhandled tools.** Any `tool_use` name that falls through to
  the generic JSON branch loses readability — add a case (emitted as the
  `unknown-tool` insight with the offending names).
- **Tool-result pairing.** A `tool_use` with no matching `tool_result`
  (`unpaired-tool` insight) shows an empty output panel; detect and label it
  "no result captured" rather than blank.
- **Truncation limits.** `Write` bodies truncate at 320 lines, results at 60;
  `heavy-truncation` insights say when that hid a lot. Make the caps adaptive
  to step count, or add a "show full" link that loads a sidecar file.

## Analytics

- **Chapters.** Auto-segment the cast at skill invocations, `AskUserQuestion`
  rounds, `node --test` / pytest runs, and git commits; render as labelled
  regions on the scrubber.
- **Test timeline.** Parse test-runner output in tool results → a red/green
  strip and pass/fail counts per chapter.
- **Cost / tokens.** Read the `cost-state` / `modelUsage` transcript lines →
  `stats.tokens`, `stats.costUSD`, and a per-phase overlay.
- **Error-recovery arcs.** Detect `is_error` result → retry of the same
  tool/file; report error rate and mean steps-to-recover.
- **Thinking captions.** Instead of raw thinking (off) or nothing, run each
  thinking block through `llm-blurb` to a one-line "why" caption.
- **Phase timing.** Use request/API-duration metadata to split each step into
  generating vs tool-running vs user-idle.

## Signals the plugin already emits

- `unknown-tool` — a tool with no dedicated renderer
- `unpaired-tool` — tool_use with no tool_result
- `heavy-truncation` — a step lost > 120 lines to truncation
- `high-redaction` — many secrets masked (redaction pattern may be too broad)
- `no-steps` — a transcript produced zero replay steps
- `flag` — a human `omarchy-devcast flag <id> "..."`
