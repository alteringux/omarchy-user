import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

import "../alteringux.kit" as Kit

// Second horizontal row, stacked beneath the shell's main top bar.
Item {
  id: root

  property QtObject palette: Kit.Palette {}
  property int barSize: 35
  property bool barVisible: true
  property var specs: []
  property var host: null
  signal widgetLoaded(string widgetId, bool loaded)
  signal slotAdded(string widgetId, var slot)
  signal slotRemoved(string widgetId, var slot)

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: win
        required property var modelData
        readonly property bool ownsHostedWidgets: modelData === Quickshell.screens[0]

        screen: modelData
        visible: root.barVisible
        implicitHeight: root.barSize
        anchors { top: true; left: true; right: true }
        exclusionMode: ExclusionMode.Auto
        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "alteringux-overflow-topbar"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        BarShim {
          id: topShim
          position: "top"
          barSize: root.barSize
          popupExtraGap: root.barSize
        }

        Rectangle {
          anchors.fill: parent
          color: root.palette.barBackground

          Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Qt.rgba(root.palette.barForeground.r, root.palette.barForeground.g,
                           root.palette.barForeground.b, 0.12)
          }

          Row {
            anchors.centerIn: parent
            height: root.barSize
            spacing: 0

            Repeater {
              model: root.specs

              delegate: Item {
                id: slot
                required property var modelData
                readonly property bool ownsHostedWidgets: win.ownsHostedWidgets
                readonly property var hostItem: loader.item
                readonly property bool failed: loader.status === Loader.Error
                height: root.barSize
                width: failed ? root.barSize
                  : Math.floor(root.host.slotWidth(slot) * root.host.overflowScale(win.width))
                clip: true

                Component.onCompleted: if (ownsHostedWidgets) root.slotAdded(modelData.id, slot)
                Component.onDestruction: if (ownsHostedWidgets) root.slotRemoved(modelData.id, slot)

                Loader {
                  id: loader
                  active: win.ownsHostedWidgets
                  anchors.fill: parent
                  source: slot.modelData.src
                  onLoaded: {
                    if (item && "bar" in item) item.bar = topShim
                    root.widgetLoaded(slot.modelData.id, !!item)
                  }
                  onStatusChanged: if (status === Loader.Error) root.widgetLoaded(slot.modelData.id, false)
                }

                Text {
                  visible: slot.failed
                  anchors.centerIn: parent
                  text: "!"
                  color: root.palette.barNegative
                  font.family: Style.font.family
                  font.bold: true
                }
              }
            }
          }
        }
      }
    }
  }
}
