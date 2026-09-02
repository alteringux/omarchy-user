// Plain-node tests for the pure logic in Model.js. Run with:
//   node --test test/model.test.js     (or: node test/model.test.js)
const assert = require("assert");
const Model = require("../Model.js");

function test(name, fn) {
  try {
    fn();
    console.log("ok - " + name);
  } catch (e) {
    console.error("FAIL - " + name);
    console.error(e);
    process.exitCode = 1;
  }
}

test("parseDoc: tolerant of garbage", () => {
  assert.equal(Model.parseDoc("{ bad").ok, false);
  assert.equal(Model.parseDoc("").ok, false);
  assert.deepEqual(Model.parseDoc("[]").nodes, []);
});

test("parseDoc: fills ui, label, in from a real-ish doc", () => {
  const d = Model.parseDoc(
    JSON.stringify({
      id: "f",
      nodes: [
        { id: "a", type: "tool", cmd: "echo hi", ui: { x: 100, y: 20 } },
        { id: "b", type: "prompt", in: "a", prompt: "go" }
      ]
    })
  );
  assert.equal(d.ok, true);
  assert.equal(d.nodes[0].x, 100);
  assert.equal(d.nodes[0].label, "a");
  assert.deepEqual(d.nodes[1].in, ["a"]);
});

test("edgeList: data edges from `in`, dashed gates from a route", () => {
  const d = Model.parseDoc(
    JSON.stringify({
      id: "f",
      nodes: [
        { id: "src", type: "input" },
        { id: "r", type: "route", in: ["src"], edges: { x: ["leaf"] } },
        { id: "leaf", type: "prompt", in: ["src"] }
      ]
    })
  );
  const edges = Model.edgeList(d);
  assert.ok(edges.some((e) => e.fromId === "src" && e.toId === "r" && e.kind === "data"));
  assert.ok(edges.some((e) => e.fromId === "r" && e.toId === "leaf" && e.kind === "gate"));
});

test("moveNode: snaps to grid, returns a new doc, round-trips through serialize", () => {
  const d = Model.parseDoc(JSON.stringify({ id: "f", nodes: [{ id: "a", type: "tool", ui: { x: 0, y: 0 } }] }));
  const moved = Model.moveNode(d, "a", 111, 47);
  assert.equal(moved.nodes[0].x, 120); // 111 -> nearest 20
  assert.equal(moved.nodes[0].y, 40);
  assert.equal(d.nodes[0].x, 0); // original untouched
  const txt = Model.serializeDoc(moved);
  assert.match(txt, /"ui": \{[\s\S]*"x": 120/);
});

test("sparkCells: monotonic input yields ascending blocks (zero baseline)", () => {
  const s = Model.sparkCells([0, 1, 2, 3, 4, 5, 6, 7]);
  assert.equal(s.length, 8);
  assert.equal(s.charAt(0), "▁");
  assert.equal(s.charAt(7), "█");
  assert.equal(Model.sparkCells([]), "");
});

test("addNode / removeNode / toggleEdge keep the doc consistent", () => {
  let d = Model.parseDoc(JSON.stringify({ id: "f", nodes: [{ id: "a", type: "tool" }] }));
  const added = Model.addNode(d, "prompt");
  assert.equal(added.doc.nodes.length, 2);
  assert.equal(added.id, "prompt");

  d = Model.toggleEdge(added.doc, "a", "prompt");
  assert.deepEqual(Model.nodeById(d, "prompt").in, ["a"]);
  d = Model.toggleEdge(d, "a", "prompt"); // toggles back off
  assert.deepEqual(Model.nodeById(d, "prompt").in, []);

  d = Model.toggleEdge(added.doc, "a", "prompt");
  d = Model.removeNode(d, "a");
  assert.equal(Model.nodeById(d, "a"), null);
  assert.deepEqual(Model.nodeById(d, "prompt").in, []); // dangling edge pruned
});

test("statusRole maps runner statuses to Kit.Palette roles", () => {
  assert.equal(Model.statusRole("ok"), "positive");
  assert.equal(Model.statusRole("error"), "negative");
  assert.equal(Model.statusRole("skipped"), "warning");
  assert.equal(Model.statusRole(undefined), "faint");
});

test("renderEnvelopeText: series -> aligned bars + sparkline row", () => {
  const t = Model.renderEnvelopeText({ shape: "series", data: { labels: ["BBC", "NPR"], values: [2, 1] } });
  const lines = t.split("\n");
  assert.match(lines[0], /^BBC\s+2\s+█+$/);
  assert.match(lines[1], /^NPR\s+1\s+█+$/);
  assert.ok(lines[2].includes("▁") || lines[2].includes("█")); // sparkline row
});

test("renderEnvelopeText: table -> header, rule, rows", () => {
  const t = Model.renderEnvelopeText({ shape: "table", data: { columns: ["a", "b"], rows: [[1, 2], [30, 40]] } });
  const lines = t.split("\n");
  assert.match(lines[1], /─+/);
  assert.equal(lines.length, 4);
});

test("renderEnvelopeText: markdown/log pass through", () => {
  assert.equal(Model.renderEnvelopeText({ shape: "markdown", data: "## hi" }), "## hi");
  assert.equal(Model.renderEnvelopeText({ shape: "log", data: ["a", "b"] }), "a\nb");
});

test("barSummary: prefers a series sparkline, else a pass/fail tally", () => {
  assert.equal(
    Model.barSummary({ envelopes: [{ shape: "series", data: { values: [0, 8] } }], nodes: {} }),
    "▁█"
  );
  assert.equal(
    Model.barSummary({ envelopes: [], nodes: { a: { status: "ok" }, b: { status: "error" } } }),
    "1✓ 1✗"
  );
});
