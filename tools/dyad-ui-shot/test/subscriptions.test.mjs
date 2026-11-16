// Finding 6: a page's subscriptions are released on layer change and close.
import { test } from "node:test";
import assert from "node:assert/strict";
import { StudioWebview } from "../lib/webview.mjs";
import { quietLog, needSetup } from "./helpers.mjs";

const PAYLOAD = { diagram: { components: [{}], connectors: [] }, problems: [] };

// Stands in for DyadLanguageServer's acquire/release.
function fakeServer() {
  const calls = [];
  const gates = [];
  return {
    calls,
    gates,
    async acquire(entity, layer) {
      calls.push(["acquire", entity, layer]);
      if (gates.length) await gates.shift();
      return PAYLOAD;
    },
    async release(entity, layer) {
      calls.push(["release", entity, layer]);
    },
  };
}

function view(server) {
  const v = new StudioWebview({ browser: null, server, log: quietLog });
  v.page = { evaluate: async () => {}, close: async () => {} };
  return v;
}

const E = "urn:definition:Lib::Comp";

test("switching layers releases the old layer; closing releases the rest", async () => {
  const server = fakeServer();
  const v = view(server);
  await v.onMessage({ kind: "request-entity", entity: E, layer: "diagram" });
  await v.onMessage({ kind: "request-entity", entity: E, layer: "icon" });
  assert.deepEqual(server.calls, [
    ["acquire", E, "diagram"],
    ["acquire", E, "icon"],
    ["release", E, "diagram"],
  ]);
  assert.deepEqual([...v.subscriptions], [[E, "icon"]]);
  await v.close();
  assert.deepEqual(server.calls.at(-1), ["release", E, "icon"]);
  assert.equal(v.subscriptions.size, 0);
});

test("unsubscribe-entity-command releases the subscription once", async () => {
  const server = fakeServer();
  const v = view(server);
  await v.onMessage({ kind: "request-entity", entity: E });
  await v.onMessage({ kind: "unsubscribe-entity-command", entity: E });
  await v.close();
  assert.deepEqual(server.calls, [
    ["acquire", E, "diagram"],
    ["release", E, "diagram"],
  ]);
});

test("a reply that arrives after close or after a newer request is released", async () => {
  const server = fakeServer();
  const v = view(server);
  let open;
  server.gates.push(new Promise((r) => (open = r)));
  const pending = v.onMessage({ kind: "request-entity", entity: E, layer: "diagram" });
  await v.close();
  open();
  await pending;
  assert.deepEqual(server.calls, [
    ["acquire", E, "diagram"],
    ["release", E, "diagram"],
  ]);

  const server2 = fakeServer();
  const v2 = view(server2);
  let open2;
  server2.gates.push(new Promise((r) => (open2 = r)));
  const first = v2.onMessage({ kind: "request-entity", entity: E, layer: "diagram" });
  await v2.onMessage({ kind: "request-entity", entity: E, layer: "icon" });
  open2();
  await first;
  assert.deepEqual([...v2.subscriptions], [[E, "icon"]]);
  assert.deepEqual(server2.calls.filter((c) => c[0] === "release"), [["release", E, "diagram"]]);
});

test("the language server is unsubscribed when the last holder releases", needSetup, async () => {
  const { DyadLanguageServer } = await import("../lib/lsp.mjs");
  const s = new DyadLanguageServer({ libraryDir: ".", julia: "julia", log: quietLog });
  const sent = [];
  s.request = async (method, params) => {
    sent.push([method, params.layer, params.entity]);
    return PAYLOAD;
  };
  await s.acquire(E, "diagram");
  await s.acquire(E, "diagram");
  await s.release(E, "diagram");
  assert.deepEqual(sent.filter((c) => c[0] === "dyad/ast-unsubscribe"), []);
  await s.release(E, "diagram");
  assert.deepEqual(sent.at(-1), ["dyad/ast-unsubscribe", "diagram", E]);
  await s.release(E, "diagram"); // an extra release sends nothing
  assert.equal(sent.filter((c) => c[0] === "dyad/ast-unsubscribe").length, 1);
});
