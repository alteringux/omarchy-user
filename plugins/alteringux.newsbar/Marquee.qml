import QtQuick
import qs.Commons
import "../alteringux.kit" as Kit

// A continuous right-to-left news crawl. The headline row is laid out twice
// end to end inside a clipped viewport and translated by half its width on an
// infinite linear loop, so the seam is never visible and there is no jump.
// Hovering anywhere on the bar pauses the scroll; each headline is a click
// target that emits activate(url). When there are no headlines a centered
// placeholder is shown and nothing animates.
Item {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  // Age-annotated headline objects: { source, title, url, age }.
  property var headlines: []
  property real pxPerSec: 60
  property color textColor: _webPalette.barForeground
  property color accentColor: _webPalette.barActive
  property color dimColor: _webPalette.contrastColorFor(_webPalette.muted, _webPalette.barBackground)
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

  // Per-sector hues use the shared 216-color RGB cube. categoryColor adjusts
  // each hue for readable text on the active bar surface.
  property var sectorColors: ({
    world: "#6699FF",
    business: "#00CC99",
    politics: "#FF6699",
    tech: "#CC99FF",
    science: "#00CCFF",
    health: "#66CC00",
    sport: "#FFCC00",
    culture: "#FF66CC"
  })

  function categoryColor(bucket) {
    return sectorColors[bucket]
      ? _webPalette.contrastColorFor(sectorColors[bucket], _webPalette.barBackground)
      : dimColor
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
            textFormat: Text.PlainText
            color: root.accentColor
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            font.bold: true
            // Extra breathing room between the source and what follows it.
            rightPadding: Style.space(3)

            verticalAlignment: Text.AlignVCenter
          }
          Text {
            text: cell.modelData.category ? cell.modelData.category.toUpperCase() : ""
            textFormat: Text.PlainText
            visible: !!cell.modelData.category
            color: root.categoryColor(cell.modelData.categoryBucket)
            font.family: root.fontFamily
            font.pixelSize: Math.max(1, root.fontSize - 1)
            font.bold: true
            // Was Style.space(1) — nearly touching the title that follows,
            // out of step with the source label's own Style.space(3) and the
            // bullet's Style.space(4). Matches the rest of the row's rhythm.
            rightPadding: Style.space(4)

            verticalAlignment: Text.AlignVCenter
          }
          Text {
            text: cell.modelData.title
            textFormat: Text.PlainText
            color: hover.hovered ? root.accentColor : root.textColor
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            font.underline: hover.hovered

            verticalAlignment: Text.AlignVCenter
          }
          Text {
            text: cell.modelData.age ? "· " + cell.modelData.age : ""
            textFormat: Text.PlainText
            visible: !!cell.modelData.age
            font.family: root.fontFamily
            font.pixelSize: root.fontSize

            verticalAlignment: Text.AlignVCenter
          }
          // Estimated reading time — ero-news only (world-news headlines have
          // no article body to measure, so this stays blank there).
          Text {
            text: cell.modelData.readTime ? "· " + cell.modelData.readTime : ""
            textFormat: Text.PlainText
            visible: !!cell.modelData.readTime
            color: root.dimColor
            font.family: root.fontFamily
            font.pixelSize: Math.max(1, root.fontSize - 1)

            verticalAlignment: Text.AlignVCenter
          }
          Text {
            text: "•"
            color: root.dimColor
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            leftPadding: Style.space(4)

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
  // headlines, font/DPI change). The tick binding keeps running on its own.
  function restartScroll() {
    track.x = 0
  }

  // A time-stepped crawl at ~30fps rather than a per-frame NumberAnimation.
  // The top bar is otherwise idle, so a 60fps translate here was the single
  // thing keeping that surface's render loop from ever parking; 30fps is
  // indistinguishable for a linear text scroll and halves the repaints. A
  // hover-pause (or no headlines) stops the tick entirely, so a static ticker
  // costs nothing.
  Timer {
    id: scrollTick
    interval: 33
    repeat: true
    running: root.hasHeadlines && track.halfWidth > 1 && !root.paused
    onTriggered: {
      track.x -= root.pxPerSec * (interval / 1000)
      if (track.x <= -track.halfWidth) track.x += track.halfWidth
    }
  }

  // A content swap (source switch, or the first crawl landing) crossfades
  // instead of snapping. The crawl dims out, restartScroll rebuilds the track
  // at x=0, then it fades back up, so the ~1-frame rebuild and the scroll-
  // position reset read as a soft dissolve rather than a jump.
  SequentialAnimation {
    id: swapAnim
    NumberAnimation {
      target: track; property: "opacity"; to: 0
      duration: 110; easing.type: Easing.OutQuad
    }
    ScriptAction { script: root.restartScroll() }
    NumberAnimation {
      target: track; property: "opacity"; to: 1
      duration: 170; easing.type: Easing.InQuad
    }
  }

  onHeadlinesChanged: Qt.callLater(swapAnim.restart)
  Component.onCompleted: Qt.callLater(restartScroll)
}
