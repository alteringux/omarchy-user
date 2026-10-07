import QtQuick
import Quickshell
import "UsageModel.js" as UsageModel

// Kit.Usage — per-plugin usage analytics + adaptive-UI signal.
//
// Drop one into a bar widget, give it `pluginId`, and call record() from
// every user action. It keeps a small JSON file
// (`$XDG_STATE_HOME/omarchy/usage/<pluginId>.json`, falling back to
// `~/.local/state/omarchy/usage/`) with per-action counts, a last-used stamp,
// and a capped recency ring, and exposes ranking / dead-feature helpers so a
// panel can reorder chips, demote unused controls, and pick smart defaults
// WITHOUT any code change.
//
//   import "../alteringux.kit" as Kit
//
//   Kit.Usage { id: usage; pluginId: "alteringux.timers" }
//
//   function addEntry(l) { ...; usage.record("add") }
//   // panel:
//   model:   usage.rankActions(["add", "rename", "remove", "clear"])   // most-used first
//   visible: !usage.isActionDead("clear")
//
// Reads are total and safe before the file loads (they see an empty doc).
// record() no-ops until loaded so startup churn can't clobber real data.
// Built on the same Kit.Store the rest of the kit uses; the JSON lives
// outside the plugin source tree so a write never trips the shell's
// plugin-file watcher.
Item {
  id: usage

  // Required. Names the state file and scopes the analytics to one plugin.
  property string pluginId: ""

  readonly property bool loaded: store.loaded

  // record() assigns a fresh object to store.value, so `doc` changes identity
  // and any binding that called rankActions()/actionScore()/isActionDead() (which read
  // `doc`) re-evaluates. `revision` is a coarser change signal for callers
  // that don't touch `doc` directly.
  property int revision: 0

  readonly property var doc: store.value ? store.value : UsageModel.defaultDoc()

  // Fired after a use is persisted, with the action name. Handy for a host
  // that wants to react (re-sort a bar, refresh a hint) beyond binding
  // re-evaluation.
  signal recorded(string action)

  // ── persistence ─────────────────────────────────────────────────────────
  // Store owns the FileView, atomic write, `mkdir -p` of the usage/ subdir,
  // and the save debounce. parse() is total (see UsageModel).
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
    || ((Quickshell.env("HOME") || "") + "/.local/state")

  // The writer re-reads and merges under a per-file flock, so duplicate
  // hosted instances cannot overwrite each other's action counts.
  readonly property string writerPath: Quickshell.env("HOME") + "/.local/bin/omarchy-usage-record"
  Store {
    id: store
    dir: usage.stateHome + (usage.stateHome.endsWith("/") ? "" : "/") + "omarchy/usage/"
    fileName: usage.pluginId ? (usage.pluginId + ".json") : "unknown.plugin.json"
    parse: function (raw) { return UsageModel.parse(raw) }
  }

  // ── write ───────────────────────────────────────────────────────────────
  function record(action) {
    if (!store.loaded || !usage.pluginId) return
    var name = String(action || "")
    if (!name.trim().length) return
    var now = Date.now()
    store.value = UsageModel.record(store.value, name, now)
    Quickshell.execDetached([usage.writerPath, store.path, name, String(now)])
    usage.revision++
    usage.recorded(name)
  }

  // ── read (all pure, all total, all safe pre-load) ──────────────────────
  function count(action) {
    var a = usage.doc.actions[String(action || "")]
    return a ? a.count : 0
  }
  function lastAt(action) {
    var a = usage.doc.actions[String(action || "")]
    return a ? a.lastAt : 0
  }
  function actionScore(action) { return UsageModel.score(usage.doc, action, Date.now()) }
  function rankActions(subset) { return UsageModel.rank(usage.doc, subset || null, Date.now()) }
  // Aggregate activity without requiring callers to know the on-disk schema.
  // This is read-only and never records bar construction or other passive use.
  function pluginSummary() { return UsageModel.pluginSummary(usage.doc, Date.now()) }
  function topActions(n)       { return UsageModel.top(usage.doc, n || 0, Date.now()) }
  function isActionDead(action){ return UsageModel.isDead(usage.doc, action, Date.now()) }
}
