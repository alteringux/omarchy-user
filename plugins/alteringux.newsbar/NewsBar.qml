import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

// News Bar service: a persistent layer-shell bar on the bottom edge of every
// monitor (mirroring the top bar's PanelWindow contract — themed, per-screen,
// reserves screen space via an exclusion zone). The bar is split down the
// middle into two independent marquees:
//
//   right half — world/general news. A timer shells out to
//     bin/omarchy-newsbar-refresh (curl + a stdlib Python RSS/Atom parser) →
//     ~/.local/state/omarchy/newsbar.json; sources in
//     ~/.config/omarchy/newsbar-feeds.json. Click a headline → xdg-open.
//
//   left half — newest Literotica stories, scraped from one listing page by
//     bin/omarchy-eronews-refresh → ~/.local/state/omarchy/eronews.json;
//     knobs in ~/.config/omarchy/eronews-feeds.json. Click a title → the
//     story is read aloud with Piper TTS (bin/eronews-read; click again to
//     stop). The hover card shows the author's one-line blurb as a TLDR.
//
// Both halves are Kit.Store watch-mode readers of their state file; a FileView
// per side tracks the config's refresh cadence.
Item {
  property QtObject _webPalette: Kit.Palette {}
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

  // Left-half "ero-news" crawl: newest Literotica stories, scraped by
  // bin/omarchy-eronews-refresh into ~/.local/state/omarchy/eronews.json.
  // Clicking a title hands the story URL to bin/eronews-read, which streams it
  // through Piper TTS (click again to stop).
  readonly property string eroRefreshScript: pluginDir + "/bin/omarchy-eronews-refresh"
  readonly property string eroReadScript: pluginDir + "/bin/eronews-read"
  // Left-half source selection lives here now (was eronews-feeds.json). The
  // generic scraper (bin/stories_fetch.py) reads .active + .sources[].recipe;
  // the switcher writes .active via bin/newsbar-set-source and appends new
  // sources via bin/newsbar-add-source (one NanoGPT call to derive a
  // recipe, then pure regex forever).
  readonly property string eroFeedsPath: home + "/.config/omarchy/newsbar-sources.json"
  readonly property string setSourceScript: pluginDir + "/bin/newsbar-set-source"
  readonly property string addSourceScript: pluginDir + "/bin/newsbar-add-source"
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
    maxAgeHours: 24,
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

  // Bottom-bar layout toggle, driven by the cycleHalves() IPC (a hotkey):
  //   false = both halves shown, split 50/50 (stories left, news right)
  //   true  = stories (left) half hidden; the news marquee spans the whole bar
  // Each press flips it. Persisted via the eronews-off flag file (same
  // convention as newsbar-off), so the hidden state survives a shell restart
  // and a reboot. hiddenProbe reads the flag back; setEroHidden writes it.
  property bool eroHidden: false
  readonly property string eroHiddenFlagPath: togglesDir + "/eronews-off"
  readonly property bool leftHalfShown: !root.eroHidden
  function cycleHalves() { root.setEroHidden(!root.eroHidden) }
  function setEroHidden(value) {
    var next = value === true
    root.eroHidden = next
    Quickshell.execDetached(["bash", "-c", next
      ? "mkdir -p " + togglesDir + " && touch " + eroHiddenFlagPath
      : "rm -f " + eroHiddenFlagPath])
  }
  property bool refreshing: false
  property bool refreshPending: false
  property int refreshMinutes: 5

  // ero-news mirror of the above
  property var eroHeadlines: []
  property string eroLastSignature: ""
  property bool eroRefreshing: false
  property bool eroRefreshPending: false
  property int eroRefreshMinutes: 3

  // Left-half source list + which one is active, read from newsbar-sources.json.
  property var eroSources: []
  property string eroActiveId: ""
  // Set once the config has been read at least once, so onLoaded can tell a
  // first-time provisioning load from a later re-read.
  property bool eroFeedsLoaded: false
  readonly property string eroActiveName: {
    for (var i = 0; i < eroSources.length; i++)
      if (eroSources[i].id === eroActiveId) return eroSources[i].name || eroSources[i].id
    return eroSources.length ? (eroSources[0].name || eroSources[0].id) : "Stories"
  }
  // switcher popup + add-source modal visibility
  property bool switcherOpen: false
  property bool addSourceOpen: false

  readonly property int barSize: Math.max(20, Style.bar.sizeHorizontal)

  readonly property string placeholderText: {
    if (state.headlines && state.headlines.length > 0) return ""
    if (state.error) return "News Bar — " + state.error
    return root.refreshing ? "Fetching headlines…" : "No new headlines"
  }

  readonly property string eroPlaceholderText: {
    if (eroStore.value.headlines && eroStore.value.headlines.length > 0) return ""
    if (eroStore.value.error) return "Ero-news — " + eroStore.value.error
    if (eroStore.value.loading) return "Loading " + root.eroActiveName + "…"
    return "No new stories"
  }

  readonly property var guard: Kit.BugGuard.create("alteringux.newsbar", function(argv) { Quickshell.execDetached(argv) })

  Kit.Store {
    id: stateStore
    fileName: "newsbar.json"
    watch: true
    pollMs: 60000
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

  // Same contract as stateStore, for the left-half Literotica crawl.
  Kit.Store {
    id: eroStore
    fileName: "eronews.json"
    watch: true
    pollMs: 60000
    parse: function (raw) { return Model.parseState(raw) }
    onExternallyChanged: function (value) {
      var sig = Model.signature(value.headlines)
      if (sig !== root.eroLastSignature) {
        root.eroLastSignature = sig
        root.eroHeadlines = Model.withAges(value.headlines, Date.now())
      }
    }
  }

  // Instant source-switch preview. setSource points this at the picked source's
  // last cached snapshot and paints it straight into eroHeadlines on the next
  // frame, so first paint no longer waits on the newsbar-set-source subprocess
  // (bash + python3 cold start, ~100-200ms). The detached script still writes
  // .active and runs the fresh crawl; eroSwitchReadback adopts the crawl result
  // over this preview when it lands. `sid` is already a slug (newsbar-add-source
  // slugs every id), so it maps 1:1 to the snapshot filename.
  FileView {
    id: eroSnapPreview
    property string sid: ""
    path: sid ? (root.home + "/.local/state/omarchy/eronews/" + sid + ".json") : ""
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (!eroSnapPreview.sid)
        return
      var v = Model.parseState(eroSnapPreview.text() || "")
      if (!v.headlines || !v.headlines.length)
        return
      var sig = Model.signature(v.headlines)
      if (sig === root.eroLastSignature)
        return
      root.eroLastSignature = sig
      root.eroHeadlines = Model.withAges(v.headlines, Date.now())
    }
  }

  Component.onCompleted: {
    ensureDirsProc.running = true
    hiddenProbe.running = true
    Qt.callLater(function() { feedsFile.reload() })
    Qt.callLater(function() { eroFeedsFile.reload() })
  }

  // ------------------------------------------------------------- open article
  function openHeadline(url) {
    guard.run("openHeadline", function() {
      var clean = String(url || "").trim()
      if (!/^https?:\/\//i.test(clean)) return
      // xdg-open -> default browser, normal window/tab (not private).
      Quickshell.execDetached(["xdg-open", clean])
    })
  }

  // A left-half title click reads the story/confession aloud through Piper
  // (eronews-read toggles: a second click on any title stops the current read).
  // Source-agnostic now — eronews-read + stories_fetch.py use the active
  // source's recipe to pull the full text.
  function readHeadline(url) {
    guard.run("readHeadline", function() {
      var clean = String(url || "").trim()
      if (!/^https?:\/\//i.test(clean)) return
      Quickshell.execDetached(["bash", root.eroReadScript, clean])
    })
  }

  // ------------------------------------------------------------- source switch
  property string eroPendingSource: ""
  property string eroFiredSource: ""
  property bool eroBurstActive: false

  function setSource(id) {
    if (!id || id === root.eroActiveId) return
    root.switcherOpen = false
    // Optimistic: flip the dropdown label now. eroFeedsFile's watch will
    // confirm it from disk a beat later (and self-correct if the id was bad).
    root.eroActiveId = id
    root.eroPendingSource = id
    // Paint the picked source's cached snapshot now, ahead of the subprocess.
    eroSnapPreview.sid = id
    eroSnapPreview.reload()
    // Leading edge fires the first pick of a burst at once (instant feel);
    // every later pick just moves eroPendingSource and pushes the settle
    // point out. When the burst goes quiet the trailing edge fires the final
    // pick once. Detached `newsbar-set-source` processes have no spawn-order
    // guarantee, so a naive fire-per-click could land on the wrong source.
    if (!root.eroBurstActive) {
      root.eroBurstActive = true
      root._fireSourceSwitch(id)
    }
    eroSwitchSettle.restart()
  }

  function _fireSourceSwitch(id) {
    root.eroFiredSource = id
    // newsbar-set-source (1) writes .active AND promotes this source's last
    // cached snapshot onto eronews.json — fast, no network — then (2) runs a
    // fresh crawl. The readback burst below surfaces the promoted snapshot the
    // instant it lands, then the crawl result, without waiting on the 45s
    // watch-gap poll.
    Quickshell.execDetached(["bash", root.setSourceScript, String(id)])
    eroSwitchReadback.restart()
  }

  Timer {
    id: eroSwitchSettle
    interval: 300
    repeat: false
    onTriggered: {
      if (root.eroPendingSource && root.eroPendingSource !== root.eroFiredSource)
        root._fireSourceSwitch(root.eroPendingSource)
      root.eroBurstActive = false
    }
  }

  // ~6s of 150ms store re-reads after a switch (see setSource). Cheap: an
  // unchanged file re-read is a no-op; it only fires onExternallyChanged when
  // the promoted snapshot / crawl result actually changes the text.
  Timer {
    id: eroSwitchReadback
    interval: 150
    repeat: true
    running: false
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      eroStore.reload()
      if (++ticks >= 40)
        running = false
    }
  }

  function submitAddSource(url, name) {
    var u = String(url || "").trim()
    if (!/^https?:\/\//i.test(u)) return
    root.addSourceOpen = false
    // The script does the NanoGPT derive + validate + append + refresh and
    // notify-sends the outcome; the config watch then updates the switcher.
    Quickshell.execDetached(["bash", root.addSourceScript, u, String(name || "").trim()])
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
        // Never restart a Process synchronously from inside its own exited
        // handler — Quickshell is mid-teardown and `running` can get stuck
        // true with no child, freezing the spinner. Defer to the next tick.
        Qt.callLater(root.runRefresh)
      }
    }
  }

  // Safety net: if a refresh Process is still "running" long after any real
  // fetch could have finished, force it down so a wedged handle self-heals.
  Timer {
    interval: 60000
    running: refreshProc.running
    onTriggered: {
      console.warn("newsbar: world-news refresh watchdog — forcing stop after 60s")
      refreshProc.running = false
      if (root.refreshPending) { root.refreshPending = false; Qt.callLater(root.runRefresh) }
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

  // ---- ero-news refresh loop (mirror of the above, own script + cadence) ----
  Process {
    id: eroRefreshProc
    running: false
    onRunningChanged: root.eroRefreshing = running
    onExited: {
      eroStore.reload()
      if (root.eroRefreshPending) {
        root.eroRefreshPending = false
        // See refreshProc: deferring the re-run is what stops the left-half
        // spinner wedging when a switch and the 3-min timer overlap.
        Qt.callLater(root.runEroRefresh)
      }
    }
  }

  Timer {
    interval: 60000
    running: eroRefreshProc.running
    onTriggered: {
      console.warn("newsbar: ero refresh watchdog — forcing stop after 60s")
      eroRefreshProc.running = false
      if (root.eroRefreshPending) { root.eroRefreshPending = false; Qt.callLater(root.runEroRefresh) }
    }
  }

  function runEroRefresh() {
    if (eroRefreshProc.running) {
      root.eroRefreshPending = true
      return
    }
    // --force: this path is the 3-min timer and explicit user refreshes only
    // (switches go through newsbar-set-source), so always crawl — don't let
    // stories_fetch's switch-dedup freshness check no-op a real refresh.
    eroRefreshProc.command = ["bash", root.eroRefreshScript, "--force"]
    eroRefreshProc.running = true
  }

  // One user-facing "refresh everything now": kicks both halves at once.
  // Wired to the bottom-right button and the refreshAll() IPC. Each side
  // coalesces its own re-entrancy (refreshPending / eroRefreshPending).
  function runAllRefresh() {
    root.runRefresh()
    root.runEroRefresh()
  }

  Timer {
    id: eroRefreshTimer
    interval: Math.max(2, root.eroRefreshMinutes) * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.runEroRefresh()
  }

  Timer {
    interval: 45 * 1000
    repeat: true
    running: root.eroHeadlines.length === 0
    onTriggered: eroFeedsFile.reload()
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

  // ero-news config: refreshMinutes + the source list + which is active.
  // bin/stories_fetch.py self-provisions the file (literotica + confessions)
  // and owns every recipe; this side only reads .active / .sources for the
  // switcher and re-refreshes when the file changes (e.g. after a switch).
  FileView {
    id: eroFeedsFile
    path: root.eroFeedsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: guard.run("eroFeedsFile.onLoaded", function() {
      var switched = false
      try {
        var j = JSON.parse(eroFeedsFile.text() || "{}")
        if (j && j.refreshMinutes) root.eroRefreshMinutes = Math.max(2, Number(j.refreshMinutes) || 3)
        if (j && Array.isArray(j.sources)) root.eroSources = j.sources
        if (j && j.active && j.active !== root.eroActiveId) {
          switched = root.eroActiveId !== ""   // a real switch, not first load
          root.eroActiveId = j.active
        }
      } catch (e) {
        console.warn("eronews: config parse failed:", e)
      }
      var firstLoad = !root.eroFeedsLoaded
      root.eroFeedsLoaded = true
      // Only crawl when there's a reason to: first load (stories_fetch.py may
      // not have written the state file yet) or the active source genuinely
      // changed. A bare re-read — a refreshMinutes edit, an unrelated field,
      // the watch firing twice on one atomic write — must NOT kick a fetch;
      // that was piling 2-3 concurrent listing crawls onto every switch.
      if (firstLoad || switched)
        root.runEroRefresh()
    })
    onLoadFailed: root.runEroRefresh()
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
      "own=no; top=no; ero=no; " +
      "[[ -f " + root.hiddenFlagPath + " ]] && own=yes; " +
      "[[ -f " + root.topBarFlagPath + " ]] && top=yes; " +
      "[[ -f " + root.eroHiddenFlagPath + " ]] && ero=yes; " +
      "echo \"$own $top $ero\""]
    stdout: SplitParser { onRead: function(line) {
      var p = String(line).trim().split(/\s+/)
      root.ownHidden = p[0] === "yes"
      root.topBarHidden = p[1] === "yes"
      root.eroHidden = p[2] === "yes"
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
  // strand this bar out of sync with the top one. A slower periodic re-probe
  // guarantees it catches up within 10 seconds without repeated process launches.
  Timer {
    interval: 10000
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
    function refreshAll(): void { root.runAllRefresh() }
    function reloadConfig(): void { feedsFile.reload() }
    function show(): void { root.setHidden(false) }
    function hide(): void { root.setHidden(true) }
    function toggle(): void { root.setHidden(!root.hidden) }

    // Hotkey: flip between the 50/50 split and news-fills-the-whole-bar
    // (stories half hidden).
    function cycleHalves(): void { root.cycleHalves() }
    function setEroHidden(hidden: bool): void { root.setEroHidden(hidden === true) }
    function halves(): string {
      return JSON.stringify({
        eroHidden: root.eroHidden,
        newsFullWidth: root.eroHidden,
        left: root.leftHalfShown
      })
    }

    // ero-news (left half)
    function refreshEro(): void { root.runEroRefresh() }
    function reloadEroConfig(): void { eroFeedsFile.reload() }
    function stopRead(): void { Quickshell.execDetached(["bash", root.eroReadScript]) }
    function setSource(id: string): void { root.setSource(id) }
    function addSource(url: string, name: string): void { root.submitAddSource(url, name) }
    function sources(): string {
      return guard.call("ipc.sources", function() {
        return JSON.stringify({ active: root.eroActiveId, sources: root.eroSources })
      }, "{}")
    }

    function status(): string {
      return guard.call("ipc.status", function() {
        return JSON.stringify({
          headlines: root.headlines.length,
          updatedAt: root.state.updatedAt,
          error: root.state.error,
          hidden: root.hidden,
          eroHidden: root.eroHidden,
          newsFullWidth: root.eroHidden,
          refreshing: root.refreshing,
          refreshMinutes: root.refreshMinutes,
          feedsPath: root.feedsPath,
          ero: {
            headlines: root.eroHeadlines.length,
            updatedAt: eroStore.value.updatedAt,
            error: eroStore.value.error,
            refreshing: root.eroRefreshing,
            refreshMinutes: root.eroRefreshMinutes,
            feedsPath: root.eroFeedsPath,
            activeSource: root.eroActiveId,
            sources: root.eroSources.map(function(s) { return s.id })
          }
        })
      }, "{}")
    }
  }

  // ------------------------------------------------------------- the bar(s)
  Variants {
    // internal laptop panel only — unused on the externals, and one
    // PanelWindow per screen multiplied the feed polling by the monitor count.
    model: Quickshell.screens.filter(function (s) { return s.name === "eDP-1" })

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

        // Both bottom surfaces use ExclusionMode.Auto; the compositor stacks
        // them edge-to-edge without reserving an empty margin below NewsBar.
        anchors { bottom: true; left: true; right: true }
        implicitHeight: root.barSize

        Rectangle {
          anchors.fill: parent
          color: _webPalette.barBackground

          // Hairline divider along the top edge, echoing the top bar's weight.
          Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1
            color: Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, 0.12)
          }

          // Middle-click anywhere on the bar forces an immediate refresh,
          // without waiting on IPC -- mirrors cliamp/score's own middle-click
          // bar shortcuts. MarqueeSegment's per-headline TapHandlers only
          // accept the left button, so this still receives the middle one.
          TapHandler {
            acceptedButtons: Qt.MiddleButton
            onTapped: root.runRefresh()
          }

          // Centre rule: newest Literotica stories on the left half, world
          // news on the right half.
          Rectangle {
            id: midRule
            width: 1
            visible: root.leftHalfShown
            anchors { top: parent.top; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
            color: Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, 0.18)
          }

          // ---- source switcher: bottom-left of the bar ------------------
          // Click -> a menu (popped above the bar) of every configured source
          // plus "＋ Add source…". Selecting one calls bin/newsbar-set-source;
          // Add opens the modal.
          Rectangle {
            id: switcher
            visible: root.leftHalfShown
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: switcherRow.implicitWidth + Style.space(16)
            color: switcherArea.containsMouse || root.switcherOpen
              ? Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, 0.10)
              : "transparent"
            Accessible.role: Accessible.Button
            Accessible.name: "Choose story source. Current source: " + root.eroActiveName
            Accessible.description: "Open the list of story sources."
            Accessible.focusable: true
            Accessible.onPressAction: root.switcherOpen = !root.switcherOpen

            Row {
              id: switcherRow
              anchors.centerIn: parent
              spacing: Style.space(4)
              Text {
                text: root.eroActiveName
                color: _webPalette.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                Accessible.ignored: true
              }
              Text {
                text: root.switcherOpen ? "⌃" : "⌄"
                color: _webPalette.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                Accessible.ignored: true
              }
            }

            MouseArea {
              id: switcherArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.switcherOpen = !root.switcherOpen
            }

            // The menu itself is a separate layer-shell overlay window
            // (switcherMenuLoader, below the add-source modal). It used to be an
            // inline Rectangle anchored above this bar (bottom: parent.top), but
            // wlr-layer-shell clips everything outside a surface's own geometry —
            // the bar surface is only `barSize` tall — so the popup was never
            // composited and its MouseAreas never saw a click ("nothing happens
            // when I pick a source"). Same reason the add-source modal is its
            // own PanelWindow.
          }

          MarqueeSegment {
            id: eroSeg
            visible: root.leftHalfShown
            anchors {
              left: switcher.right; top: parent.top; bottom: parent.bottom
              right: midRule.left
              leftMargin: Style.space(6); rightMargin: Style.space(4)
            }
            panelWindow: win
            hostHidden: root.hidden || !root.leftHalfShown
            headlines: root.eroHeadlines
            placeholder: root.eroPlaceholderText
            textColor: _webPalette.barForeground
            accentColor: _webPalette.barActive
            fontFamily: Style.font.family
            fontSize: Style.font.body
            onActivate: function(url) { root.readHeadline(url) }
          }

          MarqueeSegment {
            id: newsSeg
            anchors {
              right: refreshBtn.left; top: parent.top; bottom: parent.bottom
              // Split view: start at the centre rule. Stories hidden: span from
              // the far-left edge so the news crawl fills the whole bar.
              left: root.eroHidden ? parent.left : midRule.right
              leftMargin: root.eroHidden ? Style.space(8) : Style.space(4)
              rightMargin: Style.space(6)
            }
            panelWindow: win
            hostHidden: root.hidden
            headlines: root.headlines
            placeholder: root.placeholderText
            textColor: _webPalette.barForeground
            accentColor: _webPalette.barActive
            fontFamily: Style.font.family
            fontSize: Style.font.body
            onActivate: function(url) { root.openHeadline(url) }
          }

          // ---- refresh-all button: bottom-right of the bar -------------
          // Click -> refetch both halves now (world news + the story feed),
          // same as the refreshAll() IPC. The glyph spins while either fetch
          // is in flight and tints to the accent colour.
          Kit.ActionButton {
            id: refreshBtn
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            iconText: "↻"
            iconSize: Style.font.body + 2
            horizontalPadding: Style.space(8)
            verticalPadding: 0
            foreground: busy ? _webPalette.barActive : _webPalette.barForeground
            tooltipText: "Refresh both news feeds"
            focusable: true
            iconSpinning: busy
            readonly property bool busy: root.refreshing || root.eroRefreshing
            onClicked: root.runAllRefresh()
          }
        }
      }
    }
  }

  // ---------------------------------------------------- source switcher menu
  // Its own layer-shell overlay window, NOT an inline child of the bar: a popup
  // that extends above the bar can't live inside the bar surface (wlr-layer-
  // shell clips it away, MouseAreas included). Full-screen transparent catcher
  // closes on any outside click; the menu card sits just above the bottom bar,
  // left-aligned under the switcher button.
  LazyLoader {
    active: root.switcherOpen
    PanelWindow {
      id: switcherMenuWin
      visible: root.switcherOpen
      color: "transparent"
      surfaceFormat.opaque: false
      WlrLayershell.namespace: "omarchy-newsbar-switcher"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }

      Item {
        id: switcherKeyCatcher
        anchors.fill: parent
        focus: true
        Accessible.role: Accessible.Pane
        Accessible.name: "Story sources"
        Keys.onEscapePressed: root.switcherOpen = false

        function focusCurrentSource() {
          for (var i = 0; i < sourceRepeater.count; i++) {
            var candidate = sourceRepeater.itemAt(i)
            if (candidate && candidate.modelData.id === root.eroActiveId) {
              candidate.forceActiveFocus()
              return
            }
          }
          if (sourceRepeater.count > 0) sourceRepeater.itemAt(0).forceActiveFocus()
          else addSourceButton.forceActiveFocus()
        }

        Component.onCompleted: Qt.callLater(focusCurrentSource)
      }

      // click-away
      MouseArea {
        anchors.fill: parent
        onClicked: root.switcherOpen = false
      }

      Rectangle {
        id: switcherMenu
        width: Style.space(220)
        height: menuCol.implicitHeight + Style.space(10)
        anchors {
          left: parent.left
          bottom: parent.bottom
          leftMargin: Style.space(6)
          bottomMargin: root.barSize + Style.space(6)
        }
        color: _webPalette.barBackground
        border.width: 1
        border.color: Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, 0.25)
        radius: Style.cornerRadius !== undefined ? Style.cornerRadius : 6

        // swallow clicks inside the card so the click-away doesn't also fire
        MouseArea { anchors.fill: parent }

        Column {
          id: menuCol
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(5) }
          spacing: 1

          Repeater {
            id: sourceRepeater
            model: root.eroSources
            delegate: Kit.ActionButton {
              required property var modelData
              width: parent.width
              height: Style.space(28)
              focusable: true
              leftAlign: true
              active: modelData.id === root.eroActiveId
              selected: active
              text: ""
              foreground: _webPalette.barForeground
              horizontalPadding: Style.space(8)
              verticalPadding: 0
              Keys.onEscapePressed: root.switcherOpen = false
              Accessible.role: Accessible.RadioButton
              Accessible.name: modelData.name || modelData.id
              Accessible.description: modelData.id === root.eroActiveId ? "Current story source" : "Select story source"
              Accessible.checkable: true
              Accessible.checked: modelData.id === root.eroActiveId
              Accessible.onToggleAction: root.setSource(modelData.id)
              onClicked: root.setSource(modelData.id)

              MarqueeText {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                leftPadding: Style.space(8)
                text: (parent.active ? "● " : "  ") + (modelData.name || modelData.id)
                color: _webPalette.barForeground
                textFont.family: Style.font.family
                textFont.pixelSize: Style.font.body
                requestedElide: Text.ElideRight
                focusableOnOverflow: false
                active: parent.activeFocus
                Accessible.ignored: true
              }
            }
          }

          Rectangle {
            width: parent.width; height: 1
            color: Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, 0.15)
          }

          Rectangle {
            id: addSourceRow
            width: parent.width
            height: Style.space(28)
            color: "transparent"
            Kit.ActionButton {
              id: addSourceButton
              anchors.fill: parent
              focusable: true
              leftAlign: true
              text: "＋ Add source…"
              horizontalPadding: Style.space(8)
              verticalPadding: 0
              foreground: _webPalette.barTextColorFor(_webPalette.barActive)
              Keys.onEscapePressed: root.switcherOpen = false
              Accessible.name: "Add story source"
              onClicked: { root.switcherOpen = false; root.addSourceOpen = true }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------- add-source modal
  // A focused overlay window: paste a listing URL (+ optional name), Add runs
  // bin/newsbar-add-source, which asks NanoGPT once for a scrape recipe,
  // validates it against the page, and on success appends + activates the
  // source. The script notify-sends the outcome.
  LazyLoader {
    active: root.addSourceOpen
    PanelWindow {
      id: modalWin
      visible: root.addSourceOpen
      color: "transparent"
      surfaceFormat.opaque: false
      WlrLayershell.namespace: "omarchy-newsbar-addsource"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      anchors { top: true; bottom: true; left: true; right: true }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        MouseArea { anchors.fill: parent; onClicked: root.addSourceOpen = false }

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(40), Style.space(460))
          height: card.implicitHeight + Style.space(32)
          radius: Style.cornerRadius !== undefined ? Style.cornerRadius : 8
          color: _webPalette.barBackground
          border.width: 1
          border.color: Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, 0.25)
          // swallow clicks so the dim-area handler doesn't close it
          MouseArea { anchors.fill: parent }

          Column {
            id: card
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(16) }
            spacing: Style.space(10)

            Text {
              text: "Add a story source"
              color: _webPalette.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Paste a listing page URL. NanoGPT works out how to scrape it once; after that it's plain regex."
              color: _webPalette.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall !== undefined ? Style.font.bodySmall : 12
            }

            Rectangle {
              width: parent.width; height: Style.space(34); radius: 5
              color: Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, 0.08)
              border.width: 1
              border.color: urlInput.activeFocus
                ? _webPalette.barActive
                : Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, 0.2)
              TextInput {
                id: urlInput
                anchors { fill: parent; leftMargin: Style.space(10); rightMargin: Style.space(10) }
                Accessible.name: "Story listing URL"
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: _webPalette.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                selectByMouse: true
                onAccepted: nameInput.forceActiveFocus()
                Text {
                  anchors.fill: parent
                  verticalAlignment: Text.AlignVCenter
                  visible: urlInput.text.length === 0
                  text: "https://…"
                  color: _webPalette.barForeground
                  font: urlInput.font
                  Accessible.ignored: true
                }
              }
            }

            Rectangle {
              width: parent.width; height: Style.space(34); radius: 5
              color: Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, 0.08)
              border.width: 1
              border.color: nameInput.activeFocus
                ? _webPalette.barActive
                : Qt.rgba(_webPalette.barForeground.r, _webPalette.barForeground.g, _webPalette.barForeground.b, 0.2)
              TextInput {
                id: nameInput
                anchors { fill: parent; leftMargin: Style.space(10); rightMargin: Style.space(10) }
                Accessible.name: "Story source name (optional)"
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: _webPalette.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                selectByMouse: true
                onAccepted: root.submitAddSource(urlInput.text, nameInput.text)
                Text {
                  anchors.fill: parent
                  verticalAlignment: Text.AlignVCenter
                  visible: nameInput.text.length === 0
                  text: "name (optional)"
                  color: _webPalette.barForeground
                  font: nameInput.font
                  Accessible.ignored: true
                }
              }
            }

            Text {
              id: shortcutHint
              width: parent.width
              text: nameInput.activeFocus ? "Enter: add source  ·  Esc: cancel" : "Enter: next field  ·  Esc: cancel"
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: _webPalette.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)
              Kit.ActionButton {
                text: "Cancel"
                focusable: true
                bordered: true
                foreground: _webPalette.barForeground
                onClicked: root.addSourceOpen = false
              }
              Kit.ActionButton {
                text: "Add"
                focusable: true
                bordered: true
                enabled: /^https?:\/\//i.test(urlInput.text.trim())
                foreground: _webPalette.barBackground
                background: enabled ? _webPalette.barActive
                  : Qt.rgba(_webPalette.barActive.r, _webPalette.barActive.g, _webPalette.barActive.b, 0.3)
                Accessible.name: "Add story source"
                Accessible.description: enabled ? "Add the entered story listing URL" : "Enter a valid HTTP or HTTPS listing URL"
                onClicked: root.submitAddSource(urlInput.text, nameInput.text)
              }
            }
          }

          // focus the URL field when the modal opens; Esc closes.
          Connections {
            target: root
            function onAddSourceOpenChanged() {
              if (root.addSourceOpen) Qt.callLater(function() { urlInput.forceActiveFocus() })
            }
          }
          Keys.onEscapePressed: root.addSourceOpen = false
          focus: true
        }
      }
    }
  }
}
