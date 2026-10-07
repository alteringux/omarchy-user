import QtQuick
import Quickshell.Io
import "RecoveryModel.js" as Model

Item {
  id: root
  visible: false
  property var localBindings: []
  property var rawGlobalBindings: []
  property var globalRecords: []
  property var auditReport: Model.audit(rawGlobalBindings)
  readonly property var records: Model.localRecords(localBindings).concat(globalRecords)
  property string error: ""
  property bool loading: false

  function refresh() {
    if (request.running) return
    rawGlobalBindings = []
    globalRecords = []
    error = ""
    loading = true
    deadline.restart()
    request.running = true
  }

  Timer {
    id: deadline
    interval: 5000
    onTriggered: {
      request.running = false
      root.loading = false
      root.error = "Shortcuts could not be loaded. Try again."
    }
  }

  Process {
    id: request
    command: ["hyprctl", "-j", "binds"]
    stdout: StdioCollector { id: output }
    onExited: function(code) {
      deadline.stop()
      root.loading = false
      if (code !== 0) {
        root.error = "Shortcuts could not be loaded. Try again."
        return
      }
      try {
        const bindings = JSON.parse(output.text)
        if (!Array.isArray(bindings)) throw new Error("Invalid binding catalog")
        root.rawGlobalBindings = bindings
        root.globalRecords = Model.normalize(bindings)
      }
      catch (_) { root.error = "Shortcuts could not be loaded. Try again." }
    }
  }
}
