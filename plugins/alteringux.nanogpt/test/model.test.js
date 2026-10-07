const assert = require("assert");
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(require.resolve("../Model.js"), "utf8")
  .replace(/^\.pragma library\s*/, "");
const context = { module: { exports: {} } };
vm.runInNewContext(source, context, { filename: "Model.js" });
const Model = context.module.exports;

function test(name, fn) {
  try {
    fn();
    console.log("ok - " + name);
  } catch (error) {
    console.error("not ok - " + name);
    throw error;
  }
}

test("parseState rejects a top-level array", () => {
  assert.deepStrictEqual(Model.parseState("[]"), Model.defaultState());
});

test("parseState removes malformed rows before QML consumes them", () => {
  const state = Model.parseState(JSON.stringify({
    ready: "true",
    plan: [],
    today: null,
    allTime: "broken",
    tokenComposition: [],
    week: [null, 7, { date: "2026-09-18", totalTokens: 12 }],
    models: [null, { id: "ok", recentDays: [null, { totalTokens: 5 }] }],
  }));

  assert.strictEqual(state.ready, false);
  assert.strictEqual(JSON.stringify(state.plan), "{}");
  assert.strictEqual(JSON.stringify(state.today), "{}");
  assert.strictEqual(JSON.stringify(state.week), "[{\"date\":\"2026-09-18\",\"totalTokens\":12}]");
  assert.strictEqual(state.models.length, 1);
  assert.strictEqual(JSON.stringify(state.models[0].recentDays), "[{\"totalTokens\":5}]");
  assert.strictEqual(Model.weekPeak(state.week), 12);
  assert.strictEqual(Model.modelPeak(state.models), 0);
  assert.strictEqual(Model.modelDayPeak(state.models[0]), 5);
});

test("parseState preserves normal collector state", () => {
  const state = Model.parseState(JSON.stringify({
    schemaVersion: 1,
    ready: true,
    plan: { active: true, weeklyUsed: 25, weeklyLimit: 100 },
    today: { totalTokens: 25 },
    week: [{ date: "2026-09-18", totalTokens: 25 }],
    models: [{ id: "model", total: 25, recentDays: [] }],
    tokenComposition: { input: 20, output: 5 },
  }));

  assert.strictEqual(state.ready, true);
  assert.strictEqual(JSON.stringify(state.plan), "{\"active\":true,\"weeklyUsed\":25,\"weeklyLimit\":100}");
  assert.strictEqual(state.today.totalTokens, 25);
  assert.strictEqual(state.models[0].id, "model");
  assert.strictEqual(Model.quotaRatio(state.plan), 0.25);
});

console.log("all tests passed");
