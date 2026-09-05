# Deskpet roadmap

One small, tested increment per auto-improve run. Check items off as they land; keep a couple of candidates queued at the bottom.

## Done

- [x] **12th pet: the Hamster** (Model.js) — new voice, greet/poke/feed/play/sleepy/wake/low-battery/long-idle/milestone lines; pet count test updated 11 → 12.

## Queued

- [ ] **A pet ages up a notch** — a pure `ageUp(stats)` milestone at 50 pats: the pet gains a tiny accessory (top hat 🎩) and one special line; persisted with the rest of the stats.
- [ ] **Time-of-day chatter** — a pure `pickTimeLine(hour, seed)` with morning/afternoon/evening/late-night banks, wired into the ambient speech context alongside battery and idle.
- [ ] **A "hush" toggle** — the panel's bell (🔔/🔕) already mutes; add the same as a right-click bar-widget action so the pet can be quieted without opening the panel.