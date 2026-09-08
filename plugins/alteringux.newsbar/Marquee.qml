import QtQuick
import qs.Commons

// A continuous right-to-left news crawl. The headline row is laid out twice
// end to end inside a clipped viewport and translated by half its width on an
// infinite linear loop, so the seam is never visible and there is no jump.
// Hovering anywhere on the bar pauses the scroll; each headline is a click
// target that emits activate(url). When there are no headlines a centered
// placeholder is shown and nothing animates.
Item {
  id: root

  // Age-annotated headline objects: { source, title, url, age }.
  property var headlines: []
  property real pxPerSec: 60
  property color textColor: Color.bar.text
  property color accentColor: Color.bar.active
  property color dimColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.55)
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.body
  property string placeholder: ""
  property bool paused: false

  // The headline the pointer is currently over, and the on-screen cell for it
  // (used by the host window to anchor a summary popup). Null when nothing is
  // hovered. Scrolling is paused while hovered, so the cell stays put.
  property var hoveredHeadline: null
  property Item hoveredItem: null

  signal activate(string url)

  // Fixed per-sector hues — distinct from each other and from the source
  // colour, and legible on the dark bar regardless of theme. "other" and any
  // unknown bucket fall back to the dim colour.
  property var sectorColors: ({
    world: "#6ea8fe",
    business: "#4ec9a5",
    politics: "#e0637a",
    tech: "#b48ead",
    science: "#56c2d6",
    health: "#8fbf6b",
    sport: "#e6a95b",
    culture: "#d98fc0"
  })

  function categoryColor(bucket) {
    return sectorColors[bucket] || dimColor
  }

  clip: true

  readonly property bool hasHeadlines: Array.isArray(headlines) && headlines.length > 0

  // Headlines laid out twice so the second copy fills the gap the first
  // leaves as it scrolls off the left edge.
  readonly property var doubledModel: hasHeadlines ? headlines.concat(headlines) : []

  Text {
    id: placeholderLabel
    anchors.centerIn: parent
    visible: !root.hasHeadlines
    text: root.placeholder
    color: root.dimColor
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    renderType: Text.NativeRendering
  }

  Row {
    id: track
    height: parent.height
    visible: root.hasHeadlines
    spacing: 0
    // Half the row is one full pass of every headline.
    readonly property real halfWidth: width / 2

    Repeater {
      model: root.doubledModel

      delegate: Item {
        id: cell
        required property var modelData
        required property int index
        height: track.height
        width: cellRow.implicitWidth + Style.space(10)

        Row {
          id: cellRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)

          Text {
            text: cell.modelData.source
            color: root.accentColor
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            font.bold: true
            // Extra breathing room between the source and what follows it.
            rightPadding: Style.space(3)
            renderType: Text.NativeRendering
            verticalAlignment: Text.AlignVCenter
          }
          Text {
            visible: !!cell.modelData.category
            text: cell.modelData.category ? cell.modelData.category.toUpperCase() : ""
            color: root.categoryColor(cell.modelData.categoryBucket)
            font.family: root.fontFamily
            font.pixelSize: Math.max(1, root.fontSize - 1)
            font.bold: true
            // Was Style.space(1) — nearly touching the title that follows,
            // out of step with the source label's own Style.space(3) and the
            // bullet's Style.space(4). Matches the rest of the row's rhythm.
            rightPadding: Style.space(4)
            renderType: Text.NativeRendering
            verticalAlignment: Text.AlignVCenter
          }
          Text {
            text: cell.modelData.title
            color: hover.hovered ? root.accentColor : root.textColor
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            font.underline: hover.hovered
            renderType: Text.NativeRendering
            verticalAlignment: Text.AlignVCenter
          }
          Text {
            visible: !!cell.modelData.age
            text: cell.modelData.age ? "· " + cell.modelData.age : ""
            color: root.dimColor
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            renderType: Text.NativeRendering
            verticalAlignment: Text.AlignVCenter
          }
          Text {
            text: "•"
            color: root.dimColor
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            leftPadding: Style.space(4)
            renderType: Text.NativeRendering
            verticalAlignment: Text.AlignVCenter
          }
        }

        // hovered drives the title highlight; cursorShape makes the whole
        // headline read as clickable; and it publishes the hovered headline so
        // the host window can pop a summary over the bar.
        HoverHandler {
          id: hover
          cursorShape: Qt.PointingHandCursor
          onHoveredChanged: {
            if (hovered) {
              root.hoveredHeadline = cell.modelData
              root.hoveredItem = cell
            } else if (root.hoveredItem === cell) {
              root.hoveredHeadline = null
              root.hoveredItem = null
            }
          }
        }

        TapHandler {
          acceptedButtons: Qt.LeftButton
          onTapped: {
            var url = String(cell.modelData.url || "")
            if (url) root.activate(url)
          }
        }
      }
    }

    onWidthChanged: root.restartScroll()
  }

  // Restart from a clean origin whenever the content width changes (new
  // headlines, font/DPI change). Without this the running animation keeps its
  // stale from/to and the crawl speed drifts or the seam gaps.
  function restartScroll() {
    scrollAnim.stop()
    track.x = 0
    if (root.hasHeadlines && track.halfWidth > 1)
      scrollAnim.start()
  }

  NumberAnimation {
    id: scrollAnim
    target: track
    property: "x"
    from: 0
    to: -track.halfWidth
    duration: Math.max(1, Math.round(track.halfWidth / Math.max(1, root.pxPerSec) * 1000))
    loops: Animation.Infinite
    easing.type: Easing.Linear
    paused: root.paused && running
  }

  onHeadlinesChanged: Qt.callLater(restartScroll)
  Component.onCompleted: Qt.callLater(restartScroll)
}
