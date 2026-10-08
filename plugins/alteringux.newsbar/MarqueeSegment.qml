import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "../alteringux.kit" as Kit

// One half of the bottom bar: a Marquee plus the summary card that pops above
// it while a headline is hovered. Factored out of NewsBar.qml so the bar can
// run two independent crawls (world news on the right, Literotica's newest on
// the left) without duplicating the ~100 lines of popup placement each.
//
// The host passes its PanelWindow as `panelWindow` (the popup anchors to it)
// and the already-age-annotated `headlines`; clicks come back as activate(url).
Item {
  property QtObject _webPalette: Kit.Palette {}
  id: seg

  property var panelWindow: null
  property var headlines: []
  property string placeholder: ""
  property bool hostHidden: false

  property color textColor: _webPalette.barForeground
  property color accentColor: _webPalette.barActive
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.body

  signal activate(string url)

  readonly property var hoveredHeadline: crawl.hoveredHeadline

  Marquee {
    id: crawl
    anchors.fill: parent
    headlines: seg.headlines
    paused: segHover.hovered
    textColor: seg.textColor
    accentColor: seg.accentColor
    fontFamily: seg.fontFamily
    fontSize: seg.fontSize
    placeholder: seg.placeholder
    onActivate: function(url) { seg.activate(url) }
  }

  HoverHandler { id: segHover }

  // Summary overlay: while a headline is hovered (scroll paused) a card pops
  // above the bar with its source/sector/age, full title and blurb.
  // Non-interactive and click-through.
  PopupWindow {
    id: summaryTip

    readonly property var h: crawl.hoveredHeadline

    visible: h !== null && !seg.hostHidden && seg.panelWindow !== null
    color: "transparent"
    implicitWidth: seg.panelWindow ? Math.min(seg.panelWindow.width - 48, 520) : 520
    implicitHeight: tipCard.implicitHeight
    mask: Region {}

    anchor {
      window: seg.panelWindow
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top
      gravity: Edges.Top
      rect.width: 1
      rect.height: 1
      onAnchoring: summaryTip.place()
    }

    function place() {
      var it = crawl.hoveredItem
      var win = seg.panelWindow
      if (!it || !win || !win.contentItem) return
      var p = win.contentItem.mapFromItem(it, it.width / 2, 0)
      var x = p.x - summaryTip.implicitWidth / 2
      x = Math.max(8, Math.min(win.width - summaryTip.implicitWidth - 8, x))
      anchor.rect.x = Math.round(x)
      anchor.rect.y = 0
    }

    onVisibleChanged: if (visible) Qt.callLater(place)

    Connections {
      target: crawl
      function onHoveredItemChanged() { if (summaryTip.visible) summaryTip.place() }
    }

    Rectangle {
      id: tipCard
      width: parent ? parent.width : 0
      implicitHeight: tipCol.implicitHeight + 16
      color: _webPalette.popupBackground
      radius: Style.cornerRadius
      border.width: 1
      border.color: _webPalette.popupBorder

      Column {
        id: tipCol
        x: 10
        y: 8
        width: parent.width - 20
        spacing: 3

        Row {
          spacing: 8
          Text {
            text: summaryTip.h ? summaryTip.h.source : ""
            textFormat: Text.PlainText
            color: crawl.accentColor
            font.family: Style.font.family
            font.pixelSize: Math.max(1, Style.font.body - 1)
            font.bold: true
          }
          Text {
            visible: summaryTip.h && !!summaryTip.h.category
            text: summaryTip.h && summaryTip.h.category ? summaryTip.h.category.toUpperCase() : ""
            textFormat: Text.PlainText
            color: summaryTip.h ? crawl.categoryColor(summaryTip.h.categoryBucket) : crawl.dimColor
            font.family: Style.font.family
            font.pixelSize: Math.max(1, Style.font.body - 1)
            font.bold: true
          }
          Text {
            visible: summaryTip.h && !!summaryTip.h.age
            text: summaryTip.h && summaryTip.h.age ? "· " + summaryTip.h.age : ""
            textFormat: Text.PlainText
            color: crawl.dimColor
            font.family: Style.font.family
            font.pixelSize: Math.max(1, Style.font.body - 1)
          }
          Text {
            visible: summaryTip.h && !!summaryTip.h.readTime
            text: summaryTip.h && summaryTip.h.readTime ? "· " + summaryTip.h.readTime : ""
            textFormat: Text.PlainText
            color: crawl.dimColor
            font.family: Style.font.family
            font.pixelSize: Math.max(1, Style.font.body - 1)
          }
        }

        Text {
          width: parent.width
          text: summaryTip.h ? summaryTip.h.title : ""
          textFormat: Text.PlainText
          color: _webPalette.popupText
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: summaryTip.h && !!summaryTip.h.summary
          text: summaryTip.h ? summaryTip.h.summary : ""
          textFormat: Text.PlainText
          color: _webPalette.popupText
          font.family: Style.font.family
          font.pixelSize: Math.max(1, Style.font.body - 1)
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
