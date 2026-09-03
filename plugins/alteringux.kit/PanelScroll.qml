import QtQuick
import QtQuick.Controls
import qs.Commons

// Kit.PanelScroll — the scrollable panel body every alteringux.* overlay
// hand-rolls: a clipped vertical Flickable whose Column of content can be
// taller than the panel. Adds the two things the bare Flickable lacked —
//
//   • a visible vertical ScrollBar (AsNeeded) so overflow is discoverable
//   • a brisker wheel / two-finger step via Kit.WheelBoost
//
// Drop-in for the old block — it IS a Flickable, so every existing binding
// (contentHeight, a nested `Column { width: parent.width }`, anchors)
// behaves exactly as before:
//
//   Kit.PanelScroll {
//     anchors.fill: parent
//     contentHeight: content.implicitHeight
//     Column { id: content; width: parent.width; ... }
//   }
//
// clip / boundsBehavior / flickableDirection are already set; keep binding
// contentHeight from your inner column.
Flickable {
  id: root

  // Forwarded to Kit.WheelBoost. `wheelScale` is the one knob to tune feel.
  property real wheelScale: 1.9
  // Scrollbar handle colour. Faint grey by default so it reads as chrome,
  // not content; a host can pass its panel foreground for more contrast.
  property color handleColor: Qt.rgba(0.5, 0.5, 0.5, 0.9)

  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  // Only grab drags when there's something to scroll — matches the stock
  // shell panels (shell/plugins/agents/Panel.qml). The wheel keeps working
  // via WheelBoost regardless, on its own overflow check.
  interactive: contentHeight > height

  ScrollBar.vertical: ScrollBar {
    id: vbar
    policy: ScrollBar.AsNeeded
    contentItem: Rectangle {
      implicitWidth: Style.space(6)
      radius: width / 2
      color: root.handleColor
      opacity: vbar.pressed ? 0.9 : (vbar.hovered ? 0.7 : (vbar.active ? 0.45 : 0.0))
      Behavior on opacity {
        NumberAnimation { duration: 120 }
      }
    }
  }

  WheelBoost {
    flick: root
    scale: root.wheelScale
  }
}
