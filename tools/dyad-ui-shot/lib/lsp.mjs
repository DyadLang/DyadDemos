// A minimal LSP client for Dyad Studio's bundled language server
// (out/server/server.js in the .vsix). It speaks the same dyad/* requests the
// Studio extension sends on behalf of its diagram webview.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { paths, requireDep, childEnv } from "./paths.mjs";
import { spawnOwned, terminate, deadline } from "./procs.mjs";

const rpc = requireDep("vscode-jsonrpc/node");

// The server spawns juliaExe directly (no shell), so a command like
// "julia +dyad-3.5.0" needs a one-line wrapper script.
function juliaExecutable(cmd) {
  const parts = cmd.trim().split(/\s+/);
  if (parts.length === 1) return parts[0];
  const wrapper = path.join(paths.tmp, "julia-wrapper.sh");
  const quoted = parts.map((p) => `'${p.replace(/'/g, `'\\''`)}'`).join(" ");
  fs.mkdirSync(paths.tmp, { recursive: true });
  fs.writeFileSync(wrapper, `#!/bin/sh\nexec ${quoted} "$@"\n`, { mode: 0o755 });
  return wrapper;
}

// Keeps the server from listening or reaching the network; see the file.
export const SERVER_GUARD = fileURLToPath(new URL("./server-guard.cjs", import.meta.url));

// The server's "MCP failed to start" error, which is expected here.
const MCP_REFUSED = /MCP server failed to start/;

export class DyadLanguageServer {
  // timeoutMs bounds every request, initialization included.
  constructor({ libraryDir, julia, log, timeoutMs = 120000 }) {
    this.libraryDir = path.resolve(libraryDir);
    this.julia = julia;
    this.log = log;
    this.timeoutMs = timeoutMs;
    this.messages = [];
    this.subscriptionCounts = new Map();
  }

  async start() {
    const serverJs = path.join(paths.studio, "out", "server", "server.js");
    this.proc = spawnOwned(process.execPath, ["--require", SERVER_GUARD, serverJs, "--stdio"], {
      cwd: this.libraryDir,
      env: childEnv(),
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.proc.stderr.on("data", (d) => this.log.debug(`[server] ${String(d).trimEnd()}`));
    this.proc.exited.then(({ code, signal, error }) => {
      if (!this.stopping) this.log.warn(`language server exited (${error?.message ?? signal ?? code})`);
      this.conn?.dispose();
    });

    const conn = rpc.createMessageConnection(
      new rpc.StreamMessageReader(this.proc.stdout),
      new rpc.StreamMessageWriter(this.proc.stdin),
    );
    this.conn = conn;
    const folders = [{ uri: pathToFileURL(this.libraryDir).href, name: path.basename(this.libraryDir) }];
    conn.onRequest("workspace/workspaceFolders", () => folders);
    conn.onRequest("workspace/configuration", (p) => (p.items || []).map(() => null));
    conn.onRequest("client/registerCapability", () => null);
    conn.onRequest("client/unregisterCapability", () => null);
    conn.onRequest("window/workDoneProgress/create", () => null);
    conn.onRequest("window/showMessageRequest", () => null);
    conn.onNotification("window/showMessage", (m) => {
      if (MCP_REFUSED.test(m.message)) return this.log.debug(`[server] ${m.message} (MCP is disabled)`);
      this.messages.push(m);
      (m.type === 1 ? this.log.warn : this.log.info)(`[server] ${m.message}`);
    });
    conn.onNotification("window/logMessage", (m) => this.log.debug(`[server] ${m.message}`));
    conn.onNotification((method, params) => {
      if (method === "dyad/statusEvent") this.onStatus(params);
      else if (method === "dyad/ast/updated") this.onAstUpdated?.(params);
    });
    conn.listen();

    await this.request("initialize", {
      processId: process.pid,
      rootUri: folders[0].uri,
      workspaceFolders: folders,
      capabilities: { workspace: { workspaceFolders: true } },
      initializationOptions: {
        juliaExe: juliaExecutable(this.julia),
        juliaPkgServer: process.env.JULIA_PKG_SERVER ?? "",
        // The server always starts its MCP endpoint (an HTTP server on all
        // interfaces whose tools write files). An invalid port, and the
        // listen() refusal in server-guard.cjs, make that fail; the server
        // reports it and runs without MCP.
        mcpServerPort: -1,
        unparseOptions: { inlineMetadata: false },
      },
    });
    await conn.sendNotification("initialized", {});
  }

  onStatus(s) {
    if (s.kind === "begin") this.log.debug(`[status] ${s.title ?? s.id}${s.detail ? `: ${s.detail}` : ""}`);
    else if (s.kind === "end" && s.outcome !== "ok") this.log.warn(`[status] ${s.id} ${s.outcome}: ${s.detail ?? ""}`);
    else if (s.kind === "halted") this.log.warn(`[status] halted: ${s.reason}`);
  }

  request(method, params) {
    return deadline(this.conn.sendRequest(method, params), this.timeoutMs, `language server request ${method}`);
  }

  // The library tree (all libraries, modules and definitions the server knows).
  tree() {
    return this.request("dyad/tree", {});
  }

  // Current diagram payload of an entity for a layer ("diagram" or "icon"),
  // exactly what Studio forwards to its webview as {kind: "diagram"}.
  subscribe(entity, layer = "diagram") {
    return this.request("dyad/ast-subscribe", { layer, entity });
  }

  unsubscribe(entity, layer = "diagram") {
    return this.request("dyad/ast-unsubscribe", { layer, entity }).catch(() => {});
  }

  // Reference-counted subscriptions, like Studio's notification hub: each
  // acquire() gets the current payload, and the server is unsubscribed when
  // the last holder of an (entity, layer) releases it.
  async acquire(entity, layer = "diagram") {
    const key = `${layer} ${entity}`;
    this.subscriptionCounts.set(key, (this.subscriptionCounts.get(key) ?? 0) + 1);
    try {
      return await this.subscribe(entity, layer);
    } catch (e) {
      await this.release(entity, layer);
      throw e;
    }
  }

  async release(entity, layer = "diagram") {
    const key = `${layer} ${entity}`;
    const n = (this.subscriptionCounts.get(key) ?? 0) - 1;
    if (n > 0) return this.subscriptionCounts.set(key, n);
    this.subscriptionCounts.delete(key);
    if (n === 0 && !this.stopping) await this.unsubscribe(entity, layer);
  }

  fetchIcon(url) {
    return this.request("dyad/fetch-icon", { url });
  }

  listParameterTypes(entity) {
    return this.request("dyad/list-parameter-types", { entity });
  }

  // Safe to call after a failed or partial start(). Kills the server's whole
  // process group (Julia included) if it does not exit by itself.
  async stop() {
    this.stopping = true;
    if (this.conn) {
      try {
        await deadline(this.conn.sendRequest("shutdown"), 3000, "shutdown");
        await this.conn.sendNotification("exit");
      } catch {
        // already gone, or not answering
      }
    }
    await terminate(this.proc, 3000);
    this.conn?.dispose();
  }
}
