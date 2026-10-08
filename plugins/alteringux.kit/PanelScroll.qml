import QtQuick
import QtQuick.Controls
import "." as Kit
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
  property QtObject _webPalette: Kit.Palette {}
  id: root

  // Forwarded to Kit.WheelBoost. `wheelScale` is the one knob to tune feel —
  // turn it up if a touchpad drag still covers too little ground.
  property real wheelScale: 1.5
  readonly property bool overflowing: height > 0 && contentHeight > height
  // The handle uses the theme foreground with state-dependent opacity.
  property color handleColor: _webPalette.foreground

  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  // Only grab drags when there's something to scroll — matches the stock
  // shell panels (shell/plugins/agents/Panel.qml). The wheel keeps working
  // via WheelBoost regardless, on its own overflow check.
  interactive: overflowing

  ScrollBar.vertical: ScrollBar {
    id: vbar
    // AsNeeded can hide only the styled handle while leaving a live control
    // over the content edge. Explicit availability prevents an unused bar
    // from intercepting row hover or action input when there is no overflow.
    policy: ScrollBar.AsNeeded
    visible: root.overflowing
    enabled: visible
    interactive: visible
    contentItem: Rectangle {
      implicitWidth: Style.space(6)
      radius: width / 2
      color: root.handleColor
      opacity: vbar.pressed ? 1.0 : (vbar.hovered ? 0.8 : 0.4)
      Behavior on opacity {
        NumberAnimation { duration: 120 }
      }
    }
  }

  WheelBoost {
    flick: root
    wheelScale: root.wheelScale
  }
}
