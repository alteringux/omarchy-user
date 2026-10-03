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
//   omarchy-shell ipc call alteringux.agenda upcoming
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

  // The next/today mirror for external consumers. Owned mode — this service is
  // the only writer. Written straight through FileView rather than a base64 +
  // `bash -lc` hop through Qt.btoa(), which is deprecated and fired a console
  // warning on every poll.
  Kit.Store {
    id: stateStore
    dir: root.runtimeDir + "/omarchy-agenda/"
    fileName: "state"
    serialize: function (v) { return JSON.stringify(v) + "\n" }
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
      if (decision.notify) {
        var sent = sendNotification(decision.event)
        // sendNotification() drops the alert (returns false) when notifyProc is
        // still busy from a previous poll. Persisting decision.keys unconditionally
        // would mark this event "notified" even though nothing was shown, and
        // shouldNotify() would then never retry it for the rest of the lead
        // window. Keep the pre-add key list instead so the next poll tries again.
        persisted.notifiedKeys = JSON.stringify(sent
          ? decision.keys
          : decision.keys.filter(function (k) { return k !== decision.key }))
      } else {
        persisted.notifiedKeys = JSON.stringify(decision.keys || [])
      }
    })
  }

  function writeState(now) {
    guard.run("writeState", function () {
      stateStore.value = Model.stateJson(root.agenda, now)
      stateStore.flush()
    })
  }

  // Returns whether the notification was actually dispatched (false if
  // notifyProc was already busy or there's no event) — the caller uses this
  // to decide whether the event's key may be recorded as delivered.
  function sendNotification(ev) {
    if (notifyProc.running || !ev) return false
    var now = Math.floor(Date.now() / 1000)
    var minutesUntil = Math.round((ev.start - now) / 60)
    // Match the urgent/critical visual language the rest of alteringux.* uses
    // for "about to happen" (Kit.Palette / AttentionDot levels) so an event
    // that's essentially now stands out from one that's still 8 minutes off.
    var urgency = minutesUntil <= 2 ? "critical" : "normal"
    var body = Model.formatRelative(ev.start - now) + " · " + Model.formatClock(ev.start)
    if (ev.location) body += "\n" + ev.location
    notifyProc.command = [
      "notify-send", "-a", "Agenda", "-u", urgency, "-i", "x-office-calendar",
      "-h", "string:x-canonical-private-synchronous:agenda",
      ev.summary || "Upcoming event", body
    ]
    notifyProc.running = true
    return true
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
    interval: Math.max(60, root.pollSeconds) * 1000
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

    // The full not-yet-ended list (up to 20, per Model.computeAgenda), for a
    // widget/CLI that wants more than just the single soonest event.
    function upcoming(): string {
      return guard.call("ipc.upcoming", function () {
        return JSON.stringify(root.agenda.upcoming || [])
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
