import QtQuick
import qs.Commons

// Single-line label that plays a vertical "split-flap" slide + crossfade
// whenever `text` changes: the outgoing line lifts up and fades while the
// incoming line rises into place. `implicitWidth` eases between values so a
// host bar slot bound to it resizes smoothly instead of snapping.
//
// lineA and lineB swap front/back roles on every transition, so neither
// value is ever overwritten mid-animation. A change that lands while a
// slide is still running fast-forwards it (`slide.complete()`), which fires
// `onStopped` synchronously and flips the roles before the next slide is
// armed. Two plain Text children (no inline component) keep this friendly to
// Quickshell's QML compiler, which disallows outer-id access from inline
// components.
Item {
  id: root

  property string text: ""
  property color color: Color.foreground
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.body
  property int slideDuration: 340

  implicitWidth: Math.max(1, measure.implicitWidth)
  implicitHeight: measure.implicitHeight
  clip: true

  Behavior on implicitWidth {
    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
  }
  Behavior on color {
    ColorAnimation { duration: 220 }
  }

  // Off-screen sizer: always carries the current *target* text, so
  // implicitWidth tracks where we're animating to, not what's still shown.
  Text {
    id: measure
    visible: false
    text: root.text
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    renderType: Text.NativeRendering
  }

  Text {
    id: lineA
    width: root.width
    height: root.height
    anchors.horizontalCenter: parent.horizontalCenter
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    renderType: Text.NativeRendering
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    y: 0
    opacity: 0
  }

  Text {
    id: lineB
    width: root.width
    height: root.height
    anchors.horizontalCenter: parent.horizontalCenter
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    renderType: Text.NativeRendering
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    y: 0
    opacity: 0
  }

  property bool _frontIsA: true
  readonly property Text _front: _frontIsA ? lineA : lineB
  readonly property Text _back: _frontIsA ? lineB : lineA
  property bool _ready: false

  Component.onCompleted: {
    lineA.text = root.text
    lineA.y = 0
    lineA.opacity = 1
    _ready = true
  }

  onTextChanged: {
    if (!_ready || _front.text === root.text)
      return
    if (slide.running)
      slide.complete()
    _back.text = root.text
    _back.y = root.height
    _back.opacity = 0
    slide.restart()
  }

  ParallelAnimation {
    id: slide
    NumberAnimation { target: root._front; property: "y"; to: -root.height; duration: root.slideDuration; easing.type: Easing.InCubic }
    NumberAnimation { target: root._front; property: "opacity"; to: 0; duration: root.slideDuration; easing.type: Easing.OutCubic }
    NumberAnimation { target: root._back; property: "y"; to: 0; duration: root.slideDuration; easing.type: Easing.OutCubic }
    NumberAnimation { target: root._back; property: "opacity"; to: 1; duration: root.slideDuration; easing.type: Easing.InCubic }
    onStopped: root._frontIsA = !root._frontIsA
  }
}
