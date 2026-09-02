// Pure logic for the alteringux.flow plugin — a surface for "Omarchy Flows".
//
// The runner is ~/Work/bin/flow (Node). This plugin only *reads* two JSON
// files it produces / consumes and lays out a node canvas:
//   ~/.config/omarchy/flows/<id>.json          the flow document (also editable here)
//   ~/.local/state/omarchy/flows/<id>.json     the last run: node status + envelopes
//
// Kept free of QML/Quickshell APIs so it can be `node`-tested in isolation —
// same convention as every other alteringux.* plugin's Model.js.

var NODE_W = 150;
var NODE_H = 64;
var GRID = 20;

function parseDoc(raw) {
  var doc;
  try {
    doc = raw && raw.length ? JSON.parse(raw) : null;
  } catch (e) {
    return { ok: false, id: "", title: "", nodes: [], error: "invalid JSON" };
  }
  if (!doc || typeof doc !== "object" || Array.isArray(doc)) {
    return { ok: false, id: "", title: "", nodes: [], error: "not a flow object" };
  }
  var rawNodes = Array.isArray(doc.nodes) ? doc.nodes : [];
  var nodes = [];
  for (var i = 0; i < rawNodes.length; i++) {
    var n = rawNodes[i] || {};
    var ui = n.ui && typeof n.ui === "object" ? n.ui : {};
    var fallbackId = "node" + (i + 1);
    // Keep EVERY original field (op, key, mode, meta, system, timeoutSec, …) so
    // a canvas edit round-trips losslessly — only the drawing-derived keys
    // (x/y/label) and the normalised in/edges are overlaid.
    var node = {};
    for (var k in n) if (n.hasOwnProperty(k)) node[k] = n[k];
    node.id = typeof n.id === "string" && n.id ? n.id : fallbackId;
    node.type = typeof n.type === "string" ? n.type : "";
    node.in = normList(n.in);
    node.edges = n.edges && typeof n.edges === "object" ? n.edges : {};
    node.agent = !!n.agent;
    node.prompt = typeof n.prompt === "string" ? n.prompt : "";
    node.cmd = typeof n.cmd === "string" ? n.cmd : "";
    node.jq = typeof n.jq === "string" ? n.jq : "";
    node.shape = typeof n.shape === "string" ? n.shape : "";
    node.label = typeof n.label === "string" && n.label ? n.label : node.id;
    node.x = isFiniteNum(ui.x) ? ui.x : 40 + (i % 5) * (NODE_W + 40);
    node.y = isFiniteNum(ui.y) ? ui.y : 40 + Math.floor(i / 5) * (NODE_H + 40);
    nodes.push(node);
  }
  return {
    ok: true,
    id: typeof doc.id === "string" ? doc.id : "",
    title: typeof doc.title === "string" ? doc.title : "",
    nodes: nodes,
    error: ""
  };
}

function normList(v) {
  if (Array.isArray(v)) {
    var out = [];
    for (var i = 0; i < v.length; i++) if (typeof v[i] === "string" && v[i]) out.push(v[i]);
    return out;
  }
  return typeof v === "string" && v ? [v] : [];
}
function isFiniteNum(n) {
  return typeof n === "number" && isFinite(n);
}

function parseRunState(raw) {
  var rs;
  try {
    rs = raw && raw.length ? JSON.parse(raw) : null;
  } catch (e) {
    return { ok: false, nodes: {}, envelopes: [], order: [], error: "invalid JSON" };
  }
  if (!rs || typeof rs !== "object") {
    return { ok: false, nodes: {}, envelopes: [], order: [], error: "" };
  }
  return {
    ok: true,
    nodes: rs.nodes && typeof rs.nodes === "object" ? rs.nodes : {},
    envelopes: Array.isArray(rs.envelopes) ? rs.envelopes : [],
    order: Array.isArray(rs.order) ? rs.order : [],
    error: typeof rs.error === "string" ? rs.error : "",
    finishedAt: typeof rs.finishedAt === "string" ? rs.finishedAt : ""
  };
}

// -> "positive" | "negative" | "warning" | "faint" | "" (unknown / not run)
function statusRole(status) {
  if (status === "ok") return "positive";
  if (status === "error") return "negative";
  if (status === "skipped") return "warning";
  return "faint";
}

// Every drawable edge as {fromId,toId,kind}. `in` edges are solid data flow;
// a route's `edges` map adds dashed "gates".
function edgeList(doc) {
  var have = {};
  for (var i = 0; i < doc.nodes.length; i++) have[doc.nodes[i].id] = true;
  var out = [];
  for (var n = 0; n < doc.nodes.length; n++) {
    var node = doc.nodes[n];
    for (var j = 0; j < node.in.length; j++) {
      if (have[node.in[j]]) out.push({ fromId: node.in[j], toId: node.id, kind: "data" });
    }
    if (node.type === "route") {
      for (var label in node.edges) {
        var targets = node.edges[label];
        if (!Array.isArray(targets)) continue;
        for (var t = 0; t < targets.length; t++) {
          if (have[targets[t]]) out.push({ fromId: node.id, toId: targets[t], kind: "gate", label: label });
        }
      }
    }
  }
  return out;
}

