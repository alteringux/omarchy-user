.pragma library

// Per-plugin catch-and-report guard, shared by every alteringux.* plugin.
//
// `.pragma library` means this file is ONE instance process-wide, shared across
// every plugin that imports it — so it holds no module-level plugin state.
// Each QML file makes its own bound guard with create():
//
//   import "../alteringux.kit" as Kit
//   readonly property var guard: Kit.BugGuard.create(
//     "alteringux.timers",
//     function (argv) { Quickshell.execDetached(argv) })
//
//   guard.run("addEntry", function () { ... })              // swallow on throw
//   guard.call("format", function () { return fmt(x) }, "") // binding-safe
//   onTriggered: guard.wrap("tick", function () { root.recompute() })()
//
// A thrown error in a wrapped block is logged, handed to
// `omarchy-plugin-bug-report --source guard` (which owns dedupe + the kill
// switch + launching the CLI agent), then swallowed so the widget keeps
// running.

var _reportCmd = "omarchy-plugin-bug-report"

// Returns a guard bound to one plugin id + exec function. No shared state
// between the objects create() hands back, so two plugins importing this same
// file can't stomp each other's identity the way the old configure() did.
function create(pluginId, execDetached) {
  var plugin = pluginId || "unknown.plugin"
  var exec = execDetached || null

  function report(context, err) {
    var message = (err && err.message) ? err.message : String(err)
    var stack = (err && err.stack) ? String(err.stack) : ""
    var summary = (context ? context + ": " : "") + message

    // Always leave a trace in the shell log even if the dispatch below fails.
    console.warn("[BugGuard " + plugin + "] " + summary + (stack ? ("\n" + stack) : ""))

    if (!exec) return
    try {
      exec([
        _reportCmd,
        "--plugin", plugin,
        "--source", "guard",
        "--summary", summary,
        "--message", "context: " + (context || "(none)") + "\nerror: " + message,
        "--stack", stack
      ])
    } catch (e2) {
      console.warn("[BugGuard " + plugin + "] failed to dispatch report: " + e2)
    }
  }

  // Immediately run fn(); on throw, report and return undefined.
  function run(context, fn) {
    try {
      return fn()
    } catch (e) {
      report(context, e)
      return undefined
    }
  }

  // Like run(), but returns `fallback` instead of undefined when fn() throws.
  // Use for property bindings that must still yield a sane value.
  function call(context, fn, fallback) {
    try {
      return fn()
    } catch (e) {
      report(context, e)
      return fallback
    }
  }

  // Returns a zero-arg function that runs fn() guarded. Handy for signal
  // handlers.
  function wrap(context, fn) {
    return function () {
      return run(context, fn)
    }
  }

  return { run: run, call: call, wrap: wrap, report: report }
}
