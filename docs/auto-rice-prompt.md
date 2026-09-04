# Omarchy bar "rice" auto-improve — run instructions

You are running unattended (no human reviews changes before they land, but a
smoke test gates the commit — see the scheduler's own logic, not yours). Your
job is to wire ONE bar widget into the shared cross-plugin attention feed so
the bar becomes a live signal surface instead of every widget being an island.
The target plugin id and directory are given in the run message.

## Scope — read carefully, this is narrower than a normal auto-improve run

- Modify **only** `plugins/<id>/BarWidget.qml`. Nothing else.
- Never modify: any other plugin, `plugins/alteringux.kit`, `shell.json`,
  `shell.toml`, hooks, flows, themes, `~/.local/bin`, `local-bin/`, docs, or
  anything outside that one file.
- Never run git write commands. The scheduler commits your changes.
- Never edit this file, other docs, or the changelog.
- If `Kit.PulseTint` already appears in the target file, make no changes —
  it is already wired.

## What "wired" means

`alteringux.kit` ships `Kit.PulseTint`, a component that reads a plugin's own
entry from the shared attention feed
(`~/.local/state/omarchy/alteringux-attention.json`, written by
`omarchy-pulse attention <id> ...` / `omarchy-pulse clear <id>`, called from
that plugin's own backing script or CLI — you are not adding those calls,
just rendering what may already exist or arrive later), and `Kit.AttentionDot`,
the small pulsing corner marker that renders it. Wire the target's
`BarWidget.qml` to show one, following this exact reference (copied from
`plugins/alteringux.vpnrotate/BarWidget.qml`, already shipped and working):

```qml
import "../alteringux.kit" as Kit   // already present in every plugin — don't duplicate

  readonly property var guard: Kit.BugGuard.create("alteringux.vpnrotate", ...)

  Kit.PulseTint {
    id: pulseTint
    pluginId: "alteringux.vpnrotate"   // use the TARGET plugin's own id here
  }
```

and, on whatever `Item` is the widget's visible clickable surface (usually a
`WidgetButton { ... }`, sometimes named differently — read the file to find
it):

```qml
    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 2
      active: pulseTint.active
      level: pulseTint.level
    }
```

## Rules

- `pluginId` must be the exact manifest id of the target plugin (matches the
  directory name, e.g. `alteringux.netwatch`).
- If the widget already renders its own local `Kit.AttentionDot` bound to a
  locally-computed condition (e.g. netwatch's quota warning), leave it alone —
  do not touch plugins that already have `Kit.AttentionDot` OR `Kit.PulseTint`
  in their `BarWidget.qml`; the scheduler will not send you one of those.
- Anchor the dot on the actual clickable root (button/rectangle), not on the
  outer `Item`, so it's visible — match the reference's anchor pattern unless
  the target's layout genuinely doesn't have an equivalent surface, in which
  case pick the most visually sensible corner of whatever is rendered.
- Keep the diff minimal: one `Kit.PulseTint` block, one `Kit.AttentionDot`
  block, nothing else changed. Do not add comments beyond what's already in
  the reference above.
- Do not add new dependencies, new files, or new `~/.local/bin` helpers.

## Output protocol (required)

Write exactly one line (max 120 characters, changelog style, no leading dash)
to `~/.local/state/omarchy-auto-improve/rice-summary-<id>`:

- If you wired it: `wired Kit.PulseTint + AttentionDot`
- If you skipped it (already wired, or no sensible anchor surface exists):
  exactly `no changes` — and in the "no sensible anchor" case, make no edits.

Then stop. Do not start any other work.
