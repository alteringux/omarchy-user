import QtQuick

// Kit.WheelBoost — a tuned WheelHandler that scrolls a Flickable / ListView
// faster than the platform default, so you're not swiping ten times to reach
// the bottom of a panel. Point `flick` at the scrollable and nest it inside:
//
//   ListView { id: list; ...; Kit.WheelBoost { flick: list } }
//
// Handles a real wheel (angleDelta, notched) and a touchpad two-finger
// scroll (pixelDelta, smooth). Accepts the event so the target's own wheel
// handling doesn't also fire and compound the movement.
WheelHandler {
  // The Flickable (or ListView, which is one) to scroll. Left null == inert.
  property Flickable flick: null
  // Multiplier over the platform's default step. 1.0 == stock feel.
  property real scale: 1.9
  // Pixels per mouse notch on the angleDelta path, before `scale`. The
  // touchpad path already arrives in pixels, so it only takes `scale`.
  property real lineStep: 56

  enabled: !!flick
  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
  onWheel: function (ev) {
    if (!flick)
      return
    var maxY = Math.max(0, flick.contentHeight - flick.height)
    if (maxY <= 0)
      return

    var dy = 0
    if (ev.pixelDelta.y !== 0)
      dy = ev.pixelDelta.y * scale
    else if (ev.angleDelta.y !== 0)
      dy = (ev.angleDelta.y / 120) * lineStep * scale
    else
      return

    flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - dy))
    ev.accepted = true
  }
}
