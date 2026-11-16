// A minimal LSP client for Dyad Studio's bundled language server
// (out/server/server.js in the .vsix). It speaks the same dyad/* requests the
// Studio extension sends on behalf of its diagram webview.
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import net from "node:net";
import { pathToFileURL } from "node:url";
import { paths, requireDep, childEnv } from "./paths.mjs";

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

function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.unref();
    srv.on("error", reject);
    srv.listen(0, "127.0.0.1", () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

export class DyadLanguageServer {
  constructor({ libraryDir, julia, log }) {
    this.libraryDir = path.resolve(libraryDir);
    this.julia = julia;
    this.log = log;
    this.messages = [];
  }

  async start() {
    const serverJs = path.join(paths.studio, "out", "server", "server.js");
    this.proc = spawn(process.execPath, [serverJs, "--stdio"], {
      cwd: this.libraryDir,
      env: childEnv(),
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.proc.stderr.on("data", (d) => this.log.debug(`[server] ${String(d).trimEnd()}`));
    this.exited = new Promise((resolve) => this.proc.on("exit", (code, sig) => resolve({ code, sig })));
    this.exited.then(({ code, sig }) => {
      if (!this.stopping) this.log.warn(`language server exited (${sig ?? code})`);
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
      this.messages.push(m);
      (m.type === 1 ? this.log.warn : this.log.info)(`[server] ${m.message}`);
    });
    conn.onNotification("window/logMessage", (m) => this.log.debug(`[server] ${m.message}`));
    conn.onNotification((method, params) => {
      if (method === "dyad/statusEvent") this.onStatus(params);
      else if (method === "dyad/ast/updated") this.onAstUpdated?.(params);
    });
    conn.listen();

    await conn.sendRequest("initialize", {
      processId: process.pid,
      rootUri: folders[0].uri,
      workspaceFolders: folders,
      capabilities: { workspace: { workspaceFolders: true } },
      initializationOptions: {
        juliaExe: juliaExecutable(this.julia),
        juliaPkgServer: process.env.JULIA_PKG_SERVER ?? "",
        // The server always starts its MCP endpoint; give it a free local port.
        mcpServerPort: await freePort(),
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
    return this.conn.sendRequest(method, params);
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

  fetchIcon(url) {
    return this.request("dyad/fetch-icon", { url });
  }

  listParameterTypes(entity) {
    return this.request("dyad/list-parameter-types", { entity });
  }

  async stop() {
    this.stopping = true;
    try {
      await Promise.race([this.conn.sendRequest("shutdown"), new Promise((r) => setTimeout(r, 3000))]);
      this.conn.sendNotification("exit");
    } catch {
      // already gone
    }
    const t = setTimeout(() => this.proc.kill("SIGKILL"), 3000);
    await this.exited;
    clearTimeout(t);
    this.conn.dispose();
  }
}
