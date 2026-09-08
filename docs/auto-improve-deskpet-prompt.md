# Deskpet auto-improve — run instructions

You are running unattended, hourly, with nobody reviewing your diff before it
lands and gets restarted into the live desktop shell. Your job is to grow
`plugins/alteringux.deskpet/` — the floating desktop pet — one small,
working increment at a time, forever. Think "this thing keeps getting more
fully-fledged" rather than "clean this up."

## Scope

- Modify files only under `plugins/alteringux.deskpet/`.
- Never modify: other plugins, `plugins/alteringux.kit`, `shell.json`,
  `shell.toml`, hooks, flows, themes, `~/.local/bin`, or anything outside
  this directory. You may *read* other plugins' source for inspiration or
  `plugins/alteringux.kit/README.md` for components to reuse, but never
  write to them.
- Never run git write commands (`git add`, `git commit`, `git stash`,
  `git reset`, ...). The scheduler commits your changes after smoke-testing.
- Never edit this file or the changelog.

## Continuity: keep a roadmap

Maintain `plugins/alteringux.deskpet/ROADMAP.md`. Before doing anything else,
read it (create it if missing, seeded with a few ideas of your own). Each run:

1. Pick the next unimplemented idea (or invent one if the list is thin).
2. Implement it.
3. Update ROADMAP.md: check it off with a one-line note on what actually
   shipped, and add 1-3 new ideas if the list is running low.

This file is what lets each hourly run build on the last instead of
reinventing or duplicating past work — read it carefully, don't re-do
something already checked off.

## What counts as growth (pick ONE per run, use your judgment beyond this list)

- New ambient chatter: more hotkey tips (grep `~/.config/hypr/bindings.lua`
  for real ones — never invent a keybinding that doesn't exist), fun facts,
  jokes, or a whole new chatter *category* (e.g. weather-aware lines using
  data already on this machine, time-of-day-specific lines, a lines bank
  tied to a new mood).
- New pet behaviors/animations in `Pet.qml`: reactions to new triggers,
  new particle effects, a new roam gait, a new idle animation.
- New mechanics in `Model.js` (pure, `node --test`-able): new achievements,
  new accessories, a new stat, a mini-game, a new mood state, seasonal
  events (date-based), a streak/combo system beyond poke streaks.
- New settings/panel affordances in `Panel.qml` to control whatever you add.
- Never remove an existing pet, achievement, or accessory — only add.

## Guardrails

1. Read `Model.js`, `Pet.qml`, `Panel.qml`, `BarWidget.qml`, `manifest.json`,
   `test/model.test.js`, and `ROADMAP.md` first.
2. Follow the existing architecture: pure logic in `Model.js` (no QML
   imports there), QML files only wire it up and animate. Every new pure
   function needs a `node --test` in `test/model.test.js`.
3. Adopt `plugins/alteringux.kit` components over hand-rolled plumbing where
   they fit (Store, BugGuard, Palette, PanelHead, Toggle, etc.).
4. Keep changes additive and small enough to verify in one sitting — one
   feature per run, not a rewrite.
5. Run `node --test plugins/alteringux.deskpet/test/model.test.js` and make
   sure it's green before you finish. Never weaken or delete a test to make
   it pass. Add new tests for new logic.
6. Do not add comments beyond the codebase's existing sparse style.
7. Do not add new dependencies or new `~/.local/bin` helpers.

## Output protocol (required)

Write exactly one line (max 120 characters, changelog style, no leading
dash) to `~/.local/state/omarchy-deskpet-auto-improve/summary`:

- If you changed something: a terse description of what you added.
- If you deliberately made no changes (rare — the whole point is growth):
  exactly `no changes`.

Then stop. Do not start any other work.
