import QtQuick
import Quickshell
import Quickshell.Io

// ─────────────────────────────────────────────────────────────────────────────
// Store — one JSON file on disk, loaded into `value`, written back on `save()`.
//
// Every alteringux.* bar widget keeps its data in a small JSON file under
// ~/.local/state/omarchy/ and had, copied into it by hand, the same cluster of
// parts: a FileView, an "am I loaded yet" flag, a 200 ms debounce Timer, a
// `mkdir -p` Process, and load / flush / scheduleSave helpers — once for the
// live state, again for the history log, sometimes a third time for config.
// This component is that cluster, written once.
//
// ── What the host provides ──────────────────────────────────────────────────
//   fileName   the file's basename, e.g. "timers.json"            (required)
//   parse      raw file text  ->  a value object                  (required)
//   serialize  a value object ->  file text   (defaults to pretty JSON)
//
// `parse` must be TOTAL: given "" (missing / empty / unreadable file) or
// garbage it must return a sane default, never throw. The plugins' Model.js
// `parseState` / `parseHistory` already work exactly like this, so the host
// just points `parse` at one of them.
//
// ── What the host reads ─────────────────────────────────────────────────────
//   value    the parsed object. Assign a new object to it to mutate, then
//            call save(). (Mutating in place works too, but a fresh object is
//            what makes QML bindings on `value` re-evaluate.)
//   loaded   false until the first read of the file has completed. Guard
//            mutations with it so a save during startup can't clobber a real
//            file with an empty default.
//
// ── Watch mode (file written by someone else) ──────────────────────────────
// Set `watch: true` when a `bin/` refresh script, the user's editor, or
// another process owns the writes. The Store keeps re-reading + re-parsing
// into `value` as the file changes on disk, and emits `externallyChanged(value)` after
// any read whose text differs from the last one adopted (including the first).
//   pollMs   > 0 also reload()s on that cadence while `polling` — covers
//            FileView's watch-on-create blind spot (a file created/recreated
//            after the widget was built keeps a dead inode watch, so
//            onFileChanged never fires). Bind `polling` to when you still need
//            to catch a (re)appear, e.g. `!root.active`; default true.
// `save()` still works for a file that is both externally and plugin-written;
// a reload triggered by the Store's own write re-reads identical text, so it
// does not re-emit `changed`.
//
// ── Typical wiring ─────────────────────────────────────────────────────────
//   import "../alteringux.kit" as Kit
//
//   Kit.Store {
//     id: stateStore
//     fileName: "timers.json"
//     parse: function (raw) { return Model.parseState(raw) }
//   }
//
//   property alias state: stateStore.value
//   readonly property bool stateLoaded: stateStore.loaded
//
//   function addEntry(label) {
//     state = Model.addEntry(state, label)   // new object -> bindings update
//     stateStore.save()                      // debounced write-back
//   }
// ─────────────────────────────────────────────────────────────────────────────
Item {
  id: store

  // ── configuration ────────────────────────────────────────────────────────

  // State lives outside the plugin's own source tree on purpose: that tree is
  // watched by the shell's plugin-file watcher, and rewriting a file in it on
  // every add/remove would trigger a "local plugin changed" reload and tear
  // down an open panel. ~/.local/state/omarchy/ is the shared convention.
  property string dir: Quickshell.env("HOME") + "/.local/state/omarchy/"
  property string fileName: ""

  // raw text -> value object. Must not throw. See the note above.
  property var parse: function (raw) {
    try { return (raw && raw.length) ? JSON.parse(raw) : {} } catch (e) { return {} }
  }

  // value object -> text. Trailing newline so the file is a tidy POSIX text
  // file and diffs cleanly.
  property var serialize: function (value) {
    return JSON.stringify(value, null, 2) + "\n"
  }

  // save() coalesces a burst of mutations into one write this many ms after
  // the last one. Matches the hand-rolled timers the plugins used.
  property int debounceMs: 200

  // When true, if the file does not exist at first load, write the serialized
  // default straight away — so there is a file on disk for the user to
  // hand-edit (score-config.json / pomodoro-config.json rely on this). Off by
  // default: timers/countdown only want a file once there's real data in it.
  property bool seedOnCreate: false

  // Watch mode: keep re-reading a file written by someone else. See the header.
  property bool watch: false
  property int pollMs: 0
  property bool polling: true

  // ── observable state ─────────────────────────────────────────────────────

  property var value: undefined
  property bool loaded: false

  readonly property string path: dir + fileName

  // Emitted after a read (initial or watched) whose file text differs from the
  // text last adopted. Carries the freshly-parsed `value`. Only meaningful with
  // `watch: true`, though it fires for the first read either way.
  signal externallyChanged(var value)

  // Emitted if writing the file fails (disk full, permissions). The host can
  // surface it; by default it is only logged.
  signal saveFailed(string message)

  // ── lifecycle ────────────────────────────────────────────────────────────

  Component.onCompleted: {
    // A sane starting value before the first read lands, using the host's own
    // parser so `value` has the right shape from frame one.
    value = parse("")
    ensureDirProc.running = true
    // Read after a tick so the mkdir has a chance to run first; FileView also
    // copes fine if the file simply isn't there yet (onLoadFailed).
    Qt.callLater(view.reload)
  }

  // Force a re-read from disk. Rarely needed — the host owns this file.
  function reload() {
    view.reload()
  }

  // Debounced write-back. Safe to call on every mutation. No-ops until the
  // first read has completed, so startup churn can't overwrite real data.
  function save() {
    if (!loaded) return
    debounce.restart()
  }

  // Write immediately, skipping the debounce (e.g. on teardown). Prefer save().
  function flush() {
    if (!loaded) return
    try {
      var txt = serialize(value)
      _lastRaw = txt        // so the watch-mode reload of our own write is a no-op
      view.setText(txt)
    } catch (e) {
      console.warn("[kit/Store " + fileName + "] save failed: " + e)
      store.saveFailed(String(e))
    }
  }

  // ── internals ────────────────────────────────────────────────────────────

  // Text of the last read (or write) adopted. Sentinel until the first read so
  // that read always counts as a change.
  property string _lastRaw: " "

  function _adopt(raw) {
    var isChange = (raw !== _lastRaw)
    _lastRaw = raw
    value = parse(raw)
    loaded = true
    if (isChange) store.externallyChanged(value)
  }

  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", store.dir]
    running: false
  }

  FileView {
    id: view
    path: store.path
    watchChanges: store.watch   // off unless the host asked to track outside writes
    atomicWrites: true          // temp file + rename, so a crash mid-write never
                                // leaves a truncated file on disk
    printErrors: false          // a missing file on first run is normal, not an error
    onLoaded: store._adopt(text())
    onLoadFailed: {
      store._adopt("")               // missing / unreadable -> parse("") default
      if (store.seedOnCreate) store.flush()   // ...but leave a template on disk
    }
    // watchChanges only fires the signal; it does not re-read on its own.
    onFileChanged: view.reload()
  }

  // Idle re-read for watch mode: catches a file created/recreated after this
  // widget was built, which FileView's inode watch misses.
  Timer {
    id: watchPoll
    interval: Math.max(200, store.pollMs)
    repeat: true
    running: store.watch && store.pollMs > 0 && store.polling
    onTriggered: view.reload()
  }

  Timer {
    id: debounce
    interval: store.debounceMs
    repeat: false
    onTriggered: store.flush()
  }
}
