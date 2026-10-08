import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

BarWidget {
  id: root
  moduleName: "alteringux.agentglass"
  property alias state: stateStore.value
  property double nowMs: Date.now()
  readonly property string home: Quickshell.env("HOME")
  readonly property string helper: Qt.resolvedUrl("bin/agentglass-omarchy").toString().replace(/^file:\/\//, "")
  readonly property var guard: Kit.BugGuard.create("alteringux.agentglass", function (argv) { Quickshell.execDetached(argv) })
  readonly property var stat: stateStore.loaded ? stateStore.value : Model.emptyState()
  readonly property bool stale: Model.isStale(stat, nowMs)
  readonly property string glyph: "󰚩"

  Kit.Store {
    id: stateStore
    fileName: "agentglass.json"
    watch: true
    pollMs: 10000
    parse: function (raw) { return Model.parseState(raw) }
  }

  Process { id: refreshProc; running: false; command: ["python3", root.helper, "refresh"]; onExited: stateStore.reload() }

  function refresh() {
    guard.run("refresh", function () {
      if (!refreshProc.running) {
        refreshProc.command = ["python3", root.helper, "refresh"]
        if (panelLoader.item && panelLoader.item.opened) refreshProc.command = ["python3", root.helper, "refresh", "--details"]
        refreshProc.running = true
      }
    })
  }
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  Timer { interval: 1000; running: true; repeat: true; onTriggered: root.nowMs = Date.now() }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: { item.hostWidget = root; item.anchorItem = button; item.bar = root.bar }
  }

  IpcHandler {
    target: "alteringux.agentglass"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function status(): string { return JSON.stringify({ counts: root.stat.counts, reachable: root.stat.reachable, stale: root.stale, updatedAt: root.stat.updatedAt }) }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    tooltipText: "Agentglass — click to open workflow cockpit"
    onPressed: function (b) { if (b === Qt.MiddleButton) root.refresh(); else root.toggle() }
  }
}
