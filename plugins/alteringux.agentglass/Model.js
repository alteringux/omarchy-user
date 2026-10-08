function emptyState() {
  return {
    version: 1,
    updatedAt: 0,
    reachable: false,
    stale: true,
    error: "agentglass is not running",
    workspace: "",
    workspaceCount: 0,
    scanning: false,
    projectCount: 0,
    resources: null,
    services: null,
    servicesError: "",
    managedRuns: [],
    managedRunsOmitted: 0,
    managedRunsError: "",
    agentKinds: [],
    agentKindsError: "",
    spend: null,
    counts: { total: 0, working: 0, waiting: 0 },
    agents: []
  }
}

function text(value, fallback) {
  return typeof value === "string" ? value : fallback
}

function number(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function parseState(raw) {
  var d = emptyState()
  var parsed
  try { parsed = typeof raw === "string" && raw.length ? JSON.parse(raw) : raw } catch (e) { return d }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return d
  var counts = parsed.counts && typeof parsed.counts === "object" ? parsed.counts : {}
  var agents = Array.isArray(parsed.agents) ? parsed.agents : []
  var expired = !parsed.updatedAt || Date.now() - number(parsed.updatedAt, 0) > 30000
  return {
    version: 1,
    updatedAt: number(parsed.updatedAt, 0),
    reachable: parsed.reachable === true,
    stale: parsed.stale !== false || expired,
    error: text(parsed.error, ""),
    workspace: text(parsed.workspace, ""),
    workspaceCount: Math.max(0, number(parsed.workspaceCount, 0)),
    scanning: parsed.scanning === true,
    projectCount: Math.max(0, number(parsed.projectCount, 0)),
    resources: parsed.resources && typeof parsed.resources === "object" ? parsed.resources : null,
    services: parsed.services && typeof parsed.services === "object" ? parsed.services : null,
    servicesError: text(parsed.servicesError, ""),
    managedRuns: Array.isArray(parsed.managedRuns) ? parsed.managedRuns.slice(0, 12) : [],
    managedRunsOmitted: Math.max(0, number(parsed.managedRunsOmitted, 0)),
    managedRunsError: text(parsed.managedRunsError, ""),
    agentKinds: Array.isArray(parsed.agentKinds) ? parsed.agentKinds.slice(0, 12) : [],
    agentKindsError: text(parsed.agentKindsError, ""),
    spend: parsed.spend && typeof parsed.spend === "object" ? parsed.spend : null,
    counts: {
      total: Math.max(0, number(counts.total, 0)),
      working: Math.max(0, number(counts.working, 0)),
      waiting: Math.max(0, number(counts.waiting, 0))
    },
    agents: agents.slice(0, 12)
  }
}

function isStale(state, nowMs) {
  return !state || state.stale || !state.updatedAt || nowMs - state.updatedAt > 30000
}

function barLabel(state, nowMs) {
  var c = (state && state.counts) || {}
  if (!state || !state.reachable || isStale(state, number(nowMs, Date.now()))) return "!"
  return String(Math.max(0, Number(c.working) || 0)) + "/" + String(Math.max(0, Number(c.waiting) || 0))
}

function ageLabel(updatedAt, nowMs) {
  if (!updatedAt) return "no reading"
  var seconds = Math.max(0, Math.round((nowMs - updatedAt) / 1000))
  if (seconds < 60) return "just now"
  if (seconds < 3600) return Math.floor(seconds / 60) + "m ago"
  return Math.floor(seconds / 3600) + "h ago"
}

function resourceLabel(row) {
  var cpu = Number(row && row.cpu)
  var hasCpu = row && row.cpu !== null && row.cpu !== undefined && isFinite(cpu)
  var rss = number(row && row.rss, 0)
  return String(row && row.pid || "?") + " ← " + String(row && row.ppid || "?") +
    " · " + text(row && row.comm, "unknown") + " · CPU " +
    (hasCpu ? cpu.toFixed(1) + "%" : "sampling") + " · RSS " +
    (rss / 1048576).toFixed(0) + " MiB"
}

function pathLabel(path, home) {
  if (typeof path !== "string" || !path) return "working directory unknown"
  if (typeof home === "string" && home && (path === home || path.indexOf(home + "/") === 0))
    return "in ~" + path.slice(home.length)
  return "in " + path
}

function serviceLabel(row) {
  var label = ":" + String(row && row.port || "?") + " · " + text(row && row.proc, "unknown process") +
    (row && row.pid ? " · pid " + row.pid : "") + " · " + text(row && row.addr, "unknown address")
  if (row && row.publicBind) label += " · PUBLIC"
  if (row && row.fromAgent) label += " · agent ancestry"
  if (row && row.cwdGone) label += " · directory missing"
  if (row && row.duplicate) label += " · duplicate listener"
  if (row && row.tmpLeftover) label += " · temporary directory"
  return label
}

function userServiceLabel(row) {
  return text(row && row.unit, "unknown.service") + " · " + text(row && row.active, "unknown") +
    "/" + text(row && row.sub, "unknown") + (row && row.description ? " · " + row.description : "")
}

function managedRunLabel(row) {
  var name = text(row && row.name, "managed workflow").replace(/^Agentglass workflow: /, "")
  var cpu = row && row.cpuUsageNs !== null && row.cpuUsageNs !== undefined
    ? (number(row.cpuUsageNs, 0) / 1e9).toFixed(1) + "s CPU" : "CPU unavailable"
  var memory = row && row.memoryCurrent !== null && row.memoryCurrent !== undefined
    ? (number(row.memoryCurrent, 0) / 1048576).toFixed(0) + "/" +
      (row.memoryPeak !== null && row.memoryPeak !== undefined ? (number(row.memoryPeak, 0) / 1048576).toFixed(0) : "?") + " MiB current/peak"
    : "memory unavailable"
  return name + " · " + text(row && row.active, "unknown") + "/" + text(row && row.sub, "unknown") + " · " + cpu + " · " + memory
}

try {
  module.exports = { emptyState, parseState, barLabel, ageLabel, isStale, resourceLabel, pathLabel, serviceLabel, userServiceLabel, managedRunLabel }
} catch (e) {}
