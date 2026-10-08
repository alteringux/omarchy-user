import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Desk Pet's bar face: a small mood indicator for the floating companion.
// This widget owns ALL the state (Kit.Store in owned mode, same pattern as
// alteringux.stocks' watchlist) -- there is no daemon here, everything is
// pure QML/JS math over a JSON file the widget itself writes.
//
// The floating pet overlay (Pet.qml) is loaded here too, independent of
// whether the settings Panel is open, so the companion stays visible on the
// desktop the whole time it's enabled.
BarWidget {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.deskpet"

  readonly property var guard: Kit.BugGuard.create("alteringux.deskpet", function (argv) { Quickshell.execDetached(argv) })

  Kit.Store {
    id: petStore
    fileName: "deskpet-state.json"
    seedOnCreate: true
    parse: function (raw) { return Model.parseState(raw) }
  }

  readonly property var state: petStore.value || Model.defaultState()
  readonly property bool stateLoaded: petStore.loaded
  readonly property var pet: Model.petById(root.state.petId)

  // A slow clock so decay / idle / sleep re-evaluate without a user action.
  property double nowMs: Date.now()
  Timer { interval: 20000; repeat: true; running: true; onTriggered: root.nowMs = Date.now() }

  // Battery, for the low-battery quip. Same UPower surface omarchy.battery
  // uses; deskpet only reads it, never warns on its own.
  readonly property int batteryPercent: {
    var d = UPower.displayDevice
    if (!d || !d.isPresent) return -1
    return Math.round(Number(d.percentage || 0) * 100)
  }
  readonly property bool isLowBattery: root.batteryPercent >= 0 && root.batteryPercent <= 15
    && UPower.onBattery && UPower.displayDevice && UPower.displayDevice.state === UPowerDeviceState.Discharging

  readonly property var liveState: Model.applyDecay(root.state, root.nowMs)
  readonly property string mood: Model.moodLabel(root.liveState)
  readonly property int minutesIdleValue: Model.minutesIdle(root.liveState, root.nowMs)
  // Wall-clock hour for the time-of-day chatter; re-derived on the same 20s
  // clock as nowMs, so it's at most 20s stale when it matters.
  readonly property int hourValue: new Date(root.nowMs).getHours()
  readonly property int monthValue: new Date(root.nowMs).getMonth() + 1
  readonly property int dayValue: new Date(root.nowMs).getDate()
  readonly property int ageDaysValue: Model.ageDays(root.liveState, root.nowMs)
  readonly property var levelInfo: Model.levelInfo(root.liveState)
  readonly property var unlockedIds: Model.unlockedAchievementIds(root.liveState, root.nowMs)

  function _commit(next) { petStore.value = next; petStore.save() }
  function _tick() { return Model.applyDecay(root.state, root.nowMs) }

  function feedPet() { guard.run("feed", function () { root._commit(Model.feed(root._tick(), root.nowMs)) }) }
  function playWithPet() { guard.run("play", function () { root._commit(Model.play(root._tick(), root.nowMs)) }) }
  function pokePet() { guard.run("poke", function () { root._commit(Model.poke(root._tick(), root.nowMs)) }) }
  function toggleSleep() {
    guard.run("toggleSleep", function () {
      // Key off the pet's ACTUAL sleep state, not just manualSleep: an
      // energy-exhausted pet has manualSleep=false, so the old toggle sent
      // it a redundant "sleep" on the first press and never woke it.
      root._commit(Model.setSleep(root._tick(), !root.liveState.asleep))
    })
  }
  function selectPet(id) { guard.run("selectPet:" + id, function () { root._commit(Model.selectPet(root._tick(), id)) }) }
  function nextPet() { root.selectPet(Model.nextPetId(root.state.petId)) }
  function prevPet() { root.selectPet(Model.prevPetId(root.state.petId)) }
  function setPosition(fx, fy) { guard.run("setPosition", function () { root._commit(Model.setPosition(root._tick(), fx, fy)) }) }
  function equipAccessory(id) { guard.run("equipAccessory:" + id, function () { root._commit(Model.equipAccessory(root._tick(), id, root.nowMs)) }) }
  function setEnabled(on) { guard.run("setEnabled", function () { var n = root._tick(); n.enabled = !!on; root._commit(n) }) }
  function setMuted(on) { guard.run("setMuted", function () { var n = root._tick(); n.muted = !!on; root._commit(n) }) }
  function setSpeechFreq(min) {
    guard.run("setSpeechFreq", function () {
      var n = root._tick()
      n.speechFreqMin = Model.clamp(min, 1, 240)
      root._commit(n)
    })
  }
  function setScreenWatchEnabled(on) {
    guard.run("setScreenWatchEnabled", function () { var n = root._tick(); n.screenWatchEnabled = !!on; root._commit(n) })
  }
  function setScreenLookFreq(min) {
    guard.run("setScreenLookFreq", function () {
      var n = root._tick()
      n.screenLookFreqMin = Model.clamp(min, 5, 180)
      root._commit(n)
    })
  }
  function setRoamMode(mode) {
    guard.run("setRoamMode:" + mode, function () {
      var n = root._tick()
      n.roamMode = Model.ROAM_MODES.indexOf(mode) >= 0 ? mode : "off"
      root._commit(n)
    })
  }

  // ---- IPC (Hyprland keybindings) ----------------------------------
  IpcHandler {
    target: "alteringux.deskpet"

    function feed(): void { root.feedPet() }
    function play(): void { root.playWithPet() }
    function poke(): void { root.pokePet() }
    function toggle(): void { root.setEnabled(!root.state.enabled) }
    function mute(): void { root.setMuted(!root.state.muted) }
    function next(): void { root.nextPet() }
    function prev(): void { root.prevPet() }
    // toggleSleep() was only reachable from the panel's Sleep/Wake button --
    // every other mutating verb here (feed/play/poke/mute) already has an IPC
    // twin for scripting + Hyprland keybindings, this one didn't.
    function sleep(): void { root.toggleSleep() }
    function roam(mode: string): void { root.setRoamMode(mode) }
    function screenwatch(): void { root.setScreenWatchEnabled(!root.state.screenWatchEnabled) }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function status(): string {
      return root.guard.call("ipc.status", function () {
        return JSON.stringify({
          pet: root.pet.id, mood: root.mood, enabled: root.state.enabled,
          happiness: Math.round(root.liveState.happiness), fullness: Math.round(root.liveState.fullness),
          energy: Math.round(root.liveState.energy), asleep: root.liveState.asleep,
          roamMode: root.state.roamMode, screenWatchEnabled: root.state.screenWatchEnabled
        })
      }, "{}")
    }
  }

  // ---- settings panel ------------------------------------------------
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  // The floating companion. Always present on screen while enabled, wholly
  // independent of the settings panel's open/closed state.
  LazyLoader {
    active: root.stateLoaded && root.state.enabled
    Pet { hostWidget: root }
  }

  readonly property string displayText: {
    if (!root.state.enabled) return root.pet.glyph + " 󰈉"   // nf-md-eye_off, dimmed by hidden below
    var t = root.pet.glyph
    if (root.liveState.asleep) t += " 󰒲"                     // nf-md-sleep
    else t += " " + Model.moodFace(root.mood)
    if (root.state.muted) t += " \uf027"                     // fa-volume_off, the hush mark
    return t
  }

  readonly property color displayColor: {
    if (!root.state.enabled) return _webPalette.barMuted
    if (root.mood === "hungry" || root.mood === "grumpy") return _webPalette.barWarning
    return root.bar ? _webPalette.barForeground : _webPalette.foreground
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    foreground: root.displayColor
    active: root.mood === "hungry" || root.mood === "grumpy"
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function (b) {
      // Right-click hushes the pet (toggles mute) instead of opening the panel.
      if (b === Qt.RightButton) { root.setMuted(!root.state.muted); return }
      root.togglePanel()
    }

    // A dot when the pet needs attention (hungry/grumpy) so the bar face
    // doubles as a "someone wants a snack" indicator, same shape grip uses.
    Kit.AttentionDot {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.spaceReal(3)
      anchors.rightMargin: Style.spaceReal(2)
      active: root.state.enabled && (root.mood === "hungry" || root.mood === "grumpy")
      level: root.mood === "hungry" ? "warning" : "info"
    }
  }
}
