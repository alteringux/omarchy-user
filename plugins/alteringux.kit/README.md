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

## Suite-wide authoring and review protocol

The [plugin UI standards and review protocol](../../docs/plugin-standards.md)
applies to every visible package surface. Check it before adding or polishing a
plugin; it links the shared overflow, layout, and accessibility decisions and
defines the evidence required for package-level claims.

## Text overflow standard

For a plugin label that must be elided to fit a bounded inline area, use the
shared `../shared/MarqueeText.qml` component. Keep the full source in `text`;
set its resting font, color, alignment, wrapping, line limit, and elision to
match the old label. The component reveals the complete value on hover without
changing its layout size. Use `Kit.PanelHead`, `Kit.MetaText`, `Kit.SectionHeading`, or a titled
`Kit.Card` when one of those roles fits; they already use the shared component.
Overflowing labels also offer Enter/F2 for a stationary, selectable reader
and the saved text-motion setting. Long prose should wrap in a scrollable
panel or a detail view. See
[`ADR-0008`](../../docs/adr/0008-shared-marquee-for-clipped-plugin-text.md)
and the [consumer inventory](../../docs/prds/marquee-inventory.md).

When a marquee is inside an already-focusable control, set
`focusableOnOverflow: false` on the inner label and give the parent control its
complete accessible name. Its label still moves on pointer hover or while the
parent has keyboard focus; the parent remains the only Tab stop.

For broader panel polish, use the active theme's semantic `Color` / `Kit.Palette`
roles, `Style.font.*` and spacing tokens, visible keyboard/focus states, and
`Style.spacing.controlHeight` for compact clickable controls. Keep flexible
widths nonnegative and put over-height content in `Kit.PanelScroll`. The rules
for all plugin packages are in
[`ADR-0009`](../../docs/adr/0009-theme-aware-plugin-layouts.md).

## Catalogue

The authoritative list of what the kit provides. Keep it current when a
component is added or changed — the `omarchy-kit` skill points sessions here to
decide what to import instead of hand-rolling.

