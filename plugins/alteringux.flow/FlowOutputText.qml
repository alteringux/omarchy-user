import QtQuick
import "../shared"

// One readable output envelope from the Flow OUTPUT tab. Keeping the text
// contract here makes its wrapping, full source and overflow behavior testable.
MarqueeText {
  id: root
  property string sourceText: ""
  property bool prose: false
  property color outputColor: "white"
  property string outputFontFamily: "monospace"
  property real outputFontSize: 16

  text: sourceText
  requestedTextFormat: Text.PlainText
  requestedWrapMode: prose ? Text.WordWrap : Text.NoWrap
  requestedMaximumLineCount: -1
  requestedElide: Text.ElideRight
  color: outputColor
  textFont.family: outputFontFamily
  textFont.pixelSize: outputFontSize
}
