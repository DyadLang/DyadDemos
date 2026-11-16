// Finding 2: icon URLs. Only local assets reach the language server; remote
// ones need --allow-remote-assets and are then fetched with limits.
import { test } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { classifyIconUrl, fetchRemoteIcon, DEFAULT_ICON } from "../lib/assets.mjs";
import { StudioWebview } from "../lib/webview.mjs";
import { quietLog } from "./helpers.mjs";

const SVG = '<svg xmlns="http://www.w3.org/2000/svg"/>';

// A local HTTP server that counts its hits.
async function iconServer() {
  const hits = [];
  const srv = http.createServer((req, res) => {
    hits.push(req.url);
    if (req.url === "/icon.svg") return res.writeHead(200, { "content-type": "image/svg+xml" }).end(SVG);
    if (req.url === "/big.svg") return res.writeHead(200, { "content-type": "image/svg+xml" }).end("x".repeat(5000));
    if (req.url === "/png") return res.writeHead(200, { "content-type": "image/png" }).end("png");
    if (req.url === "/slow.svg") return setTimeout(() => res.writeHead(200, { "content-type": "image/svg+xml" }).end(SVG), 3000);
    if (req.url === "/redirect-out") return res.writeHead(302, { location: "http://localhost:1/icon.svg" }).end();
    if (req.url === "/redirect-in") return res.writeHead(302, { location: "/icon.svg" }).end();
    res.writeHead(404).end();
  });
  await new Promise((r) => srv.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${srv.address().port}`;
  return { hits, base, host: `127.0.0.1:${srv.address().port}`, close: () => new Promise((r) => srv.close(r)) };
}

function fakeServer() {
  const calls = [];
  return {
    calls,
    async fetchIcon(url) {
      calls.push(url);
      return { icon: `<svg id="server:${url}"/>`, uri: url, problems: [] };
    },
  };
}

function view(server, remoteHosts = []) {
  const v = new StudioWebview({ browser: null, server, log: quietLog, remoteHosts });
  v.page = { evaluate: async () => {} };
  return v;
}

test("icon URLs are classified", () => {
  assert.equal(classifyIconUrl("urn:definition:Lib::Comp"), "entity");
  assert.equal(classifyIconUrl("dyad://Lib/icon.svg"), "package");
  assert.equal(classifyIconUrl("data:image/svg+xml,<svg/>"), "data");
  assert.equal(classifyIconUrl("https://example.com/i.svg"), "remote");
  assert.equal(classifyIconUrl("http://10.0.0.1/i.svg"), "remote");
  for (const u of ["file:///etc/passwd", "ftp://x/y", "icon.svg", "/abs/icon.svg", "javascript:alert(1)", "", null]) {
    assert.equal(classifyIconUrl(u), "refused", String(u));
  }
});

test("local icons go to the language server", async () => {
  const server = fakeServer();
  const v = view(server);
  for (const u of ["urn:definition:Lib::Comp", "dyad://Lib/icon.svg", "data:image/svg+xml,<svg/>"]) {
    assert.equal(await v.fetchIcon(u), `<svg id="server:${u}"/>`);
  }
  assert.deepEqual(server.calls, ["urn:definition:Lib::Comp", "dyad://Lib/icon.svg", "data:image/svg+xml,<svg/>"]);
});

test("remote and other icons are refused before they reach the server", async () => {
  const icons = await iconServer();
  try {
    const server = fakeServer();
    const v = view(server);
    for (const u of [`${icons.base}/icon.svg`, "file:///etc/passwd", "http://169.254.169.254/latest/meta-data"]) {
      assert.equal(await v.fetchIcon(u), `<svg id="server:${DEFAULT_ICON}"/>`, u);
    }
    // The server only ever saw the default icon, and nothing was fetched.
    assert.deepEqual(new Set(server.calls), new Set([DEFAULT_ICON]));
    assert.deepEqual(icons.hits, []);

    // Through the message handler, as the page sends it.
    const posted = [];
    v.post = async (m) => posted.push(m);
    await v.onMessage({ kind: "fetch-icon", url: `${icons.base}/icon.svg` });
    assert.deepEqual(posted, [{ kind: "fetch-icon-response", icon: `<svg id="server:${DEFAULT_ICON}"/>`, uri: `${icons.base}/icon.svg` }]);
    assert.deepEqual(icons.hits, []);
  } finally {
    await icons.close();
  }
});

test("--allow-remote-assets: listed hosts only, size limit, timeout, checked redirects", async () => {
  const icons = await iconServer();
  try {
    const server = fakeServer();
    const v = view(server, [icons.host]);
    // Allowed: fetched here, not by the server.
    assert.equal(await v.fetchIcon(`${icons.base}/icon.svg`), SVG);
    assert.deepEqual(server.calls, []);
    // A host that is not listed (same server, other name).
    assert.equal(await v.fetchIcon(`http://localhost:${icons.base.split(":")[2]}/icon.svg`), `<svg id="server:${DEFAULT_ICON}"/>`);
    assert.deepEqual(icons.hits, ["/icon.svg"]);

    const opts = { hosts: [icons.host], maxBytes: 1000, timeoutMs: 1000 };
    assert.equal(await fetchRemoteIcon(`${icons.base}/redirect-in`, opts), SVG);
    await assert.rejects(fetchRemoteIcon(`${icons.base}/big.svg`, opts), /larger than 1000 bytes/);
    await assert.rejects(fetchRemoteIcon(`${icons.base}/png`, opts), /not image\/svg/);
    await assert.rejects(fetchRemoteIcon(`${icons.base}/redirect-out`, opts), /localhost:1\/icon.svg: host not in/);
    const t0 = Date.now();
    await assert.rejects(fetchRemoteIcon(`${icons.base}/slow.svg`, opts), /timed out after 1s/);
    assert.ok(Date.now() - t0 < 2500);
  } finally {
    await icons.close();
  }
});

test("the language server process can neither listen nor fetch", async () => {
  const icons = await iconServer();
  try {
    const guard = new URL("../lib/server-guard.cjs", import.meta.url).pathname;
    const script = `
      const net = require("node:net");
      const out = {};
      try { net.createServer().listen(0, "127.0.0.1"); out.listen = "listening"; } catch (e) { out.listen = e.code; }
      try { require("node:http").createServer().listen(-1); out.httpListen = "listening"; } catch (e) { out.httpListen = e.code; }
      try { net.connect(${icons.base.split(":")[2]}, "127.0.0.1"); out.connect = "connected"; } catch (e) { out.connect = e.code; }
      (async () => {
        try { await fetch(${JSON.stringify(icons.base + "/icon.svg")}); out.fetch = "fetched"; } catch (e) { out.fetch = e.code; }
        out.data = await (await fetch("data:image/svg+xml,<svg/>")).text();
        console.log(JSON.stringify(out));
      })();`;
    const { stdout } = await promisify(execFile)(process.execPath, ["--require", guard, "-e", script]);
    assert.deepEqual(JSON.parse(stdout), {
      listen: "EACCES",
      httpListen: "EACCES",
      connect: "EACCES",
      fetch: "EACCES",
      data: "<svg/>",
    });
    assert.deepEqual(icons.hits, []);
  } finally {
    await icons.close();
  }
});
