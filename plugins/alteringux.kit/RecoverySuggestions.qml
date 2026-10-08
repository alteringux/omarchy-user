import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import "." as Kit
import qs.Commons
import "RecoveryModel.js" as Model

// A passive read-only companion. It never opens a window, grabs focus or
// dispatches a listed shortcut. Deliberate Help uses the existing modal view.
Rectangle {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  property Item owner: null
  property bool shown: false
  property alias localBindings: catalog.localBindings
  readonly property var matches: Model.filter(catalog.records, "", true)
  readonly property bool ready: !catalog.loading
  signal dismissed()
  signal helpRequested()
  parent: owner && owner.Window.window ? owner.Window.window.contentItem : null
  visible: shown && parent && owner && owner.visible && owner.Window.window.visible
  width: Math.max(0, Math.min(380, parent ? parent.width - 16 : 380))
  height: Math.max(0, Math.min(280, parent ? parent.height - 16 : 280))
  z: 100
  color: _webPalette.background
  border.width: 1
  border.color: _webPalette.accent
  radius: Style.cornerRadius
  Accessible.role: Accessible.Pane
  Accessible.name: "Suggested recovery shortcuts"
  readonly property bool anchored: owner !== null && parent !== null
  readonly property point origin: owner && parent ? owner.mapToItem(parent, 0, 0) : Qt.point(0, 0)
  readonly property bool fitsLeft: anchored && origin.x - width - 8 >= 8
  readonly property bool fitsRight: anchored && origin.x + owner.width + width + 8 <= parent.width - 8
  x: anchored && fitsLeft ? origin.x - width - 8 : anchored && fitsRight ? origin.x + owner.width + 8
    : anchored ? Math.max(8, Math.min(parent.width - width - 8, origin.x)) : 0
  y: anchored && (fitsLeft || fitsRight) ? Math.max(8, Math.min(parent.height - height - 8, origin.y))
    : anchored && origin.y + owner.height + height + 8 <= parent.height - 8 ? origin.y + owner.height + 8
    : anchored ? Math.max(8, origin.y - height - 8) : 0

  function refresh() { catalog.refresh() }
  function reveal() {
    shown = true
    if (!catalog.records.length && !catalog.loading && !catalog.error) catalog.refresh()
    const summary = matches.length ? matches.map(function(record) {
      return record.keys + ". " + record.description
    }).join(". ") : catalog.error || (catalog.loading ? "Loading recovery shortcuts." : "No reset or restart shortcuts found.")
    Accessible.announce(summary + " Press F1 to browse help, or Escape to dismiss.")
  }
  RecoveryCatalog { id: catalog }
  // Dismiss this top surface first. Outside clicks must not also reach the
  // panel backdrop; clicks inside the panel keep their original action.
  MouseArea {
    id: dismissSurface
    parent: root.parent
    anchors.fill: parent
    z: root.z - 1
    visible: root.visible
    acceptedButtons: Qt.AllButtons
    property bool outsideOwner: false
    onPressed: function(mouse) {
      const point = root.owner.mapFromItem(dismissSurface, mouse.x, mouse.y)
      outsideOwner = point.x < 0 || point.y < 0 || point.x >= root.owner.width || point.y >= root.owner.height
      if (!outsideOwner) { root.dismissed(); mouse.accepted = false }
    }
    onClicked: if (outsideOwner) root.dismissed()
  }
  // Read-only companion clicks must not reach the outside-click backdrop.
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(8)
    Label {
      text: "Recovery shortcuts · F1: help"
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
      color: _webPalette.foreground
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }
    Label {
      text: catalog.loading ? "Loading shortcuts…" : catalog.error
      visible: catalog.loading || !!catalog.error
      wrapMode: Text.Wrap
      color: _webPalette.foreground
      Layout.fillWidth: true
    }
    Label {
      visible: !catalog.loading && !catalog.error && !root.matches.length
      text: "No reset or restart shortcuts found. Open Help to browse all shortcuts."
      wrapMode: Text.Wrap
      color: _webPalette.foreground
      Layout.fillWidth: true
    }
    ListView {
      id: list
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      model: root.matches
      spacing: Style.space(8)
      keyNavigationEnabled: false
      activeFocusOnTab: false
      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
        visible: size > 0 && size < 1
        enabled: visible
        interactive: visible
      }
      delegate: Item {
        required property var modelData
        width: list.width
        implicitHeight: description.implicitHeight
        Accessible.role: Accessible.ListItem
        Accessible.name: modelData.keys + ". " + modelData.description + ". "
          + modelData.context + (modelData.flags ? ". " + modelData.flags : "")
        Label {
          id: description
          width: parent.width
          text: modelData.keys + " — " + modelData.description + "\n" + modelData.context
            + (modelData.flags ? " · " + modelData.flags : "")
          textFormat: Text.PlainText
          wrapMode: Text.WrapAnywhere
          color: _webPalette.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          Accessible.ignored: true
        }
      }
    }
    Flow {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Button { text: "Help · F1"; focusPolicy: Qt.NoFocus; onClicked: root.helpRequested() }
      Button { text: "Dismiss · Esc"; focusPolicy: Qt.NoFocus; onClicked: root.dismissed() }
    }
  }
}
