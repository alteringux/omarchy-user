import QtQuick
import "." as Kit
import qs.Commons
import qs.Ui
import "../shared"

// Suite-owned PanelHero API. Titles and meta use the same complete-text
// treatment as body labels; reserved action slots never change on hover.
Item {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  property string glyph: ""
  property Component iconComponent: glyph.length ? glyphIcon : null
  property string title: ""
  property string meta: ""
  property string detail: ""
  property color foreground: _webPalette.foreground
  property string fontFamily: Style.font.family
  property real iconSize: Style.font.display
  property real iconOpacity: 1
  property alias metaOpacity: metaText.opacity
  property Component trailingControl: null
  property bool showHelp: true
  readonly property color dim: _webPalette.muted
  readonly property real trailingInset: actions.width ? actions.width + Style.space(12) : 0
  width: parent ? parent.width : implicitWidth
  height: implicitHeight
  implicitHeight: Math.max(iconLoader.implicitHeight, labels.implicitHeight, actions.implicitHeight)
  function openRecoveryHelp() { help.show() }

  Component {
    id: glyphIcon
    Text {
      text: root.glyph
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
      Accessible.ignored: true
    }
  }
  Loader {
    id: iconLoader
    sourceComponent: root.iconComponent
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    opacity: root.iconOpacity
  }
  Column {
    id: labels
    x: iconLoader.width ? iconLoader.width + Style.space(14) : 0
    width: Math.max(0, root.width - x - root.trailingInset)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)
    Row {
      width: parent.width
      visible: root.title.length > 0 || root.detail.length > 0
      spacing: root.detail.length ? Style.space(8) : 0
      MarqueeText {
        width: Math.max(0, parent.width - (detailPill.visible ? detailPill.width + parent.spacing : 0))
        visible: root.title.length > 0
        text: root.title
        color: root.foreground
        textFont.family: root.fontFamily
        textFont.pixelSize: Style.font.title
        textFont.bold: true
      }
      Rectangle {
        id: detailPill
        visible: root.detail.length > 0
        width: Math.min(implicitWidth, parent.width * 0.45)
        implicitWidth: detailText.implicitWidth + Style.space(10)
        implicitHeight: detailText.implicitHeight + Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        color: "transparent"
        border.width: 1
        border.color: _webPalette.muted
        radius: Style.cornerRadius
        MarqueeText {
          id: detailText
          anchors.centerIn: parent
          width: Math.max(0, parent.width - Style.space(10))
          text: root.detail
          color: root.foreground
          textFont.family: root.fontFamily
          textFont.pixelSize: Style.font.body
          textFont.bold: true
        }
      }
    }
    MarqueeText {
      id: metaText
      width: parent.width
      visible: root.meta.length > 0
      text: root.meta.toUpperCase()
      color: root.dim
      textFont.family: root.fontFamily
      textFont.pixelSize: Style.font.caption
      textFont.bold: true
      textFont.letterSpacing: 1.2
    }
  }
  Row {
    id: actions
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: trailingLoader.width && helpButton.visible ? Style.space(8) : 0
    Loader { id: trailingLoader; sourceComponent: root.trailingControl }
    ActionButton {
      id: helpButton
      anchors.verticalCenter: parent.verticalCenter
      visible: root.showHelp
      text: "Help · F1"
      foreground: root.foreground
      bordered: true
      focusable: true
      Accessible.name: "Recovery shortcuts"
      Accessible.role: Accessible.Button
      Accessible.description: "Show reset and restart shortcuts without running them. F6 switches between panel shortcuts and controls."
      onClicked: root.openRecoveryHelp()
    }
  }
  RecoveryHelp { id: help; returnFocusItem: helpButton }
}
