import QtQuick

// Kit.WheelBoost — a tuned WheelHandler that scrolls a Flickable / ListView
// much further per gesture than the platform default, so a touchpad
// two-finger drag or a mouse notch covers real ground. Point `flick` at the
// scrollable and nest it inside:
//
//   ListView { id: list; ...; Kit.WheelBoost { flick: list } }
//
// Three input shapes, one handler:
//   • touchpad / hi-res wheel  → pixelDelta (small, continuous)  → ×touchpadGain
//   • classic mouse wheel      → angleDelta ≥ 120 (one notch)    → lineStep px/notch
//   • touchpad reporting angle → angleDelta < 120 (sub-notch)    → ×touchpadGain
// then everything is multiplied by `wheelScale` (the one knob to turn up if
// it still feels short) and clamped to the flickable's bounds. The event is
// accepted so the target's own wheel handling doesn't also fire and compound
// the movement.
WheelHandler {
  // The Flickable (or ListView, which is one) to scroll. Left null == inert.
  property Flickable flick: null
  // Master multiplier over everything below. Turn this up for more travel.
  property real wheelScale: 1.5
  // Pixels moved per classic mouse-wheel notch (angleDelta == 120), before
  // wheelScale.
  property real lineStep: 90
  // Multiplier on a raw touchpad delta (pixelDelta, or a sub-notch
  // angleDelta), before wheelScale. Touchpad deltas arrive tiny, so this
  // carries most of the amplification.
  property real touchpadGain: 3.5

  enabled: !!flick
  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
  onWheel: function (ev) {
    if (!flick)
      return
    var maxY = Math.max(0, flick.contentHeight - flick.height)
    if (maxY <= 0)
      return

    var dy = 0
    if (ev.pixelDelta.y !== 0) {
      dy = ev.pixelDelta.y * touchpadGain
    } else if (ev.angleDelta.y !== 0) {
      var a = ev.angleDelta.y
      dy = Math.abs(a) >= 120 ? (a / 120) * lineStep   // notched mouse wheel
                              : a * touchpadGain        // touchpad via angleDelta
    } else {
      return
    }
    dy *= wheelScale

    flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - dy))
    ev.accepted = true
  }
}
