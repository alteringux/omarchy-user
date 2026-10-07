import QtQuick
import "." as Kit
import qs.Commons

// Kit.AttentionDot — the small corner marker an alteringux.* bar widget shows
// while it is waiting on the user. Extracted verbatim from alteringux.grip's
// inline `pulseDot` so every plugin signals "act on me" with the same shape,
// colour ramp and pulse.
//
//   WidgetButton {
//     // ...
//     Kit.AttentionDot {
//       anchors { top: parent.top; right: parent.right
//                 topMargin: Style.spaceReal(3); rightMargin: Style.spaceReal(2) }
//       active: root.needsAction
//       level: root.attentionLevel   // "info" | "warning" | "urgent" | "critical"
//     }
//   }
//
// `active` gates visibility. `level` picks the colour (via Kit.Palette) and
// whether it pulses: `info` / `warning` sit steady, `urgent` / `critical`
// breathe. The host is still responsible for the louder cues that pair with it
// (WidgetButton.active, a reddened glyph) — this is just the dot.
Rectangle {
  id: root

  property bool active: false
  property string level: "urgent"

  readonly property bool pulsing: root.level === "urgent" || root.level === "critical"

  width: Math.max(5, Style.spaceReal(5))
  height: width
  radius: width / 2
  visible: root.active

  color: {
    if (root.level === "critical") return Kit.Palette.negative
    if (root.level === "warning") return Kit.Palette.warning
    if (root.level === "info") return Kit.Palette.info
    return Kit.Palette.urgent
  }

  SequentialAnimation on opacity {
    running: root.visible && root.pulsing
    loops: Animation.Infinite
    NumberAnimation { to: 0.25; duration: 650; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutSine }
  }

  // Steady levels still want full opacity when the animation isn't running.
  onPulsingChanged: if (!pulsing) opacity = 1.0
}
