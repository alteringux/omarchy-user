import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Headless service: on a timer it cats every *.ics under the configured
// calendar dirs, computes the next event, writes a state file for other
// widgets/CLIs, and fires a single desktop notification a configurable
// number of minutes before that event starts.
//
// Config (all optional): ~/.config/omarchy/agenda.json
//   { "calendarDirs": ["~/.local/share/calendars"], "leadMinutes": 10, "pollSeconds": 60 }
//
// State file: $XDG_RUNTIME_DIR/omarchy-agenda/state  (JSON, see Model.stateJson)
//
// IPC (target "alteringux.agenda"):
//   omarchy-shell ipc call alteringux.agenda next
//   omarchy-shell ipc call alteringux.agenda today
//   omarchy-shell ipc call alteringux.agenda status
//   omarchy-shell ipc call alteringux.agenda refresh
Item {
  id: root

  // Injected by omarchy-shell's first-party service loader.
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string statePath: runtimeDir + "/omarchy-agenda/state"

  // Effective config — Model defaults, overridden by ~/.config/omarchy/agenda.json.
  // The file is user-editable, so the Store watches it (+ a poll for the
  // watch-on-create gap) and these read straight through its parsed value.
  readonly property var config: configStore.value || Model.defaultConfig()
  readonly property var calendarDirs: config.calendarDirs
  readonly property int leadSeconds: config.leadMinutes * 60
  readonly property int pollSeconds: config.pollSeconds

  property var agenda: ({ next: null, today: [], upcoming: [], generatedAt: 0 })

  readonly property var guard: Kit.BugGuard.create("alteringux.agenda", function (argv) { Quickshell.execDetached(argv) })

  Kit.Store {
    id: configStore
    dir: root.home + "/.config/omarchy/"
    fileName: "agenda.json"
    watch: true
    pollMs: 60000   // agenda.json can be created after the shell started
    parse: function (raw) { return Model.parseConfig(raw) }
  }

  // Persisted so a shell reload doesn't re-fire notifications we already sent.
  PersistentProperties {
    id: persisted
    reloadableId: "alteringux-agenda"
    property string notifiedKeys: "[]"
  }

  function expandTilde(p) {
    return (typeof p === "string" && p.indexOf("~") === 0) ? (root.home + p.slice(1)) : p
  }

  function scan() {
    if (scanProc.running) return
    var quoted = root.calendarDirs.map(root.expandTilde).map(function (d) {
      return "'" + String(d).replace(/'/g, "'\\''") + "'"
    }).join(" ")
    // Our own config-derived paths; concatenated .ics on stdout, errors dropped.
    scanProc.command = ["bash", "-lc", "find " + quoted + " -type f -name '*.ics' 2>/dev/null -exec cat {} +"]
    scanProc.running = true
  }

  function ingest(icsText) {
    guard.run("ingest", function () {
      var now = Math.floor(Date.now() / 1000)
      root.agenda = Model.computeAgenda([icsText], now, {})
      writeState(now)

      var known = []
      try { known = JSON.parse(persisted.notifiedKeys || "[]") } catch (e) { known = [] }
      var decision = Model.shouldNotify(root.agenda, now, root.leadSeconds, known)
      persisted.notifiedKeys = JSON.stringify(decision.keys || [])
      if (decision.notify) sendNotification(decision.event)
    })
  }

  function writeState(now) {
    var json = JSON.stringify(Model.stateJson(root.agenda, now))
    var dir = root.statePath.slice(0, root.statePath.lastIndexOf("/"))
    // base64 hop so arbitrary event text can't break out of the shell quoting.
    Quickshell.execDetached(["bash", "-lc",
      "mkdir -p '" + dir + "' && printf %s '" + Qt.btoa(json) + "' | base64 -d > '" + root.statePath + "'"])
  }

  function sendNotification(ev) {
    if (notifyProc.running || !ev) return
    var now = Math.floor(Date.now() / 1000)
    var body = Model.formatRelative(ev.start - now) + " · " + Model.formatClock(ev.start)
    if (ev.location) body += "\n" + ev.location
    notifyProc.command = [
      "notify-send", "-a", "Agenda", "-u", "normal", "-i", "x-office-calendar",
      "-h", "string:x-canonical-private-synchronous:agenda",
      ev.summary || "Upcoming event", body
    ]
    notifyProc.running = true
  }

  Process { id: notifyProc }

  Process {
    id: scanProc
    stdout: StdioCollector {
      id: scanOut
      waitForEnd: true
      onStreamFinished: root.ingest(scanOut.text)
    }
  }

  Timer {
    interval: Math.max(15, root.pollSeconds) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.scan()
  }

  IpcHandler {
    target: "alteringux.agenda"

    function refresh(): void { root.scan() }

    function next(): string {
      return guard.call("ipc.next", function () {
        return JSON.stringify(root.agenda.next || null)
      }, "null")
    }

    function today(): string {
      return guard.call("ipc.today", function () {
        return JSON.stringify(root.agenda.today || [])
      }, "[]")
    }

    function status(): string {
      return guard.call("ipc.status", function () {
        var known = []
        try { known = JSON.parse(persisted.notifiedKeys || "[]") } catch (e) { known = [] }
        return JSON.stringify({
          calendarDirs: root.calendarDirs,
          leadMinutes: Math.round(root.leadSeconds / 60),
          pollSeconds: root.pollSeconds,
          notified: known.length,
          generatedAt: root.agenda.generatedAt || 0
        })
      }, "{}")
    }
  }
}
