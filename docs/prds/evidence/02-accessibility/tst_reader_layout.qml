import QtQuick
import QtQuick.Window
import Quickshell
import "../../../../plugins/shared"

ShellRoot {
  id: probe
  property int index: 0
  property var cases: [
    {tag: "narrow-normal", size: 16, viewport: 340},
    {tag: "narrow-double", size: 32, viewport: 340},
    {tag: "wide-double", size: 32, viewport: 640}
  ]
  property var results: []
  Window {
    id: host
    visible: true
    width: 340
    height: 480
    MarqueeText {
      id: field
      width: 100
      height: 40
      text: "Synthetic complete text ".repeat(80)
      textFont.pixelSize: 16
    }
  }
  function next() {
    if (index === cases.length) {
      console.log("READER_LAYOUT_RESULT " + JSON.stringify(results))
      Qt.quit()
      return
    }
    host.width = cases[index].viewport
    field.textFont.pixelSize = cases[index].size
    prepare.restart()
  }
  Timer {
    id: prepare
    interval: 100
    onTriggered: { field.openDetails(); settle.restart() }
  }
  Timer {
    id: settle
    interval: 100
    onTriggered: {
      const data = probe.cases[probe.index]
      const popup = field.detailsView
      const content = popup.contentItem
      const toggle = content.children[2]
      const footer = content.children[3]
      const checks = [
        field.detailsVisible,
        host.width === data.viewport,
        content.width <= popup.width - popup.leftPadding - popup.rightPadding + 1,
        toggle.width <= content.width + 1,
        toggle.contentItem.wrapMode !== Text.NoWrap
          || toggle.contentItem.implicitWidth <= toggle.contentItem.width + 1,
        footer.width <= content.width + 1,
        content.children[1].height > data.size * 2
      ]
      field.closeDetails()
      checks.push(!field.detailsVisible)
      probe.results = probe.results.concat([{
        case: data.tag, viewport: data.viewport, actualOwnerWidth: host.width, fontSize: data.size,
        popupWidth: popup.width, contentWidth: content.width,
        readerHeight: content.children[1].height, checks: checks
      }])
      probe.index++
      Qt.callLater(probe.next)
    }
  }
  Timer {
    interval: 5000
    running: true
    onTriggered: { console.error("READER_LAYOUT_FAIL deadline"); Qt.quit() }
  }
  Component.onCompleted: Qt.callLater(next)
}
