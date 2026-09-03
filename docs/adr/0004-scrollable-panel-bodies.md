# Scrollable panel bodies use Kit.PanelScroll, scrollbar visible at rest

Most `alteringux.*` panels have a body that can grow taller than the panel —
a newest-first card list, a progressive word breakdown, a rendered brief. The
straightforward way is a bare `Flickable` with `clip` and `contentHeight`, and
that is what every panel grew independently. It has two problems: no visible
scrollbar (so nothing signals that the panel scrolls), and the platform
default wheel/two-finger step is small enough that a touchpad drag barely
moves the content.

The rule instead: **a panel body that can overflow is a `Kit.PanelScroll`,
never a bare `Flickable`.** It is a `Flickable` subclass, so `contentHeight`
bindings and a nested `Column { width: parent.width }` are unchanged; it bakes
in `clip: true`, `boundsBehavior: StopAtBounds`, `flickableDirection:
VerticalFlick`, `interactive: contentHeight > height` (drag only while there is
something to scroll — matches the stock shell panels), a vertical `ScrollBar`,
and an embedded `Kit.WheelBoost`. A migration is: rename `Flickable {` to
`Kit.PanelScroll {`, delete the now-redundant `clip` / `boundsBehavior` lines,
keep everything else.

**The scrollbar is visible whenever the content overflows, not only while it
is being dragged.** `policy: ScrollBar.AsNeeded` hides the whole bar when the
content fits; when it does not, the handle sits at a non-zero resting opacity
(`0.4`), rising on hover (`0.8`) and press (`1.0`). The first cut keyed the
resting opacity on `ScrollBar.active`, which is false at rest — so the bar was
transparent until grabbed and there was still no scroll affordance. The
resting value must be non-zero.

**Scroll travel is amplified for touchpads by default**, via `Kit.WheelBoost`
(embedded in `PanelScroll`; used standalone for `ListView`s). It handles three
input shapes in one handler — `pixelDelta` (touchpad / hi-res wheel),
`angleDelta >= 120` (one mouse notch), `angleDelta < 120` (a touchpad
reporting via angle) — then multiplies by `wheelScale`. Defaults live in the
kit: `wheelScale 1.5`, `touchpadGain 3.5`, `lineStep 90` px per notch. The
reason for the split: a MacBook touchpad's per-event deltas are tiny, and
normalising a sub-notch `angleDelta` by a full 120-unit notch collapses it to
almost nothing — so the sub-notch branch and `touchpadGain` carry the
amplification, while a real mouse notch stays a sane fixed step. `wheelScale`
is the one knob to turn up (per plugin, or in the kit) if it still feels
short.

**A scrollable `ListView`** cannot be a `PanelScroll` (it manages its own
delegates). It gets the same treatment inline:
`ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }` plus
`Kit.WheelBoost { flick: <listViewId> }`.

Tuning knobs, for when the defaults need to move: `alteringux.kit/PanelScroll.qml`
(`wheelScale` default, resting/hover/press opacity, handle width
`Style.space(6)`, `handleColor`) and `alteringux.kit/WheelBoost.qml`
(`touchpadGain`, `lineStep`).

## Scope

Migrated to `Kit.PanelScroll`: `alteringux.countdown`, `alteringux.dashboard`,
`alteringux.stocks`, `alteringux.timers` (panel body), and
`alteringux.dictionary` (the overview-step Flickable). `alteringux.dictionary`'s
suggestion `ListView` took the inline `ScrollBar` + `Kit.WheelBoost` pair.

Pending: `alteringux.flow`'s output Flickable — the migration is written but
held uncommitted until that plugin's in-flight work lands, to avoid a merge
tangle. `flow`'s canvas Flickable is a 2-D node-graph pan surface, not a
vertical body: it takes `ScrollBar.vertical` + `ScrollBar.horizontal` for
visibility but **not** `Kit.WheelBoost` — wheel-to-scroll there would fight
the drag-to-pan gesture.

No applicable surface yet: `alteringux.pomodoro`, `alteringux.score`,
`alteringux.stopwatch`, `alteringux.ttsplayer`, `alteringux.vpnrotate`. Each
has a `content` Column sized by `panel.fittedContentHeight(content.implicitHeight)`
with no Flickable — the panel grows to fit, capped at the screen by
`fittedContentHeight`, and none currently produces enough content to hit that
cap. If a future version of one can grow unbounded, wrap its `content` Column
in a `Kit.PanelScroll` (`anchors.fill: parent`, `contentHeight:
content.implicitHeight`) — the same shape as the migrated five.

A future plugin whose panel body can be taller than the panel uses
`Kit.PanelScroll` for that body and never a bare `Flickable`; a scrollable
`ListView` in a plugin takes an inline `ScrollBar` + `Kit.WheelBoost`.
