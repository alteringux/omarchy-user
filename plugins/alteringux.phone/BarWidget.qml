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

  readonly property color barForeground: root.bar ? Color.bar.text : Color.foreground
  readonly property var guard: Kit.BugGuard.create("alteringux.phone", function (argv) { Quickshell.execDetached(argv) })

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
    running: false
    onExited: { callStore.reload(); runtimeStore.reload() }
  }

  function runVerb(args) {
    root.guard.run("runVerb:" + args.join(" "), function () {
      var argv = [root.scriptPath].concat(args)
      if (actionProc.running) { Quickshell.execDetached(argv); return }
      actionProc.command = argv
      actionProc.running = true
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
    command: [root.scriptPath, "contacts"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.guard.run("contacts", function () {
        try { root.contacts = JSON.parse(text) || [] } catch (e) { root.contacts = [] }
      })
    }
  }
  function refreshContacts() { if (!contactsProc.running) contactsProc.running = true }

  Process {
    id: voicesProc
    command: [root.scriptPath, "voices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.guard.run("voices", function () {
        try { root.voices = (JSON.parse(text) || {}).voices || [] } catch (e) { root.voices = [] }
      })
    }
  }
  function refreshVoices() { if (!voicesProc.running) voicesProc.running = true }

  // Save a contact object (the panel builds it). stdin JSON -> contact-save.
  Process { id: saveProc; running: false; onExited: root.refreshContacts() }
  function saveContact(obj) {
    root.guard.run("saveContact", function () {
      saveProc.command = ["bash", "-lc",
        "printf '%s' " + shellQuote(JSON.stringify(obj)) + " | " + shellQuote(root.scriptPath) + " contact-save"]
      saveProc.running = true
    })
  }
  Process { id: deleteProc; running: false; onExited: root.refreshContacts() }
  function deleteContact(id) {
    root.guard.run("deleteContact", function () {
      deleteProc.command = [root.scriptPath, "contact-delete", id]
      deleteProc.running = true
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

  Component.onCompleted: {
    root.refreshContacts()
    root.refreshVoices()
    // If incoming was left enabled, make sure the scheduler is armed.
    Qt.callLater(function () {
      if (root.configLoaded && root.config && root.config.incomingEnabled) root.runVerb(["arm"])
    })
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
