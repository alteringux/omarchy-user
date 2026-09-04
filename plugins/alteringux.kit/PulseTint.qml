import QtQuick
import "." as Kit

// Kit.PulseTint — a plugin's read-only window onto its OWN entry in the
// shared alteringux.pulse attention feed
// (~/.local/state/omarchy/alteringux-attention.json, written by
// `omarchy-pulse attention <id> ...` / `omarchy-pulse clear <id>`).
//
// The point is cross-plugin interaction, not local state: a widget can light
// up from something ANOTHER script raised on its behalf (or its own CLI did,
// out of band from the widget's own computed properties), so the bar becomes
// one shared signal surface instead of every plugin re-deriving its own dot.
// Pair with Kit.AttentionDot:
//
//   Kit.PulseTint { id: pulseTint; pluginId: "alteringux.vpnrotate" }
//   Kit.AttentionDot {
//     active: pulseTint.active
//     level: pulseTint.level
//   }
//
// A plugin that already computes its own attention-worthy condition locally
// (alteringux.netwatch's quota, alteringux.grip's needsAction) does not need
// this — it's for widgets with nothing to say about themselves until the
// shared feed says otherwise.
Item {
  id: root

  // The manifest id this widget wants its attention entry for, e.g.
  // "alteringux.vpnrotate". Empty means "show nothing".
  property string pluginId: ""

  readonly property var _item: {
    var items = store.value && store.value.items
    return (items && root.pluginId && items[root.pluginId]) || null
  }

  readonly property bool active: !!root._item
  readonly property string level: root._item ? root._item.level : "info"
  readonly property string label: root._item ? root._item.label : ""

  Kit.Store {
    id: store
    fileName: "alteringux-attention.json"
    watch: true
    pollMs: 4000
  }
}
