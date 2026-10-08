import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui

BarWidget {
  id: root
  moduleName: "alteringux.cursortrail"

  property var points: []
  property int sampleMs: 24
  property int lifeMs: 280

  function sample(raw) {
    try {
      var p = JSON.parse(raw)
      var next = root.points.slice()
      next.push({ x: Number(p.x), y: Number(p.y), born: Date.now() })
      while (next.length > 24) next.shift()
      root.points = next
    } catch (e) {}
  }

  Process {
    id: cursorProcess
    command: ["sh", "-lc", "sig=$(hyprctl instances | sed -n 's/^instance \\([^:]*\\):/\\1/p'); HYPRLAND_INSTANCE_SIGNATURE=\"$sig\" hyprctl -j cursorpos | tr -d '\\n'"]
    running: false
    stdout: SplitParser { onRead: function(line) { root.sample(line) } }
  }

  Timer {
    interval: root.sampleMs
    repeat: true
    running: true
    onTriggered: if (!cursorProcess.running) cursorProcess.running = true
  }

  Timer {
    interval: 32
    repeat: true
    running: true
    onTriggered: root.points = root.points.filter(function(p) { return Date.now() - p.born < root.lifeMs })
  }

  Repeater {
    model: Quickshell.screens
    delegate: PanelWindow {
      required property var modelData
      property var targetScreen: modelData
      id: panel
      screen: modelData
      visible: true
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "alteringux-cursor-trail"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      Item {
        anchors.fill: parent
        Repeater {
          model: root.points
          delegate: Rectangle {
            required property var modelData
            readonly property real age: Math.max(0, Date.now() - modelData.born)
            readonly property real fade: Math.max(0, 1 - age / root.lifeMs)
            x: modelData.x - panel.targetScreen.geometry.x - width / 2
            y: modelData.y - panel.targetScreen.geometry.y - height / 2
            width: 5 + fade * 7
            height: width
            radius: width / 2
            opacity: fade * 0.55
            color: "#8be9fd"
          }
        }
      }
    }
  }
}
