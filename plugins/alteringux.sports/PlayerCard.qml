import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit
// Player row: name, position, squad number — click to expand the detail
// block (height, weight, born, nationality, blurb).
Rectangle {
  id: root

  required property var player
  property color barForeground: Color.foreground
  property color accentColor: Color.accent

  readonly property bool expanded: detailItem.visible

  Layout.preferredHeight: col.implicitHeight + Style.space(12)
  radius: Style.cornerRadius
  clip: true
  color: Util.alpha(root.barForeground, 0.05)
  border.width: 1
  border.color: Util.alpha(root.barForeground, 0.14)

  function toggle() { detailItem.visible = !detailItem.visible }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggle()
  }

  Column {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(6)
    spacing: Style.space(2)

    Row {
      width: parent.width
      spacing: Style.space(6)

      Image {
        source: root.player && root.player.thumb ? root.player.thumb : ""
        visible: source !== ""
        asynchronous: true
        sourceSize.width: Style.space(32)
        sourceSize.height: Style.space(32)
        width: Style.space(32)
        height: Style.space(32)
        fillMode: Image.PreserveAspectFit
      }
      Text {
        visible: !!(root.player && root.player.number)
        text: (root.player && root.player.number) || ""
        color: root.accentColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        text: (root.player && root.player.name) || ""
        width: parent.width - posText.width - parent.spacing * 3
        elide: Text.ElideRight
        color: root.barForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        id: posText
        text: (root.player && root.player.position) || ""
        color: root.barForeground
        opacity: 0.55
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      id: detailItem
      visible: false
      width: parent.width
      spacing: Style.space(1)

      Text {
        visible: root.statSummary() !== ""
        text: root.statSummary()
        color: root.accentColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        visible: !!(root.player && (root.player.height || root.player.weight))
        text: [(root.player && root.player.height) || "", (root.player && root.player.weight) || ""].filter(Boolean).join("  ·  ")
        color: root.barForeground
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text {
        visible: !!(root.player && (root.player.nationality || root.player.born))
        text: [(root.player && root.player.nationality) || "", (root.player && root.player.born) || ""].filter(Boolean).join("  ·  ")
        color: root.barForeground
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text {
        visible: !!(root.player && root.player.description)
        text: {
          var d = (root.player && root.player.description) || ""
          // strip residual html entities and tags from TheSportsDB blurbs
          d = d.replace(/<[^>]+>/g, " ").replace(/&[a-z]+;/gi, " ").replace(/\s+/g, " ").trim()
          return d.length > 220 ? d.slice(0, 220) + "…" : d
        }
        wrapMode: Text.WordWrap
        width: parent.width
        color: Kit.Palette.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  function accentColorFor() {
    return root.accentColor
  }

  function statSummary() {
    var stats = root.player && root.player.stats ? root.player.stats : {}
    var parts = []
    var labels = [
      ["appearances", "apps"], ["goals", "goals"], ["assists", "assists"],
      ["points", "pts"], ["minutes", "min"], ["yellowCards", "yellow"],
      ["redCards", "red"]
    ]
    for (var i = 0; i < labels.length; i++) {
      var value = stats[labels[i][0]]
      if (value !== null && value !== undefined && value !== "")
        parts.push(labels[i][1] + " " + value)
    }
    return parts.join("  ·  ")
  }
}
