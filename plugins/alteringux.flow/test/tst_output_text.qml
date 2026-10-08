import QtQuick
import QtTest
import ".." as Flow
import "../Model.js" as Model

TestCase {
  id: testCase
  name: "FlowOutputText"
  when: windowShown
  visible: true
  width: 360
  height: 100

  readonly property string message:
    ("Long generated log output that must travel across the visible card. ").repeat(2)
    + "FULLCONTENTMARKER"
  Flow.FlowOutputText {
    id: output
    x: 16
    y: 16
    width: 180
    height: 28
    sourceText: Model.renderEnvelopeText({ shape: "log", data: [testCase.message] })
    outputColor: "white"
    outputFontFamily: "monospace"
    outputFontSize: 16
  }

  Rectangle {
    id: outsideTarget
    x: 240
    y: 55
    width: 30
    height: 24
    color: "transparent"
  }

  function findRenderedLabel(item) {
    for (let i = 0; i < item.children.length; i++) {
      const child = item.children[i]
      if (child.visible && typeof child.elide !== "undefined") return child
    }
    return null
  }

  function test_logOutputMovesOnHoverAndKeepsFullText() {
    verify(output.hasOverflow || output.contentWidth > output.width,
      "long log fixture must exceed the card width")
    compare(output.text, testCase.message)

    mouseMove(outsideTarget, 10, 10)
    mouseMove(output, output.width / 2, output.height / 2)
    tryCompare(output, "scrolling", true)
    compare(output.readableText, testCase.message)
    const label = findRenderedLabel(output)
    verify(label !== null, "production output marquee label was not found")
    wait(1000)
    verify(Math.abs(label.x) > 0.5, "hovered Flow output did not move")

    mouseMove(outsideTarget, 10, 10)
    tryCompare(output, "scrolling", false)
    compare(label.x, 0)
  }
}
