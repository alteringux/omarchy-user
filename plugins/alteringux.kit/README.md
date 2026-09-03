# alteringux.kit

Shared building blocks for the `alteringux.*` Omarchy shell plugins, so the
same plumbing isn't hand-copied into every plugin directory.

## Not a plugin

This directory has **no `manifest.json`**, so the shell's `PluginRegistry`
never sees it (`scan_thirdparty` skips any directory without a manifest). It is
just a folder of shared QML/JS that sibling plugins pull in by relative path:

```qml
import "../alteringux.kit" as Kit

Kit.Store { /* ... */ }
```

The `PluginRegistry` sandbox only validates a plugin's **manifest entry
point** — it does nothing about transitive QML/JS imports — so a relative
`../alteringux.kit` import from a plugin file resolves on disk like any other.

## Catalogue

The authoritative list of what the kit provides. Keep it current when a
component is added or changed — the `omarchy-kit` skill points sessions here to
decide what to import instead of hand-rolling.

| Import                | File        | What it is | Used by |
|-----------------------|-------------|------------|---------|
| `Kit.Store`           | `Store.qml` | One JSON file, loaded into `value` through a tolerant `parse`, written back by a debounced `save()`. Replaces the per-plugin `FileView` + debounce `Timer` + `mkdir` `Process` + `load/flush/scheduleSave` cluster. `dir` defaults to `~/.local/state/omarchy/`. **Owned mode** (default): the plugin is the only writer. `seedOnCreate: true` writes the serialized default on first run so there's a file to hand-edit. **Watch mode** (`watch: true`): a `bin/` script / the user / another process owns the writes — the Store keeps re-reading + re-parsing as the file changes and emits `externallyChanged(value)` (also on the first read); `pollMs` + `polling` add an idle re-read for FileView's watch-on-create blind spot. | owned: `timers`, `countdown`, `score`, `pomodoro`, `stocks` (watchlist) · watch: `dashboard`, `stocks`, `newsbar`, `agenda`, `stopwatch` |
| `Kit.BugGuard`        | `BugGuard.js` | Per-plugin catch-and-report guard. `Kit.BugGuard.create(pluginId, execFn)` returns `{ run, call, wrap, report }` bound to one plugin; wrap risky work so a throw is logged, handed to `omarchy-plugin-bug-report --source guard`, then swallowed. It is a `.pragma library` (one instance process-wide), so identity lives in the returned object, **not** the module — that is why it is `create()` and not the old stateful `configure()`. Each QML file keeps its own `readonly property var guard: Kit.BugGuard.create(...)`. | all ten `alteringux.*` plugins |
| `Kit.InlineEdit`      | `InlineEdit.qml` | Edit-in-place for a user-authored card label / panel title (ADR-0003): click swaps the `Text` for a pre-filled, fully-selected `TextField`; Enter or focus-out fires `accepted(value)` once if it changed and is non-empty; `Esc` cancels. Host ORs `editing` into its `PanelKeyCatcher.blocked` via an `inlineEditors` count. | `alteringux.timers`, `alteringux.countdown` |
| `Kit.Usage` (+ `UsageModel.js`) | `Usage.qml` | Per-plugin usage analytics + adaptive-UI signal. Give it `pluginId`, call `record("<action>")` from every user action; it keeps `~/.local/state/omarchy/usage/<pluginId>.json` (per-action `count` / `lastAt` / a capped recency ring) via `Kit.Store`. Read-side is pure and total: `rankActions(subset)` orders actions most-used-first (freq × 7-day-half-life recency), plus `topActions(n)`, `actionScore(a)`, `count(a)`, `lastAt(a)`, `isActionDead(a)` (never used, or idle ≥21d and used <3× ever). Assigning a fresh doc on `record()` makes bindings that read the results re-evaluate; `revision` bumps too as a coarse signal. Ranking/decay math is the QML-free, Node-tested `UsageModel.js` (`test/usage.test.js`). | `timers`; rolling out to the other bar-widget plugins |
| `Kit.Palette`         | `Palette.qml` | Singleton of semantic status colors the shell palette lacks: `positive` / `negative` / `warning` (fixed, legible on light + dark), `info` / `urgent` (track the theme), `faint` (pre-dimmed foreground). Replaces the hardcoded hex every plugin grew (`#d29922`, `#4CAF50` / `#F44336` / `#FF9800`, stocks' up/down greens). | `timers`; `pomodoro` / `countdown` / `stocks` per their restyle pass |
| `Kit.EmptyState`      | `EmptyState.qml` | The "nothing here yet" block every panel hand-rolls — a `text` line plus an optional dimmer `hint` line, styled once. Set `foreground` to the host panel's text color. | `timers`; other panels as they are restyled |
| `Kit.PanelScroll`     | `PanelScroll.qml` | The scrollable panel body every overlay hand-rolled as a bare `Flickable { clip; contentHeight; boundsBehavior: StopAtBounds }`. Same thing — it *is* a `Flickable`, so `contentHeight` bindings and a nested `Column { width: parent.width }` are unchanged — plus a fading `ScrollBar.vertical` (AsNeeded) so overflow is discoverable, `interactive` only while overflowing (matches the stock shell panels), and a brisker wheel/two-finger step via an embedded `Kit.WheelBoost`. One knob, `wheelScale` (default `1.9`), tunes the step; `handleColor` tints the bar. | `countdown`, `dashboard`, `stocks`, `timers`, `dictionary` (overview) |
| `Kit.WheelBoost`      | `WheelBoost.qml` | A tuned `WheelHandler` — point `flick` at a `Flickable`/`ListView`, nest it inside, and mouse-wheel + touchpad scrolling move `scale`× further per event (default `1.9`). Reads `pixelDelta` for touchpads and `angleDelta` for notched wheels, clamps to bounds, and accepts the event so the target's own wheel handling doesn't compound it. Used on its own for `ListView`s (which `PanelScroll` can't wrap); `PanelScroll` embeds one. | `dictionary` (suggestion list); inside every `Kit.PanelScroll` |

## Trade-offs of sharing this way

- **Blast radius.** A syntax error in `Store.qml`, `Palette.qml`, or
  `EmptyState.qml` breaks every plugin that imports it; a broken
  `BugGuard.js` breaks all ten. `Usage.qml` degrades to an empty doc rather
  than throwing.
- **Hot reload.** The shell's file watcher keys on the top-level plugin
  directory, so editing a file in here emits `localPluginChanged("alteringux.kit")`
  only — dependent plugins don't reload on their own. Run
  `omarchy restart shell` after changing the kit.
- **Portability.** A plugin directory that imports the kit is no longer
  independently copyable without it. These plugins live together in one repo,
  so that's acceptable here.

## Status

`BugGuard.js` is imported by all ten `alteringux.*` plugins; `InlineEdit.qml`
by the two card-list plugins; `Kit.Store` by nine plugins — every one that
touches a JSON file except `newsbar`'s feeds config and `agenda`'s
runtime-dir state write (a base64 hop, not a `FileView`). No plugin
hand-rolls a `FileView` + save `Timer` + `mkdir` cluster any more.

`Kit.PanelScroll` / `Kit.WheelBoost` landed together to give the overflowing
overlays a real scrollbar and a faster scroll step. `PanelScroll` is in
`countdown`, `dashboard`, `stocks`, `timers`, and `dictionary`'s overview
step; `dictionary`'s suggestion `ListView` takes a bare `Kit.WheelBoost` +
`ScrollBar`. `flow`'s output/canvas Flickables are the remaining bare ones —
left for the same commit as that plugin's in-flight work. The standard for
what uses these, and the resting-visible-scrollbar + touchpad-travel
decisions, is `../../docs/adr/0004-scrollable-panel-bodies.md`.

`Kit.Usage` / `Kit.Palette` / `Kit.EmptyState` landed together as the
"foundation" pass for the adaptive-UI + restyle work. (A `Kit.Card` wrapper
was trialled and dropped — its nested content slot collapsed height inside
Repeater delegates, and a plain themed `Rectangle` per panel is a couple of
lines anyway.) `Usage` is the
substrate for the per-plugin usage-analytics feature (each plugin records its
own actions and reorders / demotes UI from `rank()` / `isDead()`, no code
change per adaptation). `Palette` / `EmptyState` are the shared restyle primitives that retire the
scattered per-plugin hex and copy-pasted empty-state markup. Per-plugin adoption rolls out plugin by
plugin. See `../../docs/adr/0003-edit-in-place-for-card-labels.md` (addenda)
for the history.
