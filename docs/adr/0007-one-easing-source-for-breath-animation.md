# One easing source for the breath animation, and an overlay that owns the screen

## Status

Accepted 2026-09-10.

## Context

`alteringux.breathe` guides a breathing exercise, and it draws the same breath
in two places at once: a fullscreen layer-shell overlay (`Guide.qml`) and a
compact guide inside the popup (`Panel.qml`). Both show one number — how big
the orb is right now.

The obvious implementation gives each surface its own animation: a
`NumberAnimation` per phase, or a `Behavior` on the orb's width driven by the
phase countdown. That was rejected for two reasons.

**Two animations drift.** They start from different frames, use independently
tuned durations, and after a few cycles the panel and the overlay visibly
disagree about where in the breath you are. There is no seam to fix, because
nothing is wrong with either one individually.

**A per-kind easing rule tears at phase boundaries.** A rule as simple as
"INHALE rises to full, EXHALE falls to empty" breaks on two of the eleven
built-in techniques:

- The **physiological sigh** inhales, then sips *more* on top. If the first
  inhale already reached the peak, the sip has nowhere to rise from and has to
  jump backwards to make room.
- **Wim Hof** ends a round holding a full breath and begins the next one empty,
  so the orb must actually be walked back down between rounds or it snaps.

Both are invisible in any single-phase test. They only appear at the seam
between phases, and at the wrap from the last phase of a cycle to the first.

## Decision

**`Model.js` owns the orb scale, and it is the only easing source.**

`Model.resolve(session, technique, nowMs)` returns `orbScale` alongside the
phase and countdown, and both guides read that one value. Neither re-derives
easing locally. A technique's full envelope is computed once by
`Model.scaleEnvelope(technique)`, which gives every phase an explicit `from`
and `to` where `from` is simply the previous phase's `to` — wrapping, so the
last phase hands off to the first.

Continuity is then **true by construction** rather than by careful per-kind
arithmetic. `phaseTargetScale` handles the two awkward cases directly: an
INHALE followed by an INHALE_TOP stops short to leave the sip headroom, and
holds and switches park wherever they arrived. `test/model.test.js` asserts the
seam across every adjacent phase pair of every built-in technique, including
the cycle wrap.

A technique may also declare an `amplitude` below 1. Buteyko's entire premise
is breathing *less* than feels natural, so rendering it at the same sweep as a
Wim Hof power breath would teach the wrong thing.

## The overlay owns the screen, and offers only reversible keys

Unlike `alteringux.deskpet`, the breath guide deliberately does **not** clamp
its input mask to a hit box. While you are breathing it covers the screen, so a
stray click should land on pause rather than on whatever was underneath.

The consequence is that it takes compositor keyboard focus, and a stray
keystroke lands on it. An early version bound bare `S` to *finish the session*;
during the first live test a single keypress ended a running session and
credited a partial one. **Every key the overlay binds must therefore be
reversible**: Space pauses, Escape hides the overlay without touching the
session. Ending a session early is a decision and lives on a panel button.

## Consequences

- **Good:** the two guides cannot drift, because there is one number. Adding a
  technique — including a user-authored one from the pattern builder — needs no
  animation code at all; the envelope falls out of its phase list.
- **Good:** the easing is pure JS, so the seam behaviour is Node-testable
  without a running compositor.
- **Cost:** the orb's width is recomputed every frame from `resolve` rather than
  animated by Qt, so `BarWidget.qml` runs a 16ms tick while the overlay is up
  (250ms when only the bar countdown is watching). Putting a `Behavior` on the
  orb width would fight that and lag the breath behind its own countdown, so
  the orb deliberately has none.
- **Cost:** `reduceMotion` has to be handled per surface, since there is no
  single animation object to switch off.

## Related

`0006-cli-first-plugins.md` — `~/.local/bin/omarchy-breathe` is the sole writer
of session/stats/history and owns every phase *transition*; the QML owns only
the frames between heartbeats. That split is why the daemon can heartbeat every
five seconds while the orb still animates smoothly.

The daemon resolves the phase in pure bash from a phase-duration array read
once per session. An earlier version forked `jq` several times per 0.25s tick
and cost ~22% of a core for the length of a session; a breathing timer that
heats the laptop rather defeats the point. It is ~2% after the fix.
