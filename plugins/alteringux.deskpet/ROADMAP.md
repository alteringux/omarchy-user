# Deskpet roadmap

One small, tested increment per auto-improve run. Check items off as they land; keep a couple of candidates queued at the bottom.

## Done

- [x] **12th pet: the Hamster** (Model.js) — new voice, greet/poke/feed/play/sleepy/wake/low-battery/long-idle/milestone lines; pet count test updated 11 → 12.
- [x] **A pet ages up a notch** (Model.js) — pure `ageUp(state)` at the 50-pat mark (shares the `pat_pat_pat` line): marks `agedUp`, equips the top hat 🎩 (idempotent, never re-equips over a user-picked accessory), and fires one special line via the Pet.qml aged-up transition; `agedUp` persists with the rest of the stats. Tests: no-op below threshold, crossing equips the hat, idempotent, no input mutation, the 50th poke fires it exactly once, and the line rides the pet's own voice.

## Queued

- [ ] **Time-of-day chatter** — a pure `pickTimeLine(hour, seed)` with morning/afternoon/evening/late-night banks, wired into the ambient speech context alongside battery and idle.
- [ ] **A "hush" toggle** — the panel's bell (🔔/🔕) already mutes; add the same as a right-click bar-widget action so the pet can be quieted without opening the panel.
- [ ] **A mood ring on the bar icon** — the bar widget's glyph shifts with the pet's computed mood (happy/meh/sad from `Model.mood()`), so the pet's state is readable without opening the panel.
- [ ] **A second age-up** — a deeper milestone at 500 pats: a different accessory and one special line, reusing the `ageUp` path and `agedUp` persistence (add `agedUp2` or extend the existing flag).