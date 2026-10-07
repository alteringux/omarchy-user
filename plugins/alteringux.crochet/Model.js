// Pure logic for the alteringux.crochet plugin: parse the status doc written
// by ~/.local/bin/omarchy-crochet (crochet-index.json) and its `list` output.
// No QML APIs so it stays plain and testable.

function parseIndex(raw) {
  var empty = { updatedAt: "", previewUrl: "", projectPath: "", lastRun: null, tests: null }
  if (!raw || raw.length === 0) return empty
  try {
    var o = typeof raw === "string" ? JSON.parse(raw) : raw
    if (!o || typeof o !== "object") return empty

    var lastRun = null
    if (o.lastRun && typeof o.lastRun === "object") {
      lastRun = {
        pattern: String(o.lastRun.pattern || ""),
        ok: o.lastRun.ok === true,
        error: o.lastRun.error || null,
        stitches: (o.lastRun.stitches === null || o.lastRun.stitches === undefined) ? null : Number(o.lastRun.stitches),
        rows: (o.lastRun.rows === null || o.lastRun.rows === undefined) ? null : Number(o.lastRun.rows),
        finalRowWidth: (o.lastRun.finalRowWidth === null || o.lastRun.finalRowWidth === undefined) ? null : Number(o.lastRun.finalRowWidth),
        svgPath: o.lastRun.svgPath || null,
        stitchPath: o.lastRun.stitchPath || null,
        at: o.lastRun.at || ""
      }
    }

    var tests = null
    if (o.tests && typeof o.tests === "object") {
      tests = {
        total: (o.tests.total === null || o.tests.total === undefined) ? null : Number(o.tests.total),
        passed: (o.tests.passed === null || o.tests.passed === undefined) ? null : Number(o.tests.passed),
        failed: Number(o.tests.failed) || 0,
        ok: o.tests.ok === true,
        at: o.tests.at || ""
      }
    }

    return {
      updatedAt: String(o.updatedAt || ""),
      previewUrl: String(o.previewUrl || ""),
      projectPath: String(o.projectPath || ""),
      lastRun: lastRun,
      tests: tests
    }
  } catch (e) {
    return empty
  }
}

// newline-separated `omarchy-crochet list` output -> array of names
function parsePatternList(raw) {
  if (!raw) return []
  return raw.split("\n").map(function (s) { return s.trim() }).filter(function (s) { return s.length > 0 })
}

if (typeof module !== "undefined") {
  module.exports = {
    parseIndex: parseIndex,
    parsePatternList: parsePatternList
  }
}
