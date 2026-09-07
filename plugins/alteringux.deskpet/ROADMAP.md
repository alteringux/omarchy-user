# Deskpet roadmap

One small, tested increment per auto-improve run. Check items off as they land; keep a couple of candidates queued at the bottom.

## Done

- [x] **12th pet: the Hamster** (Model.js) — new voice, greet/poke/feed/play/sleepy/wake/low-battery/long-idle/milestone lines; pet count test updated 11 → 12.
- [x] **A pet ages up a notch** (Model.js) — pure `ageUp(state)` at the 50-pat mark (shares the `pat_pat_pat` line): marks `agedUp`, equips the top hat 🎩 (idempotent, never re-equips over a user-picked accessory), and fires one special line via the Pet.qml aged-up transition; `agedUp` persists with the rest of the stats. Tests: no-op below threshold, crossing equips the hat, idempotent, no input mutation, the 50th poke fires it exactly once, and the line rides the pet's own voice.
- [x] **Time-of-day chatter** (Model.js) — pure `timePeriod(hour)` buckets 0-23 into morning/afternoon/evening/lateNight (null out of range), and `pickTimeLine(hour, seed)` picks from shared banks in the `CLIPPY_TIPS`/`ZOOM_LINES` style: one pool the caller wraps in `pet.voice()`, so all 12 pets share it. Wired into `pickAmbientLine` below battery/idle/mood: ~1 in 3 ambient seeds (`seed % 1000 < 300`) with a valid `hourValue` (new `hourValue` in the ambient context from BarWidget → Pet) takes the time branch, else it falls through to the generic tip. Tests: bucket boundaries, out-of-range/missing → null, seeded in-bank picks, the 1-in-3 seed gate, the missing-hour fallthrough, and battery/idle/mood still outranking it.

## Queued
- [ ] **A "hush" toggle** — the panel's bell (🔔/🔕) already mutes; add the same as a right-click bar-widget action so the pet can be quieted without opening the panel.
- [ ] **A mood ring on the bar icon** — the bar widget's glyph shifts with the pet's computed mood (happy/meh/sad from `Model.mood()`), so the pet's state is readable without opening the panel.
- [ ] **A second age-up** — a deeper milestone at 500 pats: a different accessory and one special line, reusing the `ageUp` path and `agedUp` persistence (add `agedUp2` or extend the existing flag).