function nodeById(doc, id) {
  for (var i = 0; i < doc.nodes.length; i++) if (doc.nodes[i].id === id) return doc.nodes[i];
  return null;
}

// content size for the scrollable canvas
function bounds(doc) {
  var w = 400, h = 300;
  for (var i = 0; i < doc.nodes.length; i++) {
    w = Math.max(w, doc.nodes[i].x + NODE_W + 60);
    h = Math.max(h, doc.nodes[i].y + NODE_H + 60);
  }
  return { w: w, h: h };
}

// return a NEW doc-shaped object (parsed form) with one node moved, snapped to
// the grid. The caller serialises it back via serializeDoc().
function moveNode(doc, id, x, y) {
  var copy = cloneDoc(doc);
  var nd = nodeById(copy, id);
  if (nd) {
    nd.x = Math.max(0, Math.round(x / GRID) * GRID);
    nd.y = Math.max(0, Math.round(y / GRID) * GRID);
  }
  return copy;
}

function setField(doc, id, key, value) {
  var copy = cloneDoc(doc);
  var nd = nodeById(copy, id);
  if (nd) nd[key] = value;
  return copy;
}

// append a fresh node of `type` at a free-ish spot; returns {doc, id}
function addNode(doc, type) {
  var copy = cloneDoc(doc);
  var n = copy.nodes.length;
  var base = type || "prompt";
  var id = base;
  var i = 1;
  while (nodeById(copy, id)) id = base + ++i;
  copy.nodes.push({
    id: id,
    type: base,
    in: [],
    x: 40 + (n % 5) * (NODE_W + 40),
    y: 40 + Math.floor(n / 5) * (NODE_H + 40),
    label: id,
    prompt: "",
    cmd: "",
    jq: "",
    shape: base === "view" ? "markdown" : "",
    agent: false,
    edges: {}
  });
  return { doc: copy, id: id };
}

function removeNode(doc, id) {
  var copy = cloneDoc(doc);
  var kept = [];
  for (var i = 0; i < copy.nodes.length; i++) {
    var nd = copy.nodes[i];
    if (nd.id === id) continue;
    var ins = [];
    for (var j = 0; j < nd.in.length; j++) if (nd.in[j] !== id) ins.push(nd.in[j]);
    nd.in = ins;
    for (var label in nd.edges) {
      if (!Array.isArray(nd.edges[label])) continue;
      var t = [];
      for (var k = 0; k < nd.edges[label].length; k++) if (nd.edges[label][k] !== id) t.push(nd.edges[label][k]);
      nd.edges[label] = t;
    }
    kept.push(nd);
  }
  copy.nodes = kept;
  return copy;
}

// toggle an `in` edge from -> to (used by drag-to-connect on the canvas)
function toggleEdge(doc, fromId, toId) {
  var copy = cloneDoc(doc);
  if (fromId === toId) return copy;
  var nd = nodeById(copy, toId);
  if (!nd || !nodeById(copy, fromId)) return copy;
  var at = nd.in.indexOf(fromId);
  if (at >= 0) nd.in.splice(at, 1);
  else nd.in.push(fromId);
  return copy;
}

function cloneDoc(doc) {
  return JSON.parse(JSON.stringify(doc));
}

// parsed doc -> the on-disk JSON text. Preserves every field the node came in
// with (op, key, mode, meta, system, …); only rewrites the drawing-derived
// keys and drops empties the parser had defaulted in.
function serializeDoc(doc) {
  var out = { id: doc.id, title: doc.title, nodes: [] };
  var DERIVED = { x: 1, y: 1, label: 1, ui: 1 };
  for (var i = 0; i < doc.nodes.length; i++) {
    var n = doc.nodes[i];
    var o = {};
    for (var k in n) {
      if (!n.hasOwnProperty(k) || DERIVED[k]) continue;
      var v = n[k];
      // drop the parser's empty defaults so the file stays sparse
      if ((k === "prompt" || k === "cmd" || k === "jq" || k === "shape") && v === "") continue;
      if (k === "agent" && !v) continue;
      if (k === "in" && (!v || !v.length)) continue;
      if (k === "edges" && (!v || !Object.keys(v).length)) continue;
      o[k] = v;
    }
    if (n.in && n.in.length) o.in = n.in.slice();
    if (n.label && n.label !== n.id) o.label = n.label;
    o.ui = { x: n.x, y: n.y };
    out.nodes.push(o);
  }
  return JSON.stringify(out, null, 2) + "\n";
}

