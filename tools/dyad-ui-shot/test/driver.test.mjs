// Finding 5: the studio-mode driver extension has no arbitrary-command route
// and answers only requests with the per-run token.
import { test } from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import Module from "node:module";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const executed = [];
const vscodeMock = {
  extensions: { getExtension: () => ({ isActive: false, activate: async () => {} }) },
  workspace: { workspaceFolders: [] },
  commands: { executeCommand: async (...a) => executed.push(a) },
};
const load = Module._load;
Module._load = function (request, ...rest) {
  return request === "vscode" ? vscodeMock : load.call(this, request, ...rest);
};
const driver = require("../driver-extension/extension.js");
Module._load = load;

function freePort() {
  return new Promise((resolve) => {
    const s = net.createServer().listen(0, "127.0.0.1", () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
  });
}

async function activate(env) {
  const saved = { ...process.env };
  Object.assign(process.env, env);
  const context = { subscriptions: [] };
  try {
    driver.activate(context);
  } finally {
    for (const k of Object.keys(env)) if (k in saved) process.env[k] = saved[k];
    else delete process.env[k];
  }
  await new Promise((r) => setTimeout(r, 100));
  return () => context.subscriptions.forEach((s) => s.dispose());
}

const TOKEN = "a".repeat(64);

test("routes need the token; /command is gone", async () => {
  const port = await freePort();
  const stop = await activate({ DYAD_UI_SHOT_DRIVER_PORT: String(port), DYAD_UI_SHOT_DRIVER_TOKEN: TOKEN });
  try {
    const call = (method, route, token, body) =>
      fetch(`http://127.0.0.1:${port}${route}`, {
        method,
        headers: token ? { authorization: `Bearer ${token}` } : {},
        body: body && JSON.stringify(body),
      });
    assert.equal((await call("GET", "/status")).status, 401);
    assert.equal((await call("GET", "/status", "b".repeat(64))).status, 401);
    assert.equal((await call("GET", "/status", TOKEN.slice(1))).status, 401);
    assert.equal((await call("POST", "/command", null, { command: "workbench.action.quit" })).status, 401);
    const status = await call("GET", "/status", TOKEN);
    assert.equal(status.status, 200);
    assert.equal((await status.json()).dyadInstalled, true);
    assert.equal((await call("POST", "/command", TOKEN, { command: "workbench.action.quit" })).status, 404);
    assert.deepEqual(executed, []);
    assert.equal("POST /command" in driver.handlers, false);
  } finally {
    stop();
  }
});

test("without a token the driver does not listen", async () => {
  const port = await freePort();
  const stop = await activate({ DYAD_UI_SHOT_DRIVER_PORT: String(port), DYAD_UI_SHOT_DRIVER_TOKEN: "" });
  try {
    await assert.rejects(fetch(`http://127.0.0.1:${port}/status`), /fetch failed/);
  } finally {
    stop();
  }
});
