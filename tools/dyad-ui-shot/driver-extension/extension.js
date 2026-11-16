// dyad-ui-shot driver: a tiny VS Code extension that lets the dyad-ui-shot
// script ask the running workbench to open Dyad diagrams. It listens on
// 127.0.0.1 only, on the port given in DYAD_UI_SHOT_DRIVER_PORT, and answers
// only requests that carry the per-run token from DYAD_UI_SHOT_DRIVER_TOKEN
// (`Authorization: Bearer <token>`). It does nothing unless both are set.
const crypto = require("crypto");
const http = require("http");
const vscode = require("vscode");

const DYAD_ID = "JuliaComputing.dyad-studio";

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on("error", reject);
  });
}

// "Lib.Mod.Comp" -> "urn:definition:Lib:Mod:Comp" (Dyad's internal entity id).
function toEntity(name) {
  if (name.startsWith("urn:")) return name;
  const parts = name.split(".");
  if (parts.length < 2) throw new Error(`expected Library.Component, got '${name}'`);
  const lib = parts[0];
  const def = parts[parts.length - 1];
  return `urn:definition:${lib}:${parts.slice(1, -1).join(".")}:${def}`;
}

async function hideChrome() {
  for (const cmd of [
    "workbench.action.closeSidebar",
    "workbench.action.closePanel",
    "workbench.action.closeAuxiliaryBar",
    "notifications.clearAll",
  ]) {
    try {
      await vscode.commands.executeCommand(cmd);
    } catch {
      // not every command exists in every VS Code build
    }
  }
}

const handlers = {
  async "GET /status"() {
    const ext = vscode.extensions.getExtension(DYAD_ID);
    return {
      dyadInstalled: !!ext,
      dyadActive: !!ext?.isActive,
      folders: (vscode.workspace.workspaceFolders || []).map((f) => f.uri.fsPath),
    };
  },
  async "POST /activate"() {
    const ext = vscode.extensions.getExtension(DYAD_ID);
    if (!ext) throw new Error(`${DYAD_ID} is not installed`);
    await ext.activate();
    return { dyadActive: ext.isActive };
  },
  async "POST /open"(body) {
    const entity = toEntity(body.component);
    await vscode.commands.executeCommand("workbench.action.closeAllEditors");
    await hideChrome();
    await vscode.commands.executeCommand("dyad-studio.entity.openEditor", {
      entity,
      readonly: body.readonly !== false,
    });
    await hideChrome();
    return { entity };
  },
};

function authorized(req, token) {
  const got = Buffer.from(String(req.headers.authorization || ""));
  const want = Buffer.from(`Bearer ${token}`);
  return got.length === want.length && crypto.timingSafeEqual(got, want);
}

function activate(context) {
  const port = Number(process.env.DYAD_UI_SHOT_DRIVER_PORT);
  const token = process.env.DYAD_UI_SHOT_DRIVER_TOKEN || "";
  if (!port || token.length < 32) return;
  const server = http.createServer(async (req, res) => {
    res.setHeader("Content-Type", "application/json");
    if (!authorized(req, token)) {
      res.statusCode = 401;
      res.end(JSON.stringify({ error: "unauthorized" }));
      return;
    }
    const handler = handlers[`${req.method} ${req.url}`];
    if (!handler) {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: "not found" }));
      return;
    }
    try {
      const out = await handler(await readBody(req));
      res.end(JSON.stringify(out));
    } catch (e) {
      res.statusCode = 500;
      res.end(JSON.stringify({ error: e instanceof Error ? e.message : String(e) }));
    }
  });
  server.listen(port, "127.0.0.1");
  context.subscriptions.push({ dispose: () => server.close() });
}

module.exports = { activate, deactivate() {}, handlers };
