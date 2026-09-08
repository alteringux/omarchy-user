import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model
import "../alteringux.kit" as Kit

// News Bar service: a persistent layer-shell bar on the bottom edge of every
// monitor (mirroring the top bar's PanelWindow contract — themed, per-screen,
// reserves screen space via an exclusion zone). It runs a single marquee of
// world/general news: a timer shells out to bin/omarchy-newsbar-refresh
// (curl + a stdlib Python RSS/Atom parser) → ~/.local/state/omarchy/newsbar.json;
// sources live in ~/.config/omarchy/newsbar-feeds.json. Click a headline →
// xdg-open. Hover a headline → a summary card pops above the bar.
//
// The marquee is a Kit.Store watch-mode reader of that state file; a FileView
// tracks the config's refresh cadence.
Item {
  id: root

  // Injected by the omarchy-shell host for service plugins.
  property string omarchyPath: ""
  property var shell: null
  property var pluginRegistry: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/alteringux.newsbar"
  readonly property string refreshScript: pluginDir + "/bin/omarchy-newsbar-refresh"
  // newsbar.json (the Store's file) and newsbar-feeds.json both sit outside the
  // plugin source dir on purpose: the shell's plugin-file watcher would treat a
  // write there as a code change and tear the bar down.
  readonly property string feedsPath: home + "/.config/omarchy/newsbar-feeds.json"

  readonly property string togglesDir: home + "/.local/state/omarchy/toggles"
  readonly property string hiddenFlagPath: togglesDir + "/newsbar-off"
  // The top bar's own hide flag (flipped by `omarchy-toggle-bar`). The bottom
  // bar follows it, so hiding the top bar hides this one too.
  readonly property string topBarFlagPath: togglesDir + "/bar-off"

  // Kept in sync with bin/newsbar_fetch.py's DEFAULT_CONFIG. Written here too
  // (on first run / unreadable config) so the user always has a file to edit
  // even if the very first fetch fails.
  readonly property string defaultFeedsJson: JSON.stringify({
    version: 1,
    perFeed: 8,
    maxHeadlines: 40,
    refreshMinutes: 5,
    feeds: [
      { name: "BBC", url: "https://feeds.bbci.co.uk/news/world/rss.xml", category: "World" },
      { name: "NPR", url: "https://feeds.npr.org/1001/rss.xml" },
      { name: "Guardian", url: "https://www.theguardian.com/world/rss", category: "World" },
      { name: "Al Jazeera", url: "https://www.aljazeera.com/xml/rss/all.xml", category: "World" },
      { name: "AP", url: "https://feedx.net/rss/ap.xml", category: "World" }
    ]
  }, null, 2) + "\n"

  // newsbar.json is written by bin/omarchy-newsbar-refresh, so the Store watches
  // it (+ a 45 s poll for the watch-on-create gap) rather than owning it.
  property alias state: stateStore.value
  // Age-annotated headlines actually shown. Only reassigned when the headline
  // set genuinely changes (Model.signature), so an unchanged refresh doesn't
  // restart the scroll.
  property var headlines: []
  property string lastSignature: ""

  // Hidden when the user has toggled this bar off (newsbar-off flag) OR the
  // top bar is hidden (bar-off flag) — the two flag states are tracked
  // separately so `show`/`hide`/`toggle` only ever touch our own flag.
  property bool ownHidden: false
  property bool topBarHidden: false
  readonly property bool hidden: ownHidden || topBarHidden
  property bool refreshing: false
  property bool refreshPending: false
  property int refreshMinutes: 5

  readonly property int barSize: Math.max(20, Style.bar.sizeHorizontal)

  readonly property string placeholderText: {
    if (state.headlines && state.headlines.length > 0) return ""
    if (state.error) return "News Bar — " + state.error
    return "Fetching headlines…"
  }

  readonly property var guard: Kit.BugGuard.create("alteringux.newsbar", function(argv) { Quickshell.execDetached(argv) })

  Kit.Store {
    id: stateStore
    fileName: "newsbar.json"
    watch: true
    pollMs: 45000
    parse: function (raw) { return Model.parseState(raw) }
    // Recompute the visible crawl only when the headline SET actually changes,
    // so an unchanged refresh doesn't restart the scroll.
    onExternallyChanged: function (value) {
      var sig = Model.signature(value.headlines)
      if (sig !== root.lastSignature) {
        root.lastSignature = sig
        root.headlines = Model.withAges(value.headlines, Date.now())
      }
    }
  }

  Component.onCompleted: {
    ensureDirsProc.running = true
    hiddenProbe.running = true
    Qt.callLater(function() { feedsFile.reload() })
  }

  // ------------------------------------------------------------- open article
  function openHeadline(url) {
    var clean = String(url || "").trim()
    if (!/^https?:\/\//i.test(clean)) return
    // xdg-open -> default browser, normal window/tab (not private).
    Quickshell.execDetached(["xdg-open", clean])
  }

  // ------------------------------------------------------------- refresh loop
  Process {
    id: ensureDirsProc
    command: ["mkdir", "-p", root.home + "/.local/state/omarchy", root.togglesDir]
    running: false
  }

  Process {
    id: refreshProc
    running: false
    onRunningChanged: root.refreshing = running
    onExited: {
      stateStore.reload()
      if (root.refreshPending) {
        root.refreshPending = false
        root.runRefresh()
      }
    }
  }

  // Guarded like every mutating entry point on the other alteringux.* plugins
  // (runVerb() etc.) — this one previously ran bare, so a throw here (e.g. a
  // future refactor leaving refreshScript unset) would escape uncaught from
  // every caller, including the unguarded IPC `refresh()` handler, instead of
  // being caught and reported through the shared bug-report pipeline.
  function runRefresh() {
    guard.run("runRefresh", function () {
      if (refreshProc.running) {
        root.refreshPending = true
        return
      }
      refreshProc.command = ["bash", root.refreshScript]
      refreshProc.running = true
    })
  }

  Timer {
    id: refreshTimer
    interval: Math.max(2, root.refreshMinutes) * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.runRefresh()
  }

  // If a fetch has never produced headlines, keep re-reading the feeds config
  // too — it may have just been created. (The state file's own re-read is the
  // Store's pollMs.)
  Timer {
    interval: 45 * 1000
    repeat: true
    running: root.headlines.length === 0
    onTriggered: feedsFile.reload()
  }

  // ------------------------------------------------------------- feeds config
  FileView {
    id: feedsFile
    path: root.feedsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: guard.run("feedsFile.onLoaded", function() {
      try {
        var j = JSON.parse(feedsFile.text() || "{}")
        if (j && j.refreshMinutes) root.refreshMinutes = Math.max(2, Number(j.refreshMinutes) || 15)
      } catch (e) {
        console.warn("newsbar: feeds config parse failed:", e)
      }
      root.runRefresh()
    })
    onLoadFailed: {
      feedsFile.setText(root.defaultFeedsJson)
      root.runRefresh()
    }
    onFileChanged: reload()
  }

  // ------------------------------------------------------------- hidden flag
  // Presence of a flag file = hidden. One probe reads both our own flag and
  // the top bar's, echoing "<own> <topbar>", so the bottom bar disappears
  // whenever the top bar is toggled off. FileView can't watch a
  // not-yet-existing file, so watch the parent toggles directory.
  Process {
    id: hiddenProbe
    running: false
    command: ["bash", "-c",
      "own=no; top=no; " +
      "[[ -f " + root.hiddenFlagPath + " ]] && own=yes; " +
      "[[ -f " + root.topBarFlagPath + " ]] && top=yes; " +
      "echo \"$own $top\""]
    stdout: SplitParser { onRead: function(line) {
      var p = String(line).trim().split(/\s+/)
      root.ownHidden = p[0] === "yes"
      root.topBarHidden = p[1] === "yes"
    } }
  }
  FileView {
    path: root.togglesDir
    watchChanges: true
    printErrors: false
    onFileChanged: hiddenProbe.running = true
  }
  // The directory watch can quietly stop delivering events after flags flip in
  // quick succession (same caveat the stock Bar.qml documents), which would
  // strand this bar out of sync with the top one. A cheap periodic re-probe
  // guarantees it catches up within a few seconds.
  Timer {
    interval: 3000
    repeat: true
    running: true
    onTriggered: if (!hiddenProbe.running) hiddenProbe.running = true
  }

  function setHidden(value) {
    guard.run("setHidden", function () {
      var next = value === true
      root.ownHidden = next
      var cmd = next
        ? "mkdir -p " + togglesDir + " && touch " + hiddenFlagPath
        : "rm -f " + hiddenFlagPath
      Quickshell.execDetached(["bash", "-c", cmd])
    })
  }

  // ------------------------------------------------------------- IPC
  IpcHandler {
    target: "alteringux.newsbar"

    function ping(): string { return "ok" }
    function refresh(): void { root.runRefresh() }
    function reloadConfig(): void { feedsFile.reload() }
    function show(): void { root.setHidden(false) }
    function hide(): void { root.setHidden(true) }
    function toggle(): void { root.setHidden(!root.hidden) }

    function status(): string {
      return guard.call("ipc.status", function() {
        return JSON.stringify({
          headlines: root.headlines.length,
          updatedAt: root.state.updatedAt,
          error: root.state.error,
          hidden: root.hidden,
          refreshing: root.refreshing,
          refreshMinutes: root.refreshMinutes,
          feedsPath: root.feedsPath
        })
      }, "{}")
    }
  }

  // ------------------------------------------------------------- the bar
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: win
        required property var modelData

        screen: modelData
        visible: !root.hidden
        exclusionMode: ExclusionMode.Auto
        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "omarchy-newsbar"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors { bottom: true; left: true; right: true }
        implicitHeight: root.barSize

        Rectangle {
          anchors.fill: parent
          color: Color.bar.background

          // Hairline divider along the top edge, echoing the top bar's weight.
          Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1
            color: Qt.rgba(Color.bar.text.r, Color.bar.text.g, Color.bar.text.b, 0.12)
          }

          // Middle-click anywhere on the bar forces an immediate refresh,
          // without waiting on IPC — mirrors cliamp/score's own middle-click
          // bar shortcuts. MarqueeSegment's per-headline TapHandlers only
          // accept the left button, so this still receives the middle one.
          TapHandler {
            acceptedButtons: Qt.MiddleButton
            onTapped: root.runRefresh()
          }

          MarqueeSegment {
            id: newsSeg
            anchors {
              fill: parent
              leftMargin: Style.space(6); rightMargin: Style.space(6)
            }
            panelWindow: win
            hostHidden: root.hidden
            headlines: root.headlines
            placeholder: root.placeholderText
            textColor: Color.bar.text
            accentColor: Color.bar.active
            fontFamily: Style.font.family
            fontSize: Style.font.body
            onActivate: function(url) { root.openHeadline(url) }
          }
        }
      }
    }
  }
}
