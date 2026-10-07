import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
BarWidget {
  id: root; moduleName: "alteringux.skilldashboard"
  readonly property string cli: Quickshell.env("HOME") + "/.config/omarchy/local-bin/omarchy-skilldashboard"
  property alias state: store.value
  Kit.Store { id: store; fileName: "skilldashboard.json"; watch: true; pollMs: 60000; parse: function (raw) { return Model.parse(raw) } }
  Process { id: proc; onExited: store.reload() }
  function run(args) { if (!proc.running) { proc.command = [root.cli].concat(args); proc.running = true } }
  function open() { if (panelLoader.item) panelLoader.item.open() }; function close() { if (panelLoader.item) panelLoader.item.close() }; function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  implicitWidth: button.implicitWidth; implicitHeight: button.implicitHeight
  Component.onCompleted: run(["refresh"])
  Timer { interval: 86400000; repeat: true; running: true; onTriggered: root.run(["refresh"]) }
  Loader { id: panelLoader; active: true; source: Qt.resolvedUrl("Panel.qml"); onLoaded: { item.bar = root.bar; item.anchorItem = button; item.hostWidget = root } }
  IpcHandler { target: "alteringux.skilldashboard"; function open(): void { root.open() }; function close(): void { root.close() }; function toggle(): void { root.toggle() }; function refresh(): void { root.run(["refresh"]) } }
  BarIconButton { id: button; anchors.fill: parent; bar: root.bar; text: "󰘦"; tooltipText: "Skill Dashboard"; onPressed: root.toggle() }
  Kit.AttentionDot { anchors.top: parent.top; anchors.right: parent.right; active: (root.state.summary.actionNeeded || 0) > 0; level: "warning" }
}
