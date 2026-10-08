import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.agentglass"
  ipcTarget: "alteringux.agentglass"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  property string actionError: ""
  property int launchKindIndex: 0
  property string launchName: "omarchy-" + Date.now().toString(36)
  property string launchCwd: Quickshell.env("HOME")
  property string launchPrompt: ""
  property string runName: "workflow-" + Date.now().toString(36)
  property string runCwd: Quickshell.env("HOME")
  property string runCommand: ""
  property string runMemoryHigh: ""
  property string runPriority: "background"
  property string stoppingUnit: ""
  readonly property var stat: hostWidget ? hostWidget.stat : Model.emptyState()
  readonly property var launchKinds: Array.isArray(stat.agentKinds) ? stat.agentKinds : []
  readonly property var launchKind: launchKinds.length ? launchKinds[launchKindIndex % launchKinds.length] : null
  readonly property bool stale: hostWidget ? hostWidget.stale : true
  readonly property string workspaceLabel: !stat.workspace ? "Whole machine" : stat.workspace === Quickshell.env("HOME") ? "~" : stat.workspace
  readonly property var guard: Kit.BugGuard.create("alteringux.agentglass", function (argv) { Quickshell.execDetached(argv) })

  function open() { controller.show(); refresh() }
  function close() { controller.hide() }
  function toggle() { opened ? close() : open() }
  function refresh() { if (hostWidget) hostWidget.refresh() }
  function launch() { guard.run("launch", function () { Quickshell.execDetached(["agentglass"]) }) }
  function nextLaunchKind() { if (launchKinds.length > 1) launchKindIndex = (launchKindIndex + 1) % launchKinds.length }
  function nextRunPriority() { runPriority = runPriority === "background" ? "normal" : "background" }
  function startManagedRun() {
    runProc.command = ["python3", hostWidget.helper, "run", runName.trim(), runCwd.trim(), runPriority, runMemoryHigh.trim()]
    runProc.running = true
  }
  function stopManagedRun(unit) {
    stoppingUnit = unit
    stopRunProc.command = ["python3", hostWidget.helper, "run-stop", unit]
    stopRunProc.running = true
  }

  Process {
    id: homeProc
    running: false
    command: []
    onStarted: root.actionError = ""
    stderr: StdioCollector {
      onStreamFinished: {
        const error = text.trim().slice(0, 180)
        if (error.length) root.actionError = error
      }
    }
    onExited: function (code) {
      if (code !== 0 && !root.actionError) root.actionError = "Workspace action failed or status unavailable"
      root.refresh()
    }
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(520)))

    Kit.PanelKeys {
      id: panelKeys
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.refresh()
      blocked: nameField.activeFocus || cwdField.activeFocus || promptField.activeFocus || runNameField.activeFocus || runCwdField.activeFocus || runCommandField.activeFocus || runMemoryField.activeFocus
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Refresh workflow state", context: "Agentglass · shortcut focus" }
      ]

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: content.implicitHeight

        Column {
          id: content
          width: parent.width
          spacing: Style.spacing.panelGap

          Kit.PanelHead {
            width: parent.width
            glyph: "󰚩"
            title: "Agentglass"
            meta: root.stale ? "STALE" : root.workspaceLabel + " · " + Model.ageLabel(root.stat.updatedAt, hostWidget ? hostWidget.nowMs : Date.now())
            foreground: root.barForeground
            trailingControl: Component {
              Kit.ActionButton {
                text: "Refresh"
                foreground: root.barForeground
                bordered: true
                onClicked: root.refresh()
              }
            }
          }

          Text {
            width: parent.width
            text: root.stale ? (root.stat.error || "Status refresh overdue") : "Observed workflows · scanner " + (root.stat.scanning ? "on" : "off")
            color: root.stat.reachable ? root.barForeground : root._webPalette.negative
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Row {
            width: parent.width
            spacing: Style.space(18)
            Repeater {
              model: [
                { label: "WORKING", value: root.stat.counts.working },
                { label: "ATTENTION", value: root.stat.counts.waiting },
                { label: "PROJECTS", value: root.stat.projectCount }
              ]
              delegate: Column {
                required property var modelData
                spacing: Style.space(2)
                Kit.MetaText { content: modelData.label; foreground: root.barForeground }
                Text { text: modelData.value; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: true }
              }
            }
          }

          Kit.ActionButton {
            width: parent.width
            text: "Open cockpit"
            foreground: root.barForeground
            bordered: true
            onClicked: root.launch()
          }

          Kit.MetaText { content: "LAUNCH AGENT"; foreground: root.barForeground }
          TextField {
            id: nameField
            width: parent.width
            text: root.launchName
            placeholderText: "Agent name"
            foreground: root.barForeground
            Accessible.name: "Agent name"
            onTextEdited: root.launchName = text
          }
          TextField {
            id: cwdField
            width: parent.width
            text: root.launchCwd
            placeholderText: "Working directory"
            foreground: root.barForeground
            Accessible.name: "Agent working directory"
            onTextEdited: root.launchCwd = text
          }
          TextField {
            id: promptField
            width: parent.width
            placeholderText: "First instruction (optional)"
            foreground: root.barForeground
            maximumLength: 4096
            Accessible.name: "Optional first instruction"
            onTextEdited: root.launchPrompt = text
          }
          Row {
            width: parent.width
            spacing: Style.space(8)
            Kit.ActionButton {
              text: root.launchKind ? root.launchKind.title : (root.stat.agentKindsError || "No installed agent CLIs")
              foreground: root.barForeground
              bordered: true
              enabled: root.launchKinds.length > 1 && !startProc.running
              onClicked: root.nextLaunchKind()
            }
            Kit.ActionButton {
              text: startProc.running ? "Starting…" : "Start agent"
              foreground: root.barForeground
              bordered: true
              enabled: !!root.launchKind && root.launchName.trim().length > 0 && root.launchCwd.trim().length > 0 && !startProc.running
              onClicked: {
                startProc.command = ["python3", hostWidget.helper, "start", root.launchName.trim(), root.launchCwd.trim(), root.launchKind.id]
                startProc.running = true
              }
            }
          }
          Kit.MetaText {
            content: "Default permissions; instruction travels via stdin, not process arguments"
            foreground: root._webPalette.faint
          }

          Kit.MetaText { content: "MANAGED WORKFLOW · direct argv, no shell"; foreground: root.barForeground }
          TextField {
            id: runNameField
            width: parent.width
            text: root.runName
            placeholderText: "Workflow name"
            foreground: root.barForeground
            Accessible.name: "Managed workflow name"
            onTextEdited: root.runName = text
          }
          TextField {
            id: runCwdField
            width: parent.width
            text: root.runCwd
            placeholderText: "Working directory"
            foreground: root.barForeground
            Accessible.name: "Managed workflow working directory"
            onTextEdited: root.runCwd = text
          }
          TextField {
            id: runCommandField
            width: parent.width
            placeholderText: "Command and arguments, e.g. make -j2"
            foreground: root.barForeground
            maximumLength: 4096
            Accessible.name: "Managed workflow command"
            onTextEdited: root.runCommand = text
          }
          Row {
            width: parent.width
            spacing: Style.space(8)
            TextField {
              id: runMemoryField
              width: parent.width * 0.43
              placeholderText: "MemoryHigh (optional)"
              foreground: root.barForeground
              maximumLength: 8
              Accessible.name: "Optional soft memory threshold"
              onTextEdited: root.runMemoryHigh = text
            }
            Kit.ActionButton {
              text: "CPU " + root.runPriority
              foreground: root.barForeground
              bordered: true
              enabled: !runProc.running
              onClicked: root.nextRunPriority()
            }
            Kit.ActionButton {
              text: runProc.running ? "Starting…" : "Run"
              foreground: root.barForeground
              bordered: true
              enabled: !!root.runName.trim() && !!root.runCwd.trim() && !!root.runCommand.trim() && !runProc.running
              onClicked: root.startManagedRun()
            }
          }
          Kit.MetaText {
            content: "Commands run as you; CPU weight is relative. MemoryHigh is soft; no hard memory cap is set."
            foreground: root._webPalette.faint
          }

          Text {
            width: parent.width
            readonly property var machine: root.stat.resources ? root.stat.resources.machine : null
            text: machine ? "CPU " + (machine.cpu === null ? "sampling" : Number(machine.cpu).toFixed(1) + "%") + " · RAM " + (Number(machine.memUsed) / 1073741824).toFixed(1) + "/" + (Number(machine.memTotal) / 1073741824).toFixed(1) + " GiB" : "Machine capacity unavailable"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Kit.MetaText {
            content: root.stat.spend && root.stat.spend.cost_usd !== null ? "Recorded spend · 24h · $" + Number(root.stat.spend.cost_usd).toFixed(4) : "Recorded spend unavailable"
            foreground: root.barForeground
          }

            Repeater {
              model: root.stat.resources ? root.stat.resources.procs : []
              delegate: Kit.MetaText {
                required property var modelData
                width: parent.width
                content: Model.resourceLabel(modelData) + " · " + Model.pathLabel(modelData.cwd, hostWidget.home)
                foreground: root.barForeground
              }
            }

          Kit.MetaText {
            content: "Process working directory is context, not verified workflow ownership"
            foreground: root._webPalette.faint
          }

          Kit.MetaText {
            visible: root.stat.resources && root.stat.resources.omitted > 0
            content: root.stat.resources ? "+" + root.stat.resources.omitted + " more processes not shown" : ""
            foreground: root._webPalette.faint
          }

          Kit.MetaText {
            content: root.stat.services
              ? "LISTENERS · " + root.stat.services.listening + " total · " + root.stat.services.mine + " this user · " + root.stat.services.external + " external"
              : root.stat.servicesError || "Listener inventory unavailable"
            foreground: root.barForeground
          }

          Repeater {
            model: root.stat.services ? root.stat.services.services : []
            delegate: Column {
              required property var modelData
              width: parent.width
              Kit.MetaText {
                width: parent.width
                content: Model.serviceLabel(modelData)
                foreground: root.barForeground
              }
              Kit.MetaText {
                width: parent.width
                content: Model.pathLabel(modelData.cwd, hostWidget.home)
                foreground: root._webPalette.faint
              }
            }
          }

          Kit.MetaText {
            visible: root.stat.services && root.stat.services.omitted > 0
            content: root.stat.services ? "+" + root.stat.services.omitted + " more listeners not shown; CLI supports --limit 24" : ""
            foreground: root._webPalette.faint
          }

          Kit.MetaText {
            visible: !!root.stat.servicesError
            content: root.stat.servicesError
            foreground: root._webPalette.negative
          }

          Kit.MetaText {
            content: root.stat.services && root.stat.services.userServices
              ? "USER SYSTEMD · " + root.stat.services.userServices.total + " total · " + root.stat.services.userServices.running + " running · " + root.stat.services.userServices.failed + " failed"
              : "User service inventory unavailable"
            foreground: root.barForeground
          }

          Repeater {
            model: root.stat.services && root.stat.services.userServices ? root.stat.services.userServices.units : []
            delegate: Kit.MetaText {
              required property var modelData
              width: parent.width
              content: Model.userServiceLabel(modelData)
              foreground: root.barForeground
            }
          }

          Kit.MetaText {
            visible: root.stat.services && root.stat.services.userServices && root.stat.services.userServices.omitted > 0
            content: root.stat.services && root.stat.services.userServices
              ? "+" + root.stat.services.userServices.omitted + " more user services not shown" : ""
            foreground: root._webPalette.faint
          }

          Kit.MetaText {
            visible: root.stat.services && root.stat.services.userServices && root.stat.services.userServices.error
            content: root.stat.services && root.stat.services.userServices ? root.stat.services.userServices.error : ""
            foreground: root._webPalette.negative
          }

          Kit.MetaText {
            content: "MANAGED RUNS · " + root.stat.managedRuns.length +
              (root.stat.managedRunsOmitted ? " +" + root.stat.managedRunsOmitted + " more" : "") + " · per-unit cgroup accounting"
            foreground: root.barForeground
          }
          Repeater {
            model: root.stat.managedRuns
            delegate: Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)
              Kit.MetaText {
                width: parent.width - Style.space(72)
                content: Model.managedRunLabel(modelData)
                foreground: root.barForeground
              }
              Kit.ActionButton {
                text: root.stoppingUnit === modelData.unit && stopRunProc.running ? "Stopping…"
                  : modelData.sub === "exited" || modelData.active === "failed" ? "Clear" : "Stop"
                foreground: root.barForeground
                bordered: true
                enabled: (modelData.active === "active" || modelData.active === "failed") && !stopRunProc.running
                onClicked: root.stopManagedRun(modelData.unit)
              }
            }
          }
          Kit.MetaText {
            visible: !!root.stat.managedRunsError
            content: root.stat.managedRunsError
            foreground: root._webPalette.negative
          }

          Kit.ActionButton {
            width: parent.width
            text: "Set up ~ + connect installed agents"
            foreground: root.barForeground
            bordered: true
            enabled: hostWidget !== null && !homeProc.running
            onClicked: {
              homeProc.command = ["python3", hostWidget.helper, "setup"]
              homeProc.running = true
            }
          }

          Text {
            width: parent.width
            visible: root.actionError.length > 0
            text: root.actionError
            color: root._webPalette.negative
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Column {
            width: parent.width
            spacing: Style.space(8)
          Repeater {
            model: root.stat.agents
            delegate: Column {
                required property var modelData
                width: parent.width
                spacing: Style.space(2)
                Text { width: parent.width; text: modelData.name || "agent"; color: root.barForeground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight }
                Text { width: parent.width; text: (modelData.attention || modelData.state || "unknown") + " · " + (modelData.project || "unknown project"); color: root._webPalette.faint; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                Kit.ActionButton {
                  visible: !!modelData.attention && !!modelData.paneId
                  enabled: !focusProc.running
                  text: "Open waiting session"
                  foreground: root.barForeground
                  bordered: true
                  onClicked: {
                    focusProc.command = ["python3", hostWidget.helper, "focus", modelData.name, modelData.paneId]
                    focusProc.running = true
                  }
                }
              }
            }
            Kit.EmptyState { visible: root.stat.agents.length === 0; text: root.stat.reachable ? "No observed agents" : "Start agentglass to see workflows"; hint: "Scope does not prove telemetry coverage"; foreground: root.barForeground }
          }
        }
      }
    }
  }

  Process {
    id: focusProc
    running: false
    command: []
    onStarted: root.actionError = ""
    stderr: StdioCollector {
      onStreamFinished: {
        const error = text.trim().slice(0, 180)
        if (error.length) root.actionError = error
      }
    }
    onExited: function (code) {
      if (code !== 0 && !root.actionError) root.actionError = "That session is no longer available"
      root.refresh()
    }
  }

  Process {
    id: startProc
    running: false
    stdinEnabled: true
    command: []
    onStarted: {
      root.actionError = ""
      write(JSON.stringify(root.launchPrompt) + "\n")
    }
    stderr: StdioCollector {
      onStreamFinished: {
        const error = text.trim().slice(0, 180)
        if (error.length) root.actionError = error
      }
    }
    onExited: function (code) {
      if (code !== 0 && !root.actionError) root.actionError = "Agent could not be started"
    }
  }

  Process {
    id: runProc
    running: false
    stdinEnabled: true
    command: []
    onStarted: {
      root.actionError = ""
      write(JSON.stringify({ command: root.runCommand }) + "\n")
    }
    stderr: StdioCollector {
      onStreamFinished: {
        const error = text.trim().slice(0, 180)
        if (error.length) root.actionError = error
      }
    }
    onExited: function (code) {
      if (code !== 0 && !root.actionError) root.actionError = "Managed workflow could not be started"
      root.refresh()
    }
  }

  Process {
    id: stopRunProc
    running: false
    command: []
    onStarted: root.actionError = ""
    stderr: StdioCollector {
      onStreamFinished: {
        const error = text.trim().slice(0, 180)
        if (error.length) root.actionError = error
      }
    }
    onExited: function (code) {
      if (code !== 0 && !root.actionError) root.actionError = "Managed workflow could not be stopped"
      root.stoppingUnit = ""
      root.refresh()
    }
  }
}
