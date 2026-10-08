import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Dashboard bar widget: sits in the bar's center section next to the clock.
// Owns a background refresh timer that shells out to bin/omarchy-dashboard-refresh
// (Hacker News headlines + pending system updates, both free/keyless) and
// writes them to a state file. That same state file can be appended to at
// any time by bin/omarchy-dashboard-note — including from a Claude CLI
// session — which is how the "notes" card gets outside content. Left-click
// opens the card overlay; middle-click forces an immediate refresh.
BarWidget {
  id: root
  moduleName: "alteringux.skilldashboard"

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/alteringux.skilldashboard"
  readonly property string cli: home + "/.config/omarchy/local-bin/omarchy-skilldashboard"

  // dashboard.json lives under ~/.local/state/omarchy/ (NOT in the plugin's own
  // source tree — the shell's plugin-file watcher would reload the widget on
  // every write) and is rewritten by bin/omarchy-dashboard-{refresh,note,track},
  // so the Store watches it for outside changes rather than owning it.
  property alias state: stateStore.value
  property bool refreshing: false
  property bool refreshPending: false

  readonly property bool hasUpdates: (state.summary.actionNeeded || 0) > 0

  Kit.Store {
    id: stateStore
    fileName: "skilldashboard.json"
    watch: true
    // Every bin/ writer (refresh/note/track) replaces the file via
    // mktemp+mv, which swaps the inode FileView's watchChanges is holding —
    // so after the very first external write, the watch goes dead and
    // onFileChanged never fires again without this idle poll. Same
    // watch-on-create blind spot Kit.Store's own header documents.
    pollMs: 60000
    parse: function (raw) { return Model.parse(raw) }
  }

  Process {
    id: refreshProc
    command: [root.cli, "refresh"]
    running: false
    onRunningChanged: root.refreshing = running
    onExited: {
      stateStore.reload()
      if (root.refreshPending) {
        root.refreshPending = false
        Qt.callLater(function() {
          if (!refreshProc.running) root.runRefresh()
        })
      }
    }
  }

  function runRefresh() {
    guard.run("runRefresh", function() {
      if (refreshProc.running) {
        root.refreshPending = true
        return
      }
      refreshProc.running = true
    })
  }

  function runSkillAction(action, skill) {
    guard.run("runSkillAction", function() {
      if (!skill || !skill.id || !skill.owned) return
      skillActionProc.command = [root.cli, "action", action, skill.id, skill.path]
      skillActionProc.running = true
    })
  }

  Process { id: skillActionProc; running: false; onExited: { stateStore.reload(); root.runRefresh() } }

  Timer {
    id: refreshTimer
    interval: 30 * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.runRefresh()
  }

  readonly property var guard: Kit.BugGuard.create("alteringux.skilldashboard", function(argv) { Quickshell.execDetached(argv) })

  Kit.PulseTint {
    id: pulseTint
    pluginId: "alteringux.skilldashboard"
  }

  Component.onCompleted: root.runRefresh()

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

  // The one alteringux.* bar-widget plugin with no IPC surface at all — every
  // sibling (stocks, score, conductor, ...) exposes at least open/close/status
  // for scripting + the other plugins' bottombar host. Mirrors stocks' shape.
  IpcHandler {
    target: "alteringux.skilldashboard"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.runRefresh() }
    function status(): string {
      return guard.call("ipc.status", function() {
        return JSON.stringify({
          refreshing: root.refreshing,
          hasUpdates: root.hasUpdates,
          skills: root.state.skills.length,
          summary: root.state.summary
        })
      }, "{}")
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰘦"
    tooltipText: "Skill Dashboard"

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

    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 2
      active: pulseTint.active
      level: pulseTint.level
    }
  }
}