| Import                | File        | What it is | Used by |
|-----------------------|-------------|------------|---------|
| `Kit.Store`           | `Store.qml` | One JSON file, loaded into `value` through a tolerant `parse`, written back by a debounced `save()`. Replaces the per-plugin `FileView` + debounce `Timer` + `mkdir` `Process` + `load/flush/scheduleSave` cluster. `dir` defaults to `~/.local/state/omarchy/`. **Owned mode** (default): the plugin is the only writer. `seedOnCreate: true` writes the serialized default on first run so there's a file to hand-edit. **Watch mode** (`watch: true`): a `bin/` script / the user / another process owns the writes — the Store keeps re-reading + re-parsing as the file changes and emits `externallyChanged(value)` (also on the first read); `pollMs` + `polling` add an idle re-read for FileView's watch-on-create blind spot. | owned: `stocks` (watchlist) · `pomodoro` / `score` (`*-config.json` only) · watch: `score`, `timers`, `countdown`, `pomodoro`, `dashboard`, `stocks`, `newsbar`, `agenda`, `stopwatch` — `score`/`timers`/`countdown`/`pomodoro` state is written by their `omarchy-*` CLI now (`../../docs/adr/0006-cli-first-plugins.md`) |
| `Kit.BugGuard`        | `BugGuard.js` | Per-plugin catch-and-report guard. `Kit.BugGuard.create(pluginId, execFn)` returns `{ run, call, wrap, report }` bound to one plugin; wrap risky work so a throw is logged, handed to `omarchy-plugin-bug-report --source guard`, then swallowed. It is a `.pragma library` (one instance process-wide), so identity lives in the returned object, **not** the module — that is why it is `create()` and not the old stateful `configure()`. Each QML file keeps its own `readonly property var guard: Kit.BugGuard.create(...)`. | all ten `alteringux.*` plugins |
| `Kit.InlineEdit`      | `InlineEdit.qml` | Edit-in-place for a user-authored card label / panel title (ADR-0003): click swaps the `Text` for a pre-filled, fully-selected `TextField`; Enter or focus-out fires `accepted(value)` once if it changed and is non-empty; `Esc` cancels. Host ORs `editing` into its `PanelKeyCatcher.blocked` via an `inlineEditors` count. | `alteringux.timers`, `alteringux.countdown` |
| `Kit.Usage` (+ `UsageModel.js`) | `Usage.qml` | Per-plugin usage analytics + adaptive-UI signal. Give it `pluginId`, call `record("<action>")` from every user action; it keeps `~/.local/state/omarchy/usage/<pluginId>.json` (per-action `count` / `lastAt` / a capped recency ring) via `Kit.Store`. Read-side is pure and total: `rankActions(subset)` orders actions most-used-first (freq × 7-day-half-life recency), plus `topActions(n)`, `actionScore(a)`, `count(a)`, `lastAt(a)`, `isActionDead(a)` (never used, or idle ≥21d and used <3× ever). Assigning a fresh doc on `record()` makes bindings that read the results re-evaluate; `revision` bumps too as a coarse signal. Ranking/decay math is the QML-free, Node-tested `UsageModel.js` (`test/usage.test.js`). | `timers`; rolling out to the other bar-widget plugins |
| `Kit.Palette`         | `Palette.qml` + `PaletteLogic.js` | Theme-aware semantic colors snapped to the 216-color web-safe RGB cube. Text roles choose a color with at least 4.5:1 contrast; non-text accents use 3:1. Translucent surfaces are composited against their backdrop for contrast checks; alpha remains available for overlays. Add one `property QtObject _webPalette: Kit.Palette {}` to each QML component that needs roles. The `.pragma library` resolver shares its contrast cache across those instances. `node test/palette-logic.test.js` checks the cube and contrast behavior. | all plugin components |
| `Kit.EmptyState`      | `EmptyState.qml` | The "nothing here yet" block every panel hand-rolls — a `text` line plus an optional dimmer `hint` line, styled once. Set `foreground` to the host panel's text color. | `timers`; other panels as they are restyled |
| `Kit.PanelScroll`     | `PanelScroll.qml` | The scrollable panel body every overlay hand-rolled as a bare `Flickable { clip; contentHeight; boundsBehavior: StopAtBounds }`. Same thing — it *is* a `Flickable`, so `contentHeight` bindings and a nested `Column { width: parent.width }` are unchanged — plus a fading `ScrollBar.vertical` (AsNeeded) so overflow is discoverable, `interactive` only while overflowing (matches the stock shell panels), and a brisker wheel/two-finger step via an embedded `Kit.WheelBoost`. One knob, `wheelScale` (default `1.9`), tunes the step; `handleColor` tints the bar. Prefer one vertical scroll owner per panel; nest scroll areas only for independently scrolling content. | `countdown`, `dashboard`, `pulse`, `stocks`, `timers`, `dictionary` (overview) |
| `Kit.WheelBoost`      | `WheelBoost.qml` | A tuned `WheelHandler` — point `flick` at a `Flickable`/`ListView`, nest it inside, and mouse-wheel + touchpad scrolling move `scale`× further per event (default `1.9`). Reads `pixelDelta` for touchpads and `angleDelta` for notched wheels, clamps to bounds, and accepts the event so the target's own wheel handling doesn't compound it. Used on its own for `ListView`s (which `PanelScroll` can't wrap); `PanelScroll` embeds one. | `dictionary` (suggestion list); inside every `Kit.PanelScroll` |
| `Kit.Card`            | `Card.qml` | Translucent panel card (`Palette.cardBg` / `cardBorder`, `Style.cornerRadius`) with an optional coloured left spine keyed to a semantic `tone` (`neutral`/`accent`/`positive`/`negative`/`warning`) and an optional UPPERCASE accent title. Content is an explicit `body: Item` it reparents + positions (a default-property slot collapsed height inside Repeater delegates — see ADR-0003). | `conductor` |
| `Kit.SectionHeading`  | `SectionHeading.qml` | The louder header that introduces a card or a group of rows *inside* one — accent, optionally UPPERCASE, bold, optional hairline `rule`. Distinct from the stock `PanelSectionHeader` (the small dim caption at the very top of a whole panel), which stays the panel title. | `flow`, `dashboard` (news/section headings) |
| `Kit.Bullet`          | `Bullet.qml` | One row of a prose list: a glyph in the margin (`▪` default) + a wrapping line. `styled: true` switches the line to `Text.StyledText` (caller escapes via `Kit.Str`). Replaces the per-plugin `Column { Text; Text }` list delegates. | `flow` (brief bullets), `dashboard` |
| `Kit.PanelHead`       | `PanelHead.qml` | The standard panel opener — the shape of the battery overlay's hero: optional `glyph` (nerd-font code point, live or static), Title-Case `title` (`Style.font.title`, bold), and an UPPERCASE tracked `meta` sub-line (hidden when empty). Suite-owned `PanelHero` API with bounded title/meta/detail marquees, theme-muted metadata, a compact `Help` button for mouse access, and a visible F6 controls hint. Keeps `glyph`, `detail`, and `trailingControl` slots. Every `alteringux.*` status panel opens with one; the type ramp it encodes is `../../docs/adr/0005-panel-text-hierarchy.md`. | `countdown`, `dashboard`, `pomodoro`, `stocks`, `stopwatch`, `timers`, `ttsplayer`, `vpnrotate` |
| `Kit.AttentionDot`    | `AttentionDot.qml` | The pulsing corner marker a bar widget shows while it is waiting on the user — extracted verbatim from `alteringux.grip`'s inline `pulseDot`. `active` gates it; `level` (`info`/`warning`/`urgent`/`critical`) picks the `Kit.Palette` colour and whether it breathes (`urgent`/`critical`) or sits steady. Pairs with `WidgetButton.active` + a reddened glyph — it is only the dot. The shared "a plugin needs action" signal is `~/.local/state/omarchy/alteringux-attention.json`, written by `~/.local/bin/omarchy-pulse` and surfaced by `alteringux.pulse`. | `grip`, `pulse` |
| `Kit.MetaText`        | `MetaText.qml` | The dim, tracked caption sub-line on its own — the "DRAINING WATTS" treatment (`Color.muted`, `Style.font.caption`, bold, `letterSpacing 1.2`), for a status *tag* that isn't inside a `Kit.PanelHead`. `content` in, `uppercase` (default true) toggles the case; bounded overflow follows the shared hover-marquee contract (set `wrapMode` to override); hides itself when `content` is empty. **Not** for sentences — those are the hint role (`Kit.Palette.faint` + caption, regular weight). | `score` (the "Score" caption) |

## Keyboard and help standard

Use `Kit.ActionButton` for shell-styled actions: it preserves the shell's
appearance and click/key dispatch, adds native button role/press, and defaults
to keyboard focusability. Set a descriptive name for icon-only controls and
retain availability/state bindings. Custom controls handle keypad Enter along
with Return and Space through the same guarded action.

Use `Kit.KeyboardPanel` for the shell panel and declare its `focusTarget`.
It preserves shell presentation and reasserts that target after the opening
focus prime. `PanelKeys` observes input; it does not choose initial focus.
Explicit F6 then switches between panel shortcuts and native controls.

`Kit.PanelKeys` replaces `PanelKeyCatcher` in user-owned status panels, retaining
its signals and `blocked` editor contract. Set `sectionNavigation: true` when
using `onTabRequested`. F6 enters/leaves native controls; child controls retain
activation and editing keys. Action `qs.Ui.Button`s must set `focusable: true`
and provide an accessible name. F1 opens the visible header's help.

`Kit.RecoveryHelp` / `RecoveryCatalog` refresh the live binding descriptions on
open. Search the recovery subset or browse all described shortcuts. Results
wrap, preserve invocation flags and label submap requirements. Shared panel
shortcut owners contribute their documented F1/F6/Esc/Tab bindings to the
general list. Override `shortcutContext` or supply `additionalShortcutDescriptions` to
document additional bindings from the same definitions used for dispatch.
Neither the view nor its display records can execute a shortcut. The passive
suggestion adapter is verified for Pulse and Timers. Enrollment is available
in their Help view and defaults off. See
[ADR-0010](../../docs/adr/0010-plugin-text-and-control-accessibility.md).

`RecoveryTrigger.js` contains the isolated suggestion policy. Its caller must
supply monotonic milliseconds, physical press identity, Ctrl/Alt/Super presence
(`commandModifier`), and the final `handled`/`unavailable`/`unhandled`/`excluded`
outcome after all owned dispatch layers. Three distinct misses in four seconds
reveal once; dismissal suppresses reopening for 30 seconds. The persisted
`TextPreferences.suggestRecoveryShortcuts` preference defaults off. There is
an observer in `PanelKeys`, gated by owner eligibility, native verification and
the user preference. Pulse and Timers passed the native routing pilot; their
Help view offers explicit enrollment. Other panels retain manual help. `RecoveryClock` reads Linux boot-time milliseconds for deadlines;
`RecoverySuggestions` never takes keyboard focus or executes a result.

## Trade-offs of sharing this way

- **Blast radius.** A syntax error in `Store.qml`, `Palette.qml`,
  `EmptyState.qml`, `PanelHead.qml`, or `MetaText.qml` breaks every plugin
  that imports it; a broken `BugGuard.js` breaks all ten. `Usage.qml`
  degrades to an empty doc rather than throwing.
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
`countdown`, `dashboard`, `pomodoro`, `stocks`, `timers`, `vpnrotate`, and `dictionary`'s overview
step; `dictionary`'s suggestion `ListView` takes a bare `Kit.WheelBoost` +
`ScrollBar`. `flow`'s output/canvas Flickables are the remaining bare ones —
left for the same commit as that plugin's in-flight work. The standard for
what uses these, and the resting-visible-scrollbar + touchpad-travel
decisions, is `../../docs/adr/0004-scrollable-panel-bodies.md`.

`Kit.Usage` / `Kit.Palette` / `Kit.EmptyState` landed together as the
"foundation" pass for the adaptive-UI + restyle work. (`Kit.Card` was first
trialled with a default-property content slot, which collapsed height inside
Repeater delegates; it shipped later with an explicit reparented `body: Item`
instead — see its catalogue row and ADR-0003.) `Usage` is the
substrate for the per-plugin usage-analytics feature (each plugin records its
own actions and reorders / demotes UI from `rank()` / `isDead()`, no code
change per adaptation). `Palette` / `EmptyState` are the shared restyle primitives that retire the
scattered per-plugin hex and copy-pasted empty-state markup. Per-plugin adoption rolls out plugin by
plugin. See `../../docs/adr/0003-edit-in-place-for-card-labels.md` (addenda)
for the history.

`Kit.PanelHead` / `Kit.MetaText` are the text-hierarchy pass: the battery
overlay's "title + UPPERCASE meta sub-line" hero, made the house standard for
every `alteringux.*` status panel and codified in
`../../docs/adr/0005-panel-text-hierarchy.md`. `PanelHead` now owns a compatible hero layout to apply complete-text and
keyboard-help behavior; `MetaText` uses theme-muted tracked captions for a
status line outside a hero. First pass promoted the opener to `Kit.PanelHead`
in `countdown`, `dashboard`, `pomodoro`, `stocks`, `stopwatch`, `timers`,
`ttsplayer`, `vpnrotate` — each with a `glyph:` (static bar icon, or
`hostWidget.icon` bound live for `ttsplayer` / `vpnrotate`). `dashboard` /
`stocks` fold their one Refresh button into `trailingControl`; `pomodoro`
prepends the head above its STATISTICS section. `score` swapped its
hand-rolled "SCORE" caption to `Kit.MetaText` (and `font.pixelSize: 48` →
`Style.fontPx(4)`). `vpnrotate`'s connection detail line became the hint role
(`Kit.Palette.faint` + caption, regular weight), not `MetaText` — it carries
sentences. `flow` keeps its multi-button toolbar header and its deliberately
red "last run" error line (its title promotion is deferred, concurrent WIP).
`dictionary` is exempt (a launcher-style search surface, not a status panel);
the packaged `omarchy.power` battery panel keeps its own inline hero but the
tokens match.
