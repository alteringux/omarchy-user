import QtQuick
import Quickshell
import Quickshell.Wayland

import "../alteringux.kit" as Kit

// Vertical companion surface for the compact bottom bar. Widgets keep their
// original BarWidget entry points and popup IPC; only their hosting direction
// changes.
Item {
  id: root

  property QtObject _webPalette: Kit.Palette {}
  property string side: "left"
  property int barSize: 35
  property var specs: []
  property var pluginRegistry: null
  property bool barVisible: true
  signal widgetLoaded(string widgetId, bool loaded)
  signal slotAdded(string widgetId, var slot)
  signal slotRemoved(string widgetId, var slot)
  readonly property bool isLeft: side === "left"
  readonly property int sideWidth: 30
  readonly property int expandedWidth: 300
  property bool expanded: false
  // Select with ALTERINGUX_SIDEBAR_LAYOUT=top|centered|distributed.
  readonly property string layoutVariant: {
    var value = String(Quickshell.env("ALTERINGUX_SIDEBAR_LAYOUT") || "distributed").toLowerCase()
    return ["top", "centered", "distributed"].indexOf(value) >= 0 ? value : "centered"
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: win
        required property var modelData
        readonly property bool ownsHostedWidgets: modelData === Quickshell.screens[0]

        screen: modelData
        visible: ownsHostedWidgets && root.barVisible
        implicitWidth: root.expanded ? root.expandedWidth : root.sideWidth
        exclusionMode: ExclusionMode.Auto
        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "alteringux-sidebar-" + root.side
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        BarShim {
          id: sideShim
          position: root.side
          vertical: true
          barSize: root.barSize
        }

        anchors {
          top: true
          bottom: true
          left: root.isLeft
          right: !root.isLeft
        }

        Rectangle {
          anchors.fill: parent
          color: root._webPalette.barBackground

          Rectangle {
            width: 1
            height: parent.height
            x: root.isLeft ? parent.width - width : 0
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: Qt.rgba(root._webPalette.barForeground.r, root._webPalette.barForeground.g, root._webPalette.barForeground.b, 0.12)
          }

          Column {
            anchors { left: parent.left; right: parent.right }
            height: implicitHeight
            spacing: root.layoutVariant === "distributed"
              ? Math.max(10, (parent.height - root.specs.length * root.barSize) / (root.specs.length + 1))
              : 2
            y: root.layoutVariant === "top" ? root.barSize
              : root.layoutVariant === "distributed" ? spacing
              : (parent.height - height) / 2

            Repeater {
              model: root.specs

              delegate: Item {
                id: slot
                required property var modelData
                readonly property bool ownsHostedWidgets: win.ownsHostedWidgets
                readonly property var hostItem: host.item
                width: parent.width
                height: root.barSize
                clip: true
                Component.onCompleted: if (ownsHostedWidgets) root.slotAdded(modelData.id, slot)
                Component.onDestruction: if (ownsHostedWidgets) root.slotRemoved(modelData.id, slot)

                Loader {
                  id: host
                  active: win.ownsHostedWidgets
                  x: root.isLeft ? 0 : parent.width - width * scale
                  y: 0
                  height: parent.height
                  width: Math.max(parent.width, item && item.implicitWidth ? item.implicitWidth : parent.width)
                  scale: width > parent.width ? parent.width / width : 1
                  transformOrigin: Item.TopLeft
                  source: modelData.src

                  onLoaded: {
                    if (item && "bar" in item) item.bar = sideShim
                    root.widgetLoaded(slot.modelData.id, !!item)
                  }
                  onStatusChanged: if (status === Loader.Error) root.widgetLoaded(slot.modelData.id, false)
                }
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: root.expanded = true
            onExited: root.expanded = false
          }
        }
      }
    }
  }
}
