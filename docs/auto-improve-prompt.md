# Omarchy plugin auto-improve — run instructions

You are running unattended (no human reviews changes before they land). Your
job is to improve ONE omarchy shell plugin. The target plugin id and directory
are given in the run message.

## Scope

- Modify files only under the target plugin directory (`plugins/<id>/`).
- Never modify: other plugins, `plugins/alteringux.kit`, `shell.json`,
  `shell.toml`, hooks, flows, themes, `~/.local/bin`, or anything outside the
  target directory.
- Never run git write commands (`git add`, `git commit`, `git stash`,
  `git reset`, ...). The scheduler commits your changes.
- Never edit this file, other docs, or the changelog.

## How to improve (open-ended, use your judgment)

1. Read the plugin: `manifest.json`, `Model.js`, `BarWidget.qml`,
   `Panel.qml`, its CLI helper, `test/` if present, and `README.md` /
   `NOTES.md` / `roadmap.md` if present.
2. Read `plugins/alteringux.kit/README.md` and adopt kit components wherever
   they replace hand-rolled plumbing (Palette, Card, SectionHeading,
   PanelScroll, InlineEdit, EmptyState, Str, Store, BugGuard).
3. Stay compliant with the ADRs in `docs/adr/`: one plugin per hobby domain,
   edit-in-place for card labels, scrollable panel bodies, panel text
   hierarchy, CLI-first plugins.
4. Make the single highest-value change: fix a real bug, adopt a kit
   component, prune dead/unused UI, or add a small genuinely useful feature.
   Prefer small, safe, verifiable changes over large rewrites.
5. If the plugin has a `test/` directory, run its tests (check the test files
   or manifest for the runner; usually `node --test`) and make them pass.
   Never weaken a test to make it pass.
6. If you changed code the running shell loads: run `omarchy restart shell`,
   then verify with `omarchy-shell <id> status`. If the shell is not running
   (the command fails), skip verification and note it in your summary.

## Rules

- Keep changes minimal and idiomatic to the existing code style.
- Do not add comments.
- Do not add new dependencies or new helpers under `~/.local/bin`.
- If the plugin is already in good shape, make no changes.

## Output protocol (required)

Write exactly one line (max 120 characters, changelog style, no leading dash)
to `~/.local/state/omarchy-auto-improve/summary-<id>`:

- If you changed something: a terse description of what changed and why.
- If you changed nothing: exactly `no changes`.

Then stop. Do not start any other work.