// Finding 5, for real: openvscode-server with a generated connection token,
// the driver extension behind its per-run token, loopback only. Needs
// `setup.sh --studio`; no JuliaHub login (Studio is never activated).
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { StudioServer, openWorkbench } from "../lib/studio-mode.mjs";
import { paths, importDep } from "../lib/paths.mjs";
import { quietLog, haveSetup, fixtureLib, descendants, processTable, listeningSockets, isLoopback, alive } from "./helpers.mjs";

const ready = haveSetup && fs.existsSync(`${paths.openvscode}/extensions-installed`);

test("studio mode: tokens required, loopback only, nothing left after stop", ready ? {} : { skip: "run setup.sh --studio first" }, async () => {
  const server = new StudioServer({ libraryDir: fixtureLib(), julia: "julia", log: quietLog });
  const puppeteer = (await importDep("puppeteer-core")).default;
  const browser = await puppeteer.launch({ executablePath: paths.chrome, headless: "shell", args: ["--no-sandbox"] });
  let tree = [];
  try {
    await server.start();
    const base = `http://127.0.0.1:${server.port}`;
    // The workbench refuses a request without the connection token.
    const anon = await fetch(`${base}/`, { redirect: "manual" });
    assert.ok(anon.status === 401 || anon.status === 403, `GET / without token: ${anon.status}`);
    assert.ok((await fetch(server.url(), { redirect: "manual" })).status < 400);

    // Loading the workbench starts the extension host, and with it the driver.
    const page = await browser.newPage();
    const status = await openWorkbench(page, server, 60000);
    assert.equal(status.dyadInstalled, true);
    const d = `http://127.0.0.1:${server.driver.port}`;
    const auth = { authorization: `Bearer ${server.driver.token}` };
    assert.equal((await fetch(`${d}/status`, { headers: auth })).status, 200);
    assert.equal((await fetch(`${d}/status`)).status, 401);
    assert.equal((await fetch(`${d}/status`, { headers: { authorization: "Bearer nope" } })).status, 401);
    const cmd = await fetch(`${d}/command`, { method: "POST", headers: auth, body: JSON.stringify({ command: "workbench.action.quit" }) });
    assert.equal(cmd.status, 404);

    // Everything the server and its children listen on is loopback.
    const table = processTable();
    tree = [server.proc.pid, ...descendants(server.proc.pid, table)];
    const sockets = listeningSockets().filter((s) => s.pids.some((p) => tree.includes(p)));
    assert.ok(sockets.length >= 2, `expected the workbench and driver sockets, got ${sockets.map((s) => s.line)}`);
    assert.deepEqual(sockets.filter((s) => !isLoopback(s.local)).map((s) => s.line), []);
    await page.close();
  } finally {
    await server.stop();
    await browser.close();
  }
  await new Promise((r) => setTimeout(r, 200));
  assert.deepEqual(tree.filter(alive), []);
});
