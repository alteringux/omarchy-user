# alteringux.devcast — notes

## What it is

`omarchy-devcast` turns a Claude Code session transcript
(`~/.claude/projects/<slug>/<session-id>.jsonl`) into an **interactive replay**:

- `cast.json` — the parsed step list (prompts, narration, tool calls with
  diffs / commands / output, timestamps).
- `replay.html` — a self-contained player: timeline scrubber, play/pause,
  speed, per-step syntax-highlighted diffs and terminal output, keyboard nav
  (space / ← → / ↑ ↓ / S / F / Home / End). Offline, theme-aware.
- optional `devcast-*.mp4` / `devcast-*.gif` via `omarchy-devcast export`.

All output lives under `~/.local/state/omarchy/devcasts/<stamp>-<slug>/`.
`~/.local/state/omarchy/devcast-index.json` is the single file the bar widget
watches (rebuilt on every `build` / `prune`; `omarchy-devcast reindex` forces it).

## How the parse works (Model.js)

- One JSON object per transcript line. `assistant` lines carry `thinking` /
  `text` / `tool_use` blocks; `user` lines carry the prompt string or
  `tool_result` blocks (paired back to their `tool_use` by id).
- `thinking` blocks are **omitted by default** (`--thinking` to include).
- Idle gaps between steps are clamped (`--max-gap`, default 6 s) for playback
  pacing, but each step keeps its real `T+` offset for display.
- **Redaction** (on by default): masks `sk-…`, `ghp_…`, `github_pat_…`,
  Slack/AWS keys, JWTs, `Authorization:`/`api_key=` values, `*_SECRET=` /
  `*_TOKEN=` env assignments, and long hex/base64 blobs. Count shown in the
  player header. `--no-redact` disables it.

## Export

`omarchy-devcast export <id> [--mp4|--gif] [--fps N] [--width W] [--height H]
[--theme dark|light] [--max-frames N]`

Fast path: one headless chromium driven over the DevTools protocol (Node's
built-in `WebSocket`, no npm) — navigate once, `window.__devcastSeek(ms)` +
`Page.captureScreenshot` per frame. Falls back to one chromium invocation per
frame if that fails. ffmpeg normalises to a ~45 s clip. Needs `chromium`
(present) and `ffmpeg` (present).

## Optional: auto-build on every session (Stop hook)

Not wired — this is the propose step (per the global "self-improving
automation → propose, don't auto-apply" rule). To have every Claude Code
session drop a devcast automatically, add this to `~/.claude/settings.json`:

```jsonc
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "nohup omarchy-devcast build \"$CLAUDE_SESSION_ID\" --project \"$CLAUDE_PROJECT_DIR\" >/dev/null 2>&1 &"
          }
        ]
      }
    ]
  }
}
```

Notes:
- Backgrounded (`nohup … &`) so it never delays the session ending.
- `$CLAUDE_SESSION_ID` / `$CLAUDE_PROJECT_DIR` are provided by Claude Code to
  hook commands. If a build on a still-open session misses the last few lines,
  re-run `omarchy-devcast build <id>` afterwards — it overwrites cleanly.
- To also auto-export a video, append
  `&& omarchy-devcast export "$(omarchy-devcast list --json | jq -r '.[0].id')" --mp4`
  to the command (slower; consider `SessionEnd` framing instead).
- Remove the hook block to stop.

## Self-improvement loop

This plugin opts in (`improve.json` + `roadmap.md`). `build` emits
`unknown-tool` / `unpaired-tool` / `heavy-truncation` / `high-redaction`
insights from `cast.warnings`, and `omarchy-devcast flag <id> "<what was
wrong>"` records a human one. A gated, OFF-by-default critic turns the
accumulated insights into reviewable diff proposals. See
`../../docs/self-improvement-loop.md`.

## Slash command

`~/.claude/commands/devcast.md` → `/devcast [session-id]` asks Claude to run
`omarchy-devcast build … --open` (and `export` if you ask for a video).
