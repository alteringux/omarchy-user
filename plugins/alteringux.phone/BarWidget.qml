import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Phone for the bar: a phone icon that opens the contact picker, a live pill
// while a call is connected, and a ringing state for an incoming call. Hosts
// the fullscreen call screen and the contact panel, and exposes IPC so the
// Hyprland keybindings can drive it.
//
// This widget is a thin view. ~/.local/bin/omarchy-phone and its
// `systemd --user` daemon own the whole call — mic capture, whisper, the
// NanoGPT turn + tool loop, piper-tts, barge-in — plus the opt-in incoming
// scheduler, and every write to call.json / runtime.json / a contact's memory.
// config.json stays widget-owned here (ADR-0006 rule 4): the daemon reads and
// seeds it, this widget is the only writer of user changes.
BarWidget {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.phone"

  readonly property string home: Quickshell.env("HOME")
  readonly property string scriptPath: home + "/.local/bin/omarchy-phone"

  // ---- state (daemon-owned, watched) ---------------------------------
  readonly property var call: callStore.value || Model.defaultCall()
  readonly property var runtime: runtimeStore.value || { armed: false, dnd: false }
  property alias config: configStore.value
  readonly property bool configLoaded: configStore.loaded

  readonly property string state: root.call.state || "IDLE"
  readonly property bool idle: root.state === "IDLE"
  readonly property bool dialing: root.state === "DIALING"
  readonly property bool ringing: root.state === "RINGING"
  readonly property bool connected: root.state === "CONNECTED"
  readonly property bool inCall: root.dialing || root.connected
  readonly property bool active: root.state !== "IDLE" && root.state !== "ENDED"

  readonly property bool dnd: root.runtime && root.runtime.dnd === true
  readonly property bool incomingArmed: root.runtime && root.runtime.armed === true

  // A local clock so the connected read-out ticks without waiting on the
  // daemon's heartbeat writes.
  property int elapsedSeconds: 0

  readonly property color barForeground: root.bar ? _webPalette.barForeground : _webPalette.foreground
  readonly property var guard: Kit.BugGuard.create("alteringux.phone", function (argv) { Quickshell.execDetached(argv) })
  property string actionStatus: ""
  property bool actionFailed: false
  property int actionGeneration: 0
  signal actionFeedback(string message)
  function reportActionStatus(message, failed) {
    actionStatus = message
    actionFailed = failed === true
    actionFeedback(message)
  }

  // installed piper voices — for the contact editor
  property var voices: []

  // contacts, refreshed on panel open and after a save/delete
  property var contacts: []

  readonly property string turnGlyph: {
    switch (root.call.turn) {
    case "listening": return ""  // nf-fa-microphone
    case "thinking":  return ""  // nf-fa-spinner
    case "tool":      return ""  // nf-fa-search
    case "speaking":  return ""  // nf-fa-bullhorn
    default:          return ""
    }
  }

  readonly property string icon: {
    if (root.ringing) return ""      // nf-fa-phone (ring handled by pulse)
    if (root.connected) return ""
    if (root.dialing) return ""
    if (root.dnd) return ""          // nf-md-phone_off-ish; falls back fine
    return ""                        // nf-fa-phone
  }

  // ---- persistence --------------------------------------------------
  Kit.Store {
    id: configStore
    dir: root.home + "/.local/state/omarchy/phone/"
    fileName: "config.json"
    parse: function (raw) { return Model.parseConfig(raw) }
    serialize: function (value) { return Model.serializeConfig(value) }
    seedOnCreate: true
  }

  Kit.Store {
    id: callStore
    dir: root.home + "/.local/state/omarchy/phone/"
    fileName: "call.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseCall(raw) }
    onExternallyChanged: function (value) {
      root.guard.run("call.sync", function () {
        var connectedAt = value && value.connectedAtMs ? value.connectedAtMs : 0
        if (value && value.state === "CONNECTED" && connectedAt > 0)
          root.elapsedSeconds = Math.max(0, Math.floor((Date.now() - connectedAt) / 1000))
        else
          root.elapsedSeconds = 0
      })
    }
  }

  Kit.Store {
    id: runtimeStore
    dir: root.home + "/.local/state/omarchy/phone/"
    fileName: "runtime.json"
    watch: true
    pollMs: 60000
    parse: function (raw) {
      try { var v = raw && raw.length ? JSON.parse(raw) : {}; return { armed: v.armed === true, dnd: v.dnd === true } }
      catch (e) { return { armed: false, dnd: false } }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.connected
    onTriggered: {
      var connectedAt = root.call.connectedAtMs || 0
      if (connectedAt > 0) root.elapsedSeconds = Math.max(0, Math.floor((Date.now() - connectedAt) / 1000))
    }
  }

  // ---- the CLI ----------------------------------------------------
  Process {
    id: actionProc
    property int feedbackGeneration: -1
    property bool feedbackStarted: false
    running: false
    onStarted: feedbackStarted = true
    onRunningChanged: {
      if (!running && !feedbackStarted && feedbackGeneration === root.actionGeneration) {
        feedbackGeneration = -1
        root.reportActionStatus("Phone helper unavailable. Check ~/.local/bin/omarchy-phone is installed and executable.", true)
      }
    }
    onExited: function(code, status) {
      callStore.reload(); runtimeStore.reload()
      var generation = feedbackGeneration
      feedbackGeneration = -1
      if (generation < 0 || generation !== root.actionGeneration) return
      root.reportActionStatus(code === 0 && status === 0
        ? "Phone request accepted. Call state will confirm progress."
        : "Phone request failed (exit " + code + "). Try again; check the Phone helper if it persists.", code !== 0 || status !== 0)
    }
  }

  function runVerb(args, feedback) {
    root.guard.run("runVerb:" + args.join(" "), function () {
      var report = feedback !== false
      if (report) root.actionGeneration++
      try {
        var argv = [root.scriptPath].concat(args)
        if (actionProc.running || actionProc.feedbackGeneration >= 0) {
          Quickshell.execDetached(argv)
          if (report) root.reportActionStatus("Phone request sent. Completion cannot be confirmed while another request is running.", false)
          return
        }
        actionProc.feedbackGeneration = report ? root.actionGeneration : -1
        actionProc.feedbackStarted = false
        actionProc.command = argv
        if (report) {
          root.actionFailed = false
          root.actionStatus = "Working…"
          root.actionFeedback(root.actionStatus)
        }
        actionProc.running = true
      } catch (error) {
        actionProc.feedbackGeneration = -1
        if (report) root.reportActionStatus("Phone request could not be sent. Try again; check the helper if it persists.", true)
        throw error
      }
    })
  }

  function startCall(id) { root.runVerb(["call", id]) }
  function answer()  { root.runVerb(["answer"]) }
  function decline() { root.runVerb(["decline"]) }
  function hangup()  { root.runVerb(["hangup"]) }
  function toggleMute() { root.runVerb([root.call.muted ? "unmute" : "mute"]) }
  function toggleHold() { root.runVerb([root.call.hold ? "resume" : "hold"]) }
  function setMuted(on) { root.runVerb([on ? "mute" : "unmute"]) }
  function toggleDnd() { root.runVerb(["dnd", root.dnd ? "off" : "on"]) }
  function say(text) { if (text && text.length) root.runVerb(["say", text]) }
  function forgetMemory(id) { root.runVerb(["memory-forget", id]) }

  // ---- contact list -----------------------------------------------
  Process {
    id: contactsProc
    property bool started: false
    property bool attempted: false
    command: [root.scriptPath, "contacts"]
    onStarted: started = true
    onRunningChanged: {
      if (running) { started = false; attempted = true }
      else if (attempted && !started) {
        attempted = false
        root.reportActionStatus("Contacts unavailable. Check ~/.local/bin/omarchy-phone.", true)
      }
    }
    onExited: function(code, status) {
      started = false
      attempted = false
      if (code !== 0 || status !== 0) root.reportActionStatus("Contacts could not be loaded (exit " + code + ").", true)
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.guard.run("contacts", function () {
        try {
          var data = JSON.parse(text || "[]")
          if (!Array.isArray(data)) throw new Error("expected contact list")
          root.contacts = data
        } catch (e) {
          root.contacts = []
          root.reportActionStatus("Contacts could not be read. Check the Phone helper and try again.", true)
        }
      })
    }
  }
  function refreshContacts() { if (!contactsProc.running) contactsProc.running = true }

  Process {
    id: voicesProc
    property bool started: false
    property bool attempted: false
    command: [root.scriptPath, "voices"]
    onStarted: started = true
    onRunningChanged: {
      if (running) { started = false; attempted = true }
      else if (attempted && !started) {
        attempted = false
        root.reportActionStatus("Voice list unavailable. Check ~/.local/bin/omarchy-phone.", true)
      }
    }
    onExited: function(code, status) {
      started = false
      attempted = false
      if (code !== 0 || status !== 0) root.reportActionStatus("Voice list could not be loaded (exit " + code + ").", true)
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.guard.run("voices", function () {
        try {
          var data = JSON.parse(text || "{}")
          if (!data || !Array.isArray(data.voices)) throw new Error("expected voice list")
          root.voices = data.voices
        } catch (e) {
          root.voices = []
          root.reportActionStatus("Voice list could not be read. Check the Phone helper and try again.", true)
        }
      })
    }
  }
  function refreshVoices() { if (!voicesProc.running) voicesProc.running = true }

  // Save a contact object (the panel builds it). stdin JSON -> contact-save.
  Process {
    id: saveProc
    property int feedbackGeneration: -1
    property bool feedbackStarted: false
    running: false
    onStarted: feedbackStarted = true
    onRunningChanged: {
      if (!running && !feedbackStarted && feedbackGeneration === root.actionGeneration) {
        feedbackGeneration = -1
        root.reportActionStatus("Contact save unavailable. Check that ~/.local/bin/omarchy-phone can write its contact store.", true)
      }
    }
    onExited: function(code, status) {
      root.refreshContacts()
      var generation = feedbackGeneration
      feedbackGeneration = -1
      if (generation !== root.actionGeneration) return
      root.reportActionStatus(code === 0 && status === 0
        ? "Contact save command completed."
        : "Contact save failed (exit " + code + "). Check the Phone helper and try again.", code !== 0 || status !== 0)
    }
  }
  function saveContact(obj) {
    root.guard.run("saveContact", function () {
      root.actionGeneration++
      try {
        if (saveProc.running) {
          root.reportActionStatus("A contact save is already running. Wait for it to finish before retrying.", true)
          return
        }
        saveProc.feedbackGeneration = root.actionGeneration
        saveProc.feedbackStarted = false
        saveProc.command = ["bash", "-lc",
          "printf '%s' " + shellQuote(JSON.stringify(obj)) + " | " + shellQuote(root.scriptPath) + " contact-save"]
        root.actionFailed = false
        root.actionStatus = "Saving contact…"
        root.actionFeedback(root.actionStatus)
        saveProc.running = true
      } catch (error) {
        saveProc.feedbackGeneration = -1
        root.reportActionStatus("Contact save could not be started. Try again.", true)
        throw error
      }
    })
  }
  Process {
    id: deleteProc
    property int feedbackGeneration: -1
    property bool feedbackStarted: false
    running: false
    onStarted: feedbackStarted = true
    onRunningChanged: {
      if (!running && !feedbackStarted && feedbackGeneration === root.actionGeneration) {
        feedbackGeneration = -1
        root.reportActionStatus("Contact delete unavailable. Check that ~/.local/bin/omarchy-phone can write its contact store.", true)
      }
    }
    onExited: function(code, status) {
      root.refreshContacts()
      var generation = feedbackGeneration
      feedbackGeneration = -1
      if (generation !== root.actionGeneration) return
      root.reportActionStatus(code === 0 && status === 0
        ? "Contact delete command completed."
        : "Contact delete failed (exit " + code + "). Check the Phone helper and try again.", code !== 0 || status !== 0)
    }
  }
  function deleteContact(id) {
    root.guard.run("deleteContact", function () {
      root.actionGeneration++
      try {
        if (deleteProc.running) {
          root.reportActionStatus("A contact delete is already running. Wait for it to finish before retrying.", true)
          return
        }
        deleteProc.feedbackGeneration = root.actionGeneration
        deleteProc.feedbackStarted = false
        deleteProc.command = [root.scriptPath, "contact-delete", id]
        root.actionFailed = false
        root.actionStatus = "Deleting contact…"
        root.actionFeedback(root.actionStatus)
        deleteProc.running = true
      } catch (error) {
        deleteProc.feedbackGeneration = -1
        root.reportActionStatus("Contact delete could not be started. Try again.", true)
        throw error
      }
    })
  }

  function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  // ---- config writes (widget-owned) -----------------------------
  function updateConfig(patch) {
    root.guard.run("updateConfig", function () {
      if (!configStore.loaded) return
      var next = JSON.parse(JSON.stringify(root.config))
      for (var k in patch) {
        if (k === "quietHours" && patch.quietHours && typeof patch.quietHours === "object") {
          if (!next.quietHours) next.quietHours = {}
          for (var q in patch.quietHours) next.quietHours[q] = patch.quietHours[q]
        } else {
          next[k] = patch[k]
        }
      }
      root.config = next
      configStore.save()
      // Arm / disarm the incoming scheduler to match.
      if ("incomingEnabled" in patch)
        root.runVerb([patch.incomingEnabled ? "arm" : "disarm"])
    })
  }

  onConfigLoadedChanged: {
    if (root.configLoaded && root.config && root.config.incomingEnabled)
      root.runVerb(["arm"], false)
  }

  Component.onCompleted: {
    root.refreshContacts()
    root.refreshVoices()
  }

  // ---- the call screen (real layer-shell window; exists only when wanted) --
  property bool screenDismissed: false
  readonly property bool screenWanted: (root.active) && !root.screenDismissed

  onActiveChanged: if (!root.active) root.screenDismissed = false

  LazyLoader {
    active: root.screenWanted
    CallScreen { hostWidget: root }
  }

  function showCallScreen() { root.screenDismissed = false }
  function dismissCallScreen() { root.screenDismissed = true }

  // ---- IPC ------------------------------------------------------
  IpcHandler {
    target: "alteringux.phone"

    function panel(): void { root.togglePanel() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function call(id: string): void { if (id && id.length) root.startCall(id); else root.togglePanel() }
    function answer(): void { root.answer() }
    function decline(): void { root.decline() }
    function hangup(): void { root.hangup() }
    function mute(): void { root.setMuted(true) }
    function unmute(): void { root.setMuted(false) }
    function muteToggle(): void { root.toggleMute() }
    function hold(): void { root.runVerb(["hold"]) }
    function resume(): void { root.runVerb(["resume"]) }
    function dnd(): void { root.toggleDnd() }
    function screen(): void { if (root.screenDismissed) root.showCallScreen(); else root.dismissCallScreen() }
    function status(): string {
      return root.guard.call("ipc.status", function () {
        return JSON.stringify({
          state: root.state,
          contactId: root.call.contactId,
          contactName: root.call.contactName,
          direction: root.call.direction,
          turn: root.call.turn,
          toolLabel: root.call.toolLabel,
          muted: root.call.muted === true,
          hold: root.call.hold === true,
          elapsedSeconds: root.elapsedSeconds,
          dnd: root.dnd,
          incomingArmed: root.incomingArmed,
          lastError: root.call.lastError || ""
        })
      }, "{}")
    }
  }

  // ---- panel wiring (mirrors alteringux.stopwatch / ttsplayer) ---
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { root.refreshContacts(); root.refreshVoices(); if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { root.refreshContacts(); root.refreshVoices(); if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  // ---- the bar label -------------------------------------------
  readonly property string displayText: {
    if (root.ringing) return root.icon + "  " + (root.call.contactName || "Incoming") + " calling…"
    if (root.dialing) return root.icon + "  " + (root.call.contactName || "Calling") + "…"
    if (root.connected) {
      var t = root.icon + "  " + (root.call.contactName || "Call")
      t += " " + Model.formatCallClock(root.elapsedSeconds * 1000)
      if (root.call.muted) t += "  "   // muted mic
      else if (root.call.hold) t += "  " // pause
      else if (root.turnGlyph) t += "  " + root.turnGlyph
      return t
    }
    if (root.dnd) return root.icon + "  DND"
    return root.icon
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function (b) {
      if (b === Qt.MiddleButton) {
        if (root.connected || root.dialing) root.toggleMute()
        else if (root.ringing) root.decline()
        else root.toggleDnd()
      } else if (b === Qt.RightButton) {
        if (root.active) root.hangup()
        else root.togglePanel()
      } else {
        // Left click: ringing -> answer; in a call -> raise the call screen;
        // otherwise open the contact picker.
        if (root.ringing) root.answer()
        else if (root.active) { root.showCallScreen() }
        else root.togglePanel()
      }
    }

    // Pulsing dot while ringing / a live-call tick.
    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 2
      active: root.ringing || root.connected
      level: root.ringing ? "urgent" : "info"
    }
  }
}
