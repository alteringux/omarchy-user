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

test("parseRunState: malformed nested state becomes safe empty entries", () => {
  const rs = Model.parseRunState(JSON.stringify({
    nodes: { good: { status: "ok" }, bad: null, list: [] },
    envelopes: [null, "old", { shape: "table", data: { columns: ["a"], rows: [null, "bad", [1]] } }],
    order: ["good", 4, null]
  }));
  assert.deepEqual(Object.keys(rs.nodes), ["good"]);
  assert.equal(rs.envelopes.length, 1);
  assert.deepEqual(rs.envelopes[0].data.rows, [[1]]);
  assert.deepEqual(rs.order, ["good"]);
  assert.deepEqual(Model.parseRunState("[]").nodes, {});
});


test("parseDoc: hostile own-property names do not break recovery or save", () => {
  const d = Model.parseDoc(JSON.stringify({
    id: "f",
    nodes: [{ id: "a", type: "tool", hasOwnProperty: "not a function" }]
  }));
  assert.equal(d.nodes.length, 1);
  assert.doesNotThrow(() => JSON.parse(Model.serializeDoc(d)));
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

test("serializeDoc: a canvas edit round-trips WITHOUT dropping op/key/mode/meta", () => {
  const src = JSON.stringify({
    id: "f",
    title: "t",
    nodes: [
      { id: "m", type: "memory", op: "append", key: "hist", in: ["a"], meta: { title: "M" } },
      { id: "d", type: "reduce", mode: "llm", in: ["a"], prompt: "go", ui: { x: 5, y: 5 } },
      { id: "a", type: "input", value: { text: "hi" } }
    ]
  });
  const moved = Model.moveNode(Model.parseDoc(src), "d", 40, 40);
  const back = JSON.parse(Model.serializeDoc(moved));
  const m = back.nodes.find((n) => n.id === "m");
  const d = back.nodes.find((n) => n.id === "d");
  assert.equal(m.op, "append");
  assert.equal(m.key, "hist");
  assert.deepEqual(m.meta, { title: "M" });
  assert.equal(d.mode, "llm");
  assert.deepEqual(d.ui, { x: 40, y: 40 });
  assert.deepEqual(back.nodes.find((n) => n.id === "a").value, { text: "hi" });
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

test("speakable: strips markdown marks Piper should not read aloud", () => {
  assert.equal(Model.speakable("## Culture\n- **Big** news _here_"), "Culture\nBig news here");
  assert.equal(Model.speakable("see [the site](https://x.y) now"), "see the site now");
  assert.equal(Model.speakable(null), "");
});

test("splitSections: dateline + one section per '## Heading', with speakText", () => {
  const md = "*Thu, Sep 3 — all sectors*\n\n## World\n- a (BBC)\n- b (NPR)\n\n## Food\n- c (Eater)";
  const s = Model.splitSections(md);
  assert.equal(s.length, 3);
  assert.equal(s[0].heading, ""); // the dateline
  assert.equal(s[1].heading, "World");
  assert.match(s[1].body, /^- a \(BBC\)/);
  assert.equal(s[2].heading, "Food");
  assert.ok(s[1].speakText.startsWith("World. "));
  assert.ok(!s[1].speakText.includes("## "));
  assert.equal(Model.splitSections("").length, 0);
});

test("escapeHtml: entity-encodes for Text.StyledText", () => {
  assert.equal(Model.escapeHtml('A & B <c> "d"'), "A &amp; B &lt;c&gt; &quot;d&quot;");
  assert.equal(Model.escapeHtml(null), "");
});

test("splitBullets: pulls lead, source, and notes out of a section body", () => {
  const body = [
    "- **Robotaxi launch:** Uber beats Waymo to London with Wayve tech (The Verge).",
    "- Congress blocks OMB grant-funding rewrite (Ars Technica)",
    "- plain point with no source",
    "_nothing notable_",
  ].join("\n");
  const b = Model.splitBullets(body);
  assert.equal(b.length, 4);
  assert.deepEqual(b[0], {
    kind: "bullet",
    lead: "Robotaxi launch",
    text: "Uber beats Waymo to London with Wayve tech",
    source: "The Verge",
  });
  assert.deepEqual(b[1], {
    kind: "bullet", lead: "", text: "Congress blocks OMB grant-funding rewrite", source: "Ars Technica",
  });
  assert.deepEqual(b[2], { kind: "bullet", lead: "", text: "plain point with no source", source: "" });
  assert.deepEqual(b[3], { kind: "note", text: "nothing notable" });
  assert.deepEqual(Model.splitBullets(""), []);
});

test("sectorScoreMap + scoreBadge: read the mood table, badge by sign + delta", () => {
  const envs = [
    { shape: "series", data: { labels: ["World"], values: [8] } },
    {
      shape: "table",
      data: {
        columns: ["Sector", "Today", "Δ prev", "7d avg", "Trend"],
        rows: [
          ["World", -4, "-3", "-2.5", "▄▂"],
          ["Science", 5, "—", "+5.0", "█"],
          ["Sports", 0, "+0", "+0.0", "▅"],
          ["Food", "n/a", "—", "—", "—"]
        ]
      }
    }
  ];
  const m = Model.sectorScoreMap(envs);
  assert.equal(m.World.score, -4);
  assert.equal(m.World.delta, "-3");
  assert.equal(m.Food.score, null);

  assert.deepEqual(Model.scoreBadge(m.World), { text: "-4  -3 ▼", role: "negative" });
  assert.deepEqual(Model.scoreBadge(m.Science), { text: "+5", role: "positive" });
  assert.equal(Model.scoreBadge(m.Sports).role, "faint");
  assert.equal(Model.scoreBadge(m.Food), null);
  assert.equal(Model.scoreBadge(undefined), null);
  assert.deepEqual(Model.sectorScoreMap([]), {});
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
