# Edit user-authored labels in place, applied on focus-out

Countdown, timers, and any future card-list plugin show a user-typed label on
each card. The straightforward way to let the user fix a typo would be an
"edit" affordance per card — a pencil button, or a row that opens the add form
pre-filled. We considered that and rejected it.

The rule instead: **any user-authored label shown on a card, or as a panel
title, is edited in place.** Clicking the label swaps it for a text field
pre-filled with the current text and fully selected. Committing — pressing
Enter, or focus leaving the field for any reason — applies the change
immediately and persists it. `Esc` cancels back to the original. There is no
separate edit mode, no save button, no confirmation dialog. A blank or
unchanged value is a no-op (the original stands).

This is implemented once as `InlineEdit.qml` — originally copied per plugin,
now shared from `alteringux.kit/` as `Kit.InlineEdit` (see the addendum; the
"no shared import path" premise turned out to be wrong). The plugin's `Model.js` gains a
`renameEntry(state, id, label)` pure function, the `BarWidget` a matching
`renameEntry` host method and a `rename` IPC verb, so a rename goes through
the same persist path as add/remove.

While an inline field is open the panel must route keystrokes to it — each
panel keeps an `inlineEditors` count and ORs `inlineEditors > 0` into its
`PanelKeyCatcher.blocked`, alongside the existing add-field check. That is
what lets `Esc` reach the field to cancel instead of closing the panel.

## Scope

Applies now to `alteringux.countdown` and `alteringux.timers` (card `label`).

Already consistent with the rule, no change needed:
- `alteringux.stopwatch` — the pre-start label field already applies on
  `editingFinished`.
- `alteringux.pomodoro` — sound-path fields apply on `editingFinished`;
  numeric config applies live via `NumberField.onModified`.

No applicable surface:
- `alteringux.dashboard` — the notes/news/system cards are written by the
  `bin/` scripts and rendered read-only; there is no user-authored label in
  the panel.
- `alteringux.score` — the card is an icon plus a number, no text label.
- `alteringux.stocks` — tickers are symbols added and removed, not renamed.
- `alteringux.dictionary`, `alteringux.agenda`, `alteringux.newsbar` — no
  card/panel of this shape.

A future plugin that shows a user-typed label on a card adopts `InlineEdit.qml`
rather than inventing an edit affordance of its own.

## Addendum (2026-09-01) — "no shared import path" was wrong

This ADR (and `CONTEXT.md`) asserted the plugins are "independent directories
with no shared import path", which is why `InlineEdit.qml` and `BugGuard.js`
are copied per plugin. That premise does not hold: plugin entry points load via
`Qt.createComponent(fileUrl)`, and `PluginRegistry` sandboxes only the
*manifest entry point* — not transitive QML/JS imports. A plugin file can
`import "../alteringux.kit" as Kit` and the engine resolves it on disk. A
sibling directory with no `manifest.json` is invisible to the registry yet
importable.

So a shared library *is* available. Its real costs are blast radius (one broken
file breaks every dependent), hot-reload (the shell's watcher keys on the
top-level dir, so kit edits need `omarchy restart shell`), and loss of
per-directory portability — acceptable for plugins that live in one repo.

**What changed (2026-09-01):** `alteringux.kit/Store.qml` took the persistence
cluster (`FileView` + atomic write + `mkdir -p` + debounced save) that was
hand-copied into every widget, adopted as a two-plugin trial in
`alteringux.timers` and `alteringux.countdown`.

**Follow-up (2026-09-01):** the trial held. `BugGuard.js` and `InlineEdit.qml`
have moved into `alteringux.kit/` too:

- `Kit.InlineEdit` — the single component this ADR describes; `alteringux.timers`
  and `alteringux.countdown` now use `Kit.InlineEdit { }` and carry no local
  copy. Any future card-list plugin does the same.
- `Kit.BugGuard` — imported by **all ten** `alteringux.*` plugins. It is a
  `.pragma library`, so it is one instance for the whole shell process; the old
  `configure(pluginId, exec)` that set module globals would have had the last
  plugin to load win. It is now `Kit.BugGuard.create(pluginId, exec)`, which
  returns a `{ run, call, wrap, report }` object bound to that plugin, and each
  QML file keeps its own `readonly property var guard`.

So "copied per plugin" no longer describes anything in this repo.

**Follow-up 2 (2026-09-01):** `Kit.Store` adoption extended to `alteringux.score`
(config + state) and `alteringux.pomodoro` (config + stats + history). Each
plugin dropped its hand-rolled `FileView` + save `Timer` + `mkdir` `Process` +
`load/flush/schedule*Save` cluster; `config` / `state` / `stats` / `history`
became `property alias`es onto the stores, and the tolerant parsers moved into
the plugins' `Model.js` as `parseConfig` / `parseState` / `parseStats` /
`parseHistory` (unit-tested). One kit addition: `Store.seedOnCreate` (bool,
default false) writes the serialized default on first run when the file is
missing — `score`/`pomodoro` set it on their *config* store so there's a file
to hand-edit (score's icon/step have no panel UI).

**Follow-up 3 (2026-09-01):** `Kit.Store` gained a **watch mode** and the last
five hand-rolled `FileView`s moved onto it: `dashboard`, `stocks`, `newsbar`,
`agenda`, `stopwatch`. These read files written by external `bin/` scripts (or,
for `agenda`, hand-edited by the user), so `watch: true` keeps `FileView.watchChanges`
on, re-reads + re-parses on every change, and emits `externallyChanged(value)`;
`pollMs` + `polling` add an idle re-read for FileView's watch-on-create blind
spot (a file created/recreated after the widget was built keeps a dead inode
watch). `stocks` also moved its plugin-owned watchlist to an owned `Kit.Store`
(new `Model.parseWatchlist`, unit-tested). `_lastRaw`-comparison in `_adopt`
means a reload triggered by the Store's own `save()` does not re-emit
`externallyChanged`.

What still isn't a `Kit.Store`: `newsbar`'s feeds config (`newsbar-feeds.json` —
bidirectional, seeded with a bespoke JSON string, not `Model`-parsed), its
`toggles/` directory watch (watches a dir, not a file), and `agenda`'s state
write (a base64 `printf | base64 -d >` hop, never a `FileView`). Everything else
in every plugin goes through the kit now.
