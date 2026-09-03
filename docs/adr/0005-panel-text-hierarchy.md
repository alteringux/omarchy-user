# Panel text hierarchy: one type ramp, PanelHead opener, MetaText sub-line

The stock battery overlay (`omarchy.power`) opens its panel with a hero: a
battery glyph, a bold Title-Case **Battery**, and — directly under it — a
small, dim, letter-spaced **UPPERCASE** sub-line that rotates through
"DRAINING WATTS" / "POURING JUICE" / the plain mode label. That sub-line is
the `meta` slot of `qs.Ui.PanelHero`, and the same treatment recurs across the
stock shell (`agents`, `dropbox`, `tailscale` panels).

None of the `alteringux.*` panels used it. Each opened with a bare
`PanelSectionHeader { text: "STOPWATCH" }` (the small dim caption meant for
*sections within* a panel, not the panel title) followed by an ad-hoc status
`Text` — mostly `Style.font.bodySmall` bold, sometimes `Qt.darker(fg, 1.4)`,
sometimes `opacity: 0.6`, `score` had a raw `font.pixelSize: 48`. No shared
rule, so no two panels agreed on what a title, a status line, or a hint looked
like.

## The ramp

Every text role in an `alteringux.*` panel resolves to one row of this table.
Sizes are always `Style.font.*` tokens — never a pixel literal, so a theme's
`[font] base-size` and per-token overrides still carry.

| Role | Size token | Weight | Case | Colour |
|---|---|---|---|---|
| Panel title (hero) | `Style.font.title` | bold | Title Case | `foreground` |
| Hero meta / status sub-line | `Style.font.caption`, `letterSpacing 1.2` | bold | UPPERCASE | `Qt.darker(foreground, 1.4)` |
| Section header within a panel | `Style.font.caption` (`PanelSectionHeader`) | bold | UPPERCASE | `Qt.darker(foreground, 1.4)` |
| Primary readout / big number | `Style.font.display` / `displayLarge` | bold | — | `foreground` |
| Body row label | `Style.font.bodySmall` | regular | — | `foreground` @ 0.6 |
| Body row value | `Style.font.bodySmall` | regular or bold | — | `foreground` |
| Hint / tertiary / source line | `Style.font.caption` | regular | — | `Kit.Palette.faint` |
| Explanatory sentence | `Style.font.caption` | regular | sentence | `Kit.Palette.faint` |

The distinction that keeps biting: **the status sub-line is a glanceable tag**
(short, UPPERCASE, tracked — "3 RUNNING", "ON BATTERY"). A full sentence
("Seeking isn't available for streaming TTS.") is the *hint* role — regular
weight, `Kit.Palette.faint`, no letter-spacing, not uppercased. Don't run a
sentence through the meta treatment.

## The components

**`Kit.PanelHead`** — the standard opener. Wraps `qs.Ui.PanelHero`, takes the
glyph as a plain string (`glyph:`), leaves `foreground` for the caller to bind
to its bar text colour. `meta` hides itself when empty, so a panel with no
glanceable status is just the promoted Title-Case title. `detail` (a bordered
pill) and `trailingControl` pass through to `PanelHero`.

```qml
Kit.PanelHead {
  title: "Stopwatch"
  meta: hostWidget && hostWidget.active ? "Running" : "Ready"
  foreground: root.barForeground
}
```

**`Kit.MetaText`** — the meta treatment on its own, for a status line that is
not inside a `Kit.PanelHead` (a custom hero, a toolbar-row header). `content`
in, `uppercase` (default true) toggles case, hides itself when `content` is
empty.

```qml
Kit.MetaText { content: "SCORE"; foreground: root.bar.foreground }
```

## Rules

- **A status panel opens with `Kit.PanelHead`.** The first thing in the
  content Column is the head; `PanelSectionHeader` is only for sections
  *below* it. If the panel already leads with a genuine section ("STATISTICS"
  in `pomodoro`), prepend a `Kit.PanelHead { title: "<Plugin>" }` and keep the
  section header under it. The one exception is a header that is a
  multi-control toolbar (`flow`: Output / Canvas / Run) — `PanelHero` has a
  single `trailingControl`, so that row keeps its `RowLayout` +
  `PanelSectionHeader`, and only its status text follows the ramp.
- **Promote the title to Title Case.** `"STOPWATCH"` → `title: "Stopwatch"`.
  `PanelHead` renders it at `Style.font.title` bold; it is no longer the
  same visual as a section header.
- **The status sub-line is `meta` (in a head) or `Kit.MetaText` (outside
  one).** No more hand-rolled `Text { color: Qt.darker(fg, 1.4); font.bold;
  font.letterSpacing }`.
- **No pixel-literal font sizes.** `font.pixelSize: 48` → `Style.fontPx(4)`
  (or the nearest `Style.font.*` token).
- **Hints and sentences use `Kit.Palette.faint` at `Style.font.caption`,
  regular weight** — not the meta treatment.

## Scope

First pass:

- **Opener promoted to `Kit.PanelHead`:** `countdown`, `dashboard`, `pomodoro`
  (prepended, above STATISTICS), `stocks`, `stopwatch`, `timers`, `ttsplayer`,
  `vpnrotate`. `dashboard` and `stocks` fold their single Refresh button into
  `trailingControl` and their "refreshing…" text into `meta`.
- **Hand-rolled dim status line → `Kit.MetaText`:** `score` (the "SCORE"
  caption; the icon literal `48` → `Style.fontPx(4)`), `vpnrotate` (the
  connection detail line). `ttsplayer`'s old bold status `Text` was folded
  into the head's `meta`; its remaining detail line lost the redundant state
  word.
- **Left as-is:** `flow` — its header is a four-control toolbar (`PanelSectionHeader`
  + Output / Canvas / Run), which `PanelHero`'s single `trailingControl` can't
  hold, and its "last run" line is deliberately `Kit.Palette.negative` red, not
  the neutral meta grey. Font tokens there were already clean.
- **Exempt:** `alteringux.dictionary` — a launcher-style search surface built
  on `Color.menu.*` and custom card chrome, not a status panel. Its header is
  a search field, not a title.
- **Not ours:** the packaged `omarchy.power` battery panel keeps its own
  inline hero (it lives under `/usr/share/omarchy`, read-only), but the tokens
  are identical so it reads as part of the same family.
- **Services with no panel:** `agenda`, `notifications` — nothing to do.

A future `alteringux.*` status panel opens with `Kit.PanelHead` and uses
`Kit.MetaText` for any status line outside it; it never re-rolls the dim
tracked-caption `Text` and never hard-codes a font pixel size.
