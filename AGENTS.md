# Omarchy plugin rules

- Never use emoji as UI icons in any plugin. This includes bar and panel glyphs, section/category markers, status badges, and action controls. Use the installed JetBrainsMono Nerd Font glyphs already used by Omarchy instead.
- Emoji used as actual content or artwork may remain, such as deskpet characters and accessories, animated effects, and user-facing copy. Do not use these as substitutes for interface icons.
- Vertical taskbar rails host only fixed icon buttons that open a panel. Keep labels, counters, timers, scores, and other changing information on horizontal bars. Check every active state of a widget before moving it.

## Agent skills

### Issue tracker

Issues and specs for this repository live in GitHub Issues at `alteringux/omarchy-user`; use the GitHub CLI workflow. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the canonical labels `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository with a root glossary and shared ADR directory. See `docs/agents/domain.md`.

### Visual verification

UI and layout verification is incomplete without screenshot QA. Capture the
running surface into `.lavish/qa/`, open every verification screenshot with the
image viewer, and read it for overlaps, clipping, missing widgets, and popup
placement before reporting the change as verified. Keep the before/after
screenshots when a layout bug is being fixed.
