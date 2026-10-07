import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit
import "Model.js" as Model

// Bar widget: a horizontal marquee of every countdown — "21d · Disneyland
//   •   90d · Move house" — soonest first, scrolling left-to-right as a live
// ticker. Click opens the add/list panel. State is a
// flat JSON list of { label, targetEpoch } under ~/.local/state/omarchy/;
// days-remaining is always derived from the stored target so a countdown
// keeps ticking across restarts and rolls over on its own at local midnight.
// Same bar-widget + click-panel shape as alteringux.timers.
BarWidget {
  id: root
  moduleName: "alteringux.countdown"

  // State + history are two JSON files under ~/.local/state/omarchy/, each
  // managed by a Kit.Store (FileView + atomic write + `mkdir -p` + the 200 ms
  // save debounce — written once in alteringux.kit instead of copied in here).
  // The Store instances are defined further down; `state` / `history` read and
  // write straight through them.
  property alias state: stateStore.value
  property alias history: historyStore.value
  readonly property bool stateLoaded: stateStore.loaded
  readonly property bool historyLoaded: historyStore.loaded
  readonly property var added: history && history.added ? history.added : []

  readonly property var entries: state && state.entries ? state.entries : []
  readonly property bool hasEntries: entries.length > 0

  // Bumped by the slow tick and on panel open so every daysRemaining binding
  // re-evaluates. Day granularity — no need to spin faster.
  property double nowMs: Date.now()

  readonly property string marqueeContent: stateLoaded ? Model.marqueeText(root.entries, root.nowMs) : ""
  readonly property string emptyText: "  Countdown"
  // Marquee viewport width in raw px (comparable to the other widgets' label
  // widths). The widget stays this wide whenever countdowns exist; a single
  // short countdown fits without scrolling, longer/multiple ones scroll.
  readonly property real marqueeViewport: 300

  readonly property var guard: Kit.BugGuard.create("alteringux.countdown", function(argv) { Quickshell.execDetached(argv) })

  // Ids already notified that their countdown reached "Today", so the 30s
  // tick below fires the notification exactly once per countdown per day
  // rather than nagging every tick. In-memory only (reset on a shell
  // restart) — a missed notification across a restart is an acceptable
  // trade-off for not persisting yet another small state file.
  property var _dueNotified: ({})

  // Fire a one-shot "Today" notification for any entry that just rolled over
  // to daysRemaining === 0, skipping ids already recorded in _dueNotified.
  // Uses execDetached (not a shared Process) so two countdowns landing on
  // the same day each get their own notify-send instead of one clobbering
  // the other's command mid-launch. Also drops any recorded id that's no
  // longer due (rolled past, or the entry was removed) so the map can't grow
  // unbounded across a long uptime — that keeps a re-added countdown reusing
  // the same id notifiable again too.
  function checkDueNotifications() {
    guard.run("checkDueNotifications", function () {
      var list = root.entries
      var stillDue = {}
      for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (Model.daysRemaining(e.targetEpoch, root.nowMs) !== 0) continue
        stillDue[e.id] = true
        if (root._dueNotified[e.id]) continue
        Quickshell.execDetached([
          "notify-send", "-a", "Countdown", "-u", "normal",
          e.label || "Countdown", "Today"
        ])
      }
      root._dueNotified = stillDue
    })
  }

  // ---- persistence: both files are now written only by
  // ~/.local/bin/omarchy-countdowns (docs/adr/0006-cli-first-plugins.md).
  // Kit.Store runs in watch mode — it re-reads + re-parses as the CLI rewrites
  // them and the `state` / `history` aliases update straight through. The idle
  // poll covers FileView's watch-on-create blind spot.
  Kit.Store {
    id: stateStore
    fileName: "countdowns.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseState(raw) }
    onLoadedChanged: if (loaded) root.nowMs = Date.now()
    onExternallyChanged: root.nowMs = Date.now()
  }

  // The rolling log of added countdowns (label + day count, capped by the CLI)
  // — feeds the panel's most-used-label chips.
  Kit.Store {
    id: historyStore
    fileName: "countdown-history.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseHistory(raw) }
  }

  // ---- the CLI that owns every write to countdowns.json / countdown-history.json
  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/omarchy-countdowns"

  Process {
    id: actionProc
    running: false
    onExited: { stateStore.reload(); historyStore.reload() }
  }

  // Run one omarchy-countdowns verb (argv after the script path). Serialised
  // through actionProc; a verb fired mid-run falls back to execDetached.
  function runVerb(argv) {
    guard.run("runVerb:" + argv[0], function() {
      var cmd = [root.scriptPath].concat(argv)
      if (actionProc.running) { Quickshell.execDetached(cmd); return }
      actionProc.command = cmd
      actionProc.running = true
    })
  }

  function entryById(id) {
    var list = root.entries
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }

  // ---- actions — each runs the matching omarchy-countdowns verb; the watch
  //      on the two stores reflects the result back into `state` / `history`.
  //      The CLI also owns folding an add into the history log.
  function addEntry(label, days) {
    if (!label || label.trim().length === 0) return
    root.runVerb(["add", String(days), label])
    root.nowMs = Date.now()
  }

  // Add by an absolute target epoch (the panel's date picker). The CLI takes a
  // yyyy-MM-dd key, so convert here with the same Model helper the picker uses.
  function addEntryAt(label, targetEpoch) {
    if (!label || label.trim().length === 0) return
    var key = Model.keyForEpoch(targetEpoch)
    if (!key) return
    root.runVerb(["add-at", key, label])
    root.nowMs = Date.now()
  }

  function removeEntry(id) { root.runVerb(["remove", id]) }

  // Edit-in-place: rename one countdown from its card (see docs/adr/0003).
  function renameEntry(id, label) { root.runVerb(["rename", id, label]) }

  function clearEntries() { root.runVerb(["clear"]) }

  // Forget one remembered "usual label" — the × on that chip in the panel.
  function forgetLabel(label) { root.runVerb(["forget", label]) }

  // ---- tick -------------------------------------------------------
  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: { root.nowMs = Date.now(); root.checkDueNotifications() }
  }

  onOpenedChanged: if (opened) nowMs = Date.now()
  onStateLoadedChanged: if (stateLoaded) root.checkDueNotifications()

  // ---- IPC ------------------------------------------------------
  IpcHandler {
    target: "alteringux.countdown"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function add(days: int, label: string): void { root.addEntry(label, days) }
    function addDate(date: string, label: string): void { root.addEntryAt(label, Model.epochForKey(date)) }
    function removeEntry(id: string): void { root.removeEntry(id) }
    function rename(id: string, label: string): void { root.renameEntry(id, label) }
    function clear(): void { root.clearEntries() }
    function forgetLabel(label: string): void { root.forgetLabel(label) }
    function status(): string {
      return guard.call("ipc.status", function() {
        return JSON.stringify({
          count: root.entries.length,
          soonestDays: Model.soonestDays(root.entries, Date.now())
        })
      }, "{}")
    }
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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.emptyText
    labelVisible: !root.hasEntries
    hasVisualContent: true
    fixedWidth: root.hasEntries ? root.marqueeViewport : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.hasEntries ? Model.listText(root.entries, root.nowMs) : ""

    onPressed: function(b) {
      root.togglePanel()
    }

    // ---- marquee overlay -------------------------------------------
    // Two identical copies of the text in a Row; the Row's x animates one
    // full copy-width right (from -copyWidth to 0) on an infinite loop, so
    // copy 1 slides into the gap copy 2 leaves — a seamless scroll.
    // When it fits, the Binding parks it centred and the animation is off.
    Item {
      id: marquee
      // Inset the scroll viewport from the slot edges so text sliding past
      // either end butts against a gutter, not against the neighbouring
      // widget (the pomodoro label + its progress bar sit immediately to the
      // left). The slot stays `marqueeViewport` wide; only the painted band
      // narrows. Mirrors the button's own `horizontalMargin`.
      anchors.fill: parent
      anchors.leftMargin: Style.spaceReal(8.75)
      anchors.rightMargin: Style.spaceReal(8.75)
      clip: true
      visible: root.hasEntries

      readonly property color fg: root.bar ? root.bar.barForeground : Color.foreground
      readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      readonly property real gap: 56
      readonly property real copyWidth: seg1.implicitWidth + gap
      // Always run the left-to-right scroll whenever there are countdowns, so
      // the widget reads as a live ticker instead of parking centred when the
      // text happens to fit. Restore `seg1.implicitWidth > marquee.width` here
      // to only scroll on overflow.
      readonly property bool scrolling: root.hasEntries && seg1.implicitWidth > 0 && marquee.width > 0

      Row {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        spacing: marquee.gap

        Text {
          id: seg1
          text: "  " + root.marqueeContent
          color: marquee.fg
          font.family: marquee.fontFamily
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
          verticalAlignment: Text.AlignVCenter
        }
        Text {
          id: seg2
          visible: marquee.scrolling
          text: seg1.text
          color: marquee.fg
          font.family: marquee.fontFamily
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
          verticalAlignment: Text.AlignVCenter
        }
      }

      // Parked position when it fits (animation is not running then).
      Binding {
        target: track
        property: "x"
        value: Math.max(0, (marquee.width - seg1.implicitWidth) / 2)
        when: !marquee.scrolling
      }

      // ~45 px/sec, min 4s per lap, restarts cleanly when the content width
      // changes (a day rolled over, or an entry was added/removed).
      NumberAnimation {
        id: scrollAnim
        target: track
        property: "x"
        running: marquee.visible && marquee.scrolling
        from: -marquee.copyWidth
        to: 0
        duration: Math.max(4000, Math.round(marquee.copyWidth * 22))
        loops: Animation.Infinite
        easing.type: Easing.Linear
      }
    }
  }
}
