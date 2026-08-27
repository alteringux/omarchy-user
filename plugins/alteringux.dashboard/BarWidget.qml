import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Dashboard bar widget: sits in the bar's center section next to the clock.
// Owns a background refresh timer that shells out to bin/omarchy-dashboard-refresh
// (Hacker News headlines + pending system updates, both free/keyless) and
// writes them to a state file. That same state file can be appended to at
// any time by bin/omarchy-dashboard-note — including from a Claude CLI
// session — which is how the "notes" card gets outside content. Left-click
// opens the card overlay; middle-click forces an immediate refresh.
BarWidget {
  id: root
  moduleName: "alteringux.dashboard"

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/alteringux.dashboard"
  readonly property string refreshScript: pluginDir + "/bin/omarchy-dashboard-refresh"
  // Deliberately NOT inside the plugin's own source directory: that tree is
  // watched by the shell's plugin-file watcher, and this file is rewritten
  // repeatedly by the refresh/note scripts. Writing it there would trigger
  // a "local plugin changed" reload every refresh, tearing down an open
  // panel. Keep it under ~/.local/state/omarchy/ instead (same convention
  // alteringux.pomodoro uses).
  readonly property string stateDir: home + "/.local/state/omarchy/"
  readonly property string statePath: stateDir + "dashboard.json"

  property var state: Model.defaultState()
  property bool refreshing: false

  readonly property bool hasUpdates: state.system.items.length > 0

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.state = Model.parseState(text())
    onLoadFailed: root.state = Model.defaultState()
    onFileChanged: reload()
  }

  Process {
    id: ensureDirsProc
    command: ["mkdir", "-p", root.stateDir]
    running: false
  }

  Process {
    id: refreshProc
    command: ["bash", root.refreshScript]
    running: false
    onRunningChanged: root.refreshing = running
    onExited: stateFile.reload()
  }

  function runRefresh() {
    if (refreshProc.running) return
    refreshProc.running = true
  }

  Timer {
    id: refreshTimer
    interval: 30 * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.runRefresh()
  }

  Component.onCompleted: {
    ensureDirsProc.running = true
    Qt.callLater(function() {
      stateFile.reload()
      root.runRefresh()
    })
  }

  // ---- Popup panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "🗞️"
    tooltipText: "Dashboard"

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.runRefresh()
      else root.togglePanel()
    }

    Rectangle {
      visible: root.hasUpdates
      width: Style.space(6)
      height: Style.space(6)
      radius: width / 2
      color: Color.urgent
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.space(3)
      anchors.rightMargin: Style.space(3)
    }
  }
}