// ---- envelope -> plain text -------------------------------------------------
// The panel draws every shape as monospace text (robust; no nested layouts).
// Same look as `flow view` in the terminal.
function pad(s, n) {
  s = String(s == null ? "" : s);
  while (s.length < n) s += " ";
  return s;
}
function padLeft(s, n) {
  s = String(s == null ? "" : s);
  while (s.length < n) s = " " + s;
  return s;
}

function renderSeriesText(data) {
  var labels = (data && data.labels) || [];
  var values = (data && data.values) || [];
  if (!values.length) return "(no data)";
  var w = 1;
  for (var i = 0; i < labels.length; i++) w = Math.max(w, String(labels[i]).length);
  var max = 1;
  for (i = 0; i < values.length; i++) max = Math.max(max, values[i]);
  var barW = 24;
  var out = [];
  for (i = 0; i < values.length; i++) {
    var v = values[i] || 0;
    var fill = Math.max(0, Math.round((v / max) * barW));
    var bar = "";
    for (var b = 0; b < fill; b++) bar += "█";
    out.push(pad(labels[i] !== undefined ? labels[i] : i + 1, w) + "  " + padLeft(v, 4) + "  " + bar);
  }
  out.push(pad("", w) + "        " + sparkCells(values));
  return out.join("\n");
}

function renderTableText(data) {
  var cols = (data && data.columns) || [];
  var rows = (data && data.rows) || [];
  if (!cols.length) return "(empty table)";
  var widths = [];
  for (var c = 0; c < cols.length; c++) {
    var mx = String(cols[c]).length;
    for (var r = 0; r < rows.length; r++) mx = Math.max(mx, String(rows[r][c] == null ? "" : rows[r][c]).length);
    widths.push(Math.max(3, mx));
  }
  function line(cells) {
    var s = "";
    for (var i = 0; i < widths.length; i++) s += (i ? "  " : "") + pad(cells[i], widths[i]);
    return s;
  }
  var out = [line(cols)];
  var sep = [];
  for (c = 0; c < widths.length; c++) {
    var d = "";
    for (var k = 0; k < widths[c]; k++) d += "─";
    sep.push(d);
  }
  out.push(line(sep));
  for (r = 0; r < rows.length; r++) out.push(line(rows[r]));
  return out.join("\n");
}

function renderEnvelopeText(env) {
  if (!env) return "";
  if (env.shape === "series") return renderSeriesText(env.data);
  if (env.shape === "table") return renderTableText(env.data);
  if (env.shape === "log") return (Array.isArray(env.data) ? env.data : []).join("\n");
  if (env.shape === "image") return "[image] " + (env.data && env.data.path ? env.data.path : "");
  return String(env.data == null ? "" : env.data);
}

var SPARK = "▁▂▃▄▅▆▇█";
function sparkCells(values) {
  if (!values || !values.length) return "";
  var max = Math.max.apply(null, values);
  var min = Math.min.apply(null, values.concat([0]));
  var span = max - min || 1;
  var s = "";
  for (var i = 0; i < values.length; i++) {
    var idx = Math.round(((values[i] - min) / span) * (SPARK.length - 1));
    if (idx < 0) idx = 0;
    if (idx > SPARK.length - 1) idx = SPARK.length - 1;
    s += SPARK.charAt(idx);
  }
  return s;
}

// short one-line summary for the bar label from the run state
function barSummary(runState) {
  var envs = runState.envelopes || [];
  for (var i = 0; i < envs.length; i++) {
    if (envs[i].shape === "series" && envs[i].data && envs[i].data.values) {
      return sparkCells(envs[i].data.values);
    }
  }
  var ok = 0, bad = 0;
  for (var k in runState.nodes) {
    if (runState.nodes[k].status === "ok") ok++;
    else if (runState.nodes[k].status === "error") bad++;
  }
  return bad ? ok + "✓ " + bad + "✗" : ok + "✓";
}

var api = {
  NODE_W: NODE_W,
  NODE_H: NODE_H,
  GRID: GRID,
  parseDoc: parseDoc,
  parseRunState: parseRunState,
  statusRole: statusRole,
  edgeList: edgeList,
  nodeById: nodeById,
  bounds: bounds,
  moveNode: moveNode,
  setField: setField,
  addNode: addNode,
  removeNode: removeNode,
  toggleEdge: toggleEdge,
  serializeDoc: serializeDoc,
  sparkCells: sparkCells,
  barSummary: barSummary,
  renderEnvelopeText: renderEnvelopeText,
  renderSeriesText: renderSeriesText,
  renderTableText: renderTableText
};

if (typeof module !== "undefined") {
  module.exports = api;
}
