// Standalone mode: host Dyad Studio's own diagram webview (out/dyad-ui.js from
// the pinned .vsix) in headless Chrome, and play the part of the Studio
// extension host for it, answering its messages from the bundled language
// server.
import fs from "node:fs";
import path from "node:path";
import { paths } from "./paths.mjs";

// Pages are served from this made-up origin through request interception; no
// port is opened and nothing is fetched from the network.
const ORIGIN = "https://webview.dyad-ui-shot.invalid";

// The defaults VS Code injects into every webview (src/vs/workbench/contrib/
// webview/browser/pre/index.html), with the values of VS Code's default "Light
// Modern" theme on Linux for the few variables involved. dyad-ui only reads
// --vscode-font-size (through Studio's own :root rule below); the rest keeps
// the page identical to Studio's webview anyway.
const VSCODE_WEBVIEW_DEFAULTS = `
  html {
    --vscode-font-family: system-ui, "Ubuntu", "Droid Sans", sans-serif;
    --vscode-font-weight: normal;
    --vscode-font-size: 13px;
    --vscode-editor-background: #ffffff;
    --vscode-editor-foreground: #3b3b3b;
    scrollbar-color: var(--vscode-scrollbarSlider-background) var(--vscode-editor-background);
  }
  body {
    background-color: transparent;
    color: var(--vscode-editor-foreground);
    font-family: var(--vscode-font-family);
    font-weight: var(--vscode-font-weight);
    font-size: var(--vscode-font-size);
    margin: 0;
    padding: 0 20px;
  }
  img, video { max-width: 100%; max-height: 100%; }
`;

// The document Studio 3.5.1 builds for its entity editor (function gtt in
// out/extension.js), with VS Code's webview URIs replaced by ORIGIN, plus what
// VS Code adds to every webview (the default styles, the theme class on body).
// Keep in sync when bumping DYAD_STUDIO_VERSION.
function studioHtml(entity, title) {
  const nonce = "dyaduishot";
  const esc = (s) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
  return `
    <!DOCTYPE html>
    <html lang="en" style="background-color: var(--vscode-editor-background)">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta
          http-equiv="Content-Security-Policy"
          content="
            default-src 'none';
            style-src ${ORIGIN} 'unsafe-inline';
            font-src ${ORIGIN};
            script-src 'nonce-${nonce}';
            script-src-elem 'nonce-${nonce}';
            connect-src ${ORIGIN} data: dyad:;"
        />
        <style id="_defaultStyles">${VSCODE_WEBVIEW_DEFAULTS}</style>
        <script type="module" nonce="${nonce}" src="${ORIGIN}/out/dyad-ui.js"></script>
        <title>${esc(title)}</title>
        <style>
          @font-face {
            font-family: "Inter";
            font-style: normal;
            font-display: swap;
            font-weight: 100 900;
            src: url("${ORIGIN}/out/fonts/inter-latin-wght-normal.woff2") format("woff2-variations");
          }
          /* Anchor rem to VSCode's UI font-size so dyad-ui's rem-based
           * tokens track the editor.fontSize preference. */
          :root {
            font-size: var(--vscode-font-size);
          }
          body {
            block-size: 100dvb;
            padding: 0;
          }
        </style>
      </head>
      <body class="vscode-light" data-vscode-theme-kind="vscode-light">
        <dyad-theme theme="light">
          <dyad-vscode-ui entity="${esc(entity)}"></dyad-vscode-ui>
        </dyad-theme>
      </body>
    </html>
  `;
}

// Runs in the page before dyad-ui.js: the part of VS Code's webview API that
// dyad-ui uses (acquireVsCodeApi().postMessage/getState/setState). Messages go
// to Node through a puppeteer binding; replies come back as window "message"
// events, as in a real webview.
function installVsCodeApiShim() {
  let state;
  const api = Object.freeze({
    postMessage: (msg) => window.__dyadUiShotPost(JSON.stringify(msg)),
    getState: () => state,
    setState: (s) => ((state = s), s),
  });
  window.acquireVsCodeApi = () => api;
}

const MIME = { ".js": "text/javascript", ".woff2": "font/woff2", ".svg": "image/svg+xml", ".png": "image/png" };

// One browser page showing one Dyad diagram, fed from `server`.
export class StudioWebview {
  constructor({ browser, server, log }) {
    this.browser = browser;
    this.server = server;
    this.log = log;
    this.inflight = 0;
    this.lastActivity = Date.now();
    this.errors = [];
  }

  async open(entity, { width, height, scale = 1, layer = "diagram" }) {
    this.entity = entity;
    this.layer = layer;
    const page = await this.browser.newPage();
    this.page = page;
    await page.setViewport({ width, height, deviceScaleFactor: scale });
    page.on("console", (m) => {
      const text = m.text();
      if (m.type() === "error") this.errors.push(text);
      this.log.debug(`[page:${m.type()}] ${text}`);
    });
    page.on("pageerror", (e) => {
      this.errors.push(String(e));
      this.log.warn(`[page] ${e}`);
    });

    const outDir = path.join(paths.studio, "out");
    await page.setRequestInterception(true);
    page.on("request", (req) => {
      const url = req.url();
      if (url === `${ORIGIN}/index.html`) {
        return req.respond({ status: 200, contentType: "text/html", body: studioHtml(entity, entity) });
      }
      if (url.startsWith(`${ORIGIN}/out/`)) {
        const rel = decodeURIComponent(new URL(url).pathname.slice("/out/".length));
        const file = path.resolve(outDir, rel);
        if (file.startsWith(outDir + path.sep) && fs.existsSync(file)) {
          return req.respond({
            status: 200,
            contentType: MIME[path.extname(file)] ?? "application/octet-stream",
            body: fs.readFileSync(file),
          });
        }
      }
      if (url.startsWith("data:")) return req.continue();
      this.log.debug(`[page] blocked request ${url}`);
      return req.respond({ status: 404, body: "" });
    });

    await page.exposeFunction("__dyadUiShotPost", (json) => this.onMessage(JSON.parse(json)));
    await page.evaluateOnNewDocument(installVsCodeApiShim);
    this.server.onAstUpdated = (payload) => {
      if (payload?.diagram?.origin === this.entity && payload.diagram.kind === this.layer) {
        this.post({ kind: "diagram", diagram: payload });
      }
    };
    await page.goto(`${ORIGIN}/index.html`, { waitUntil: "load" });
  }

  async post(msg) {
    if (this.closed) return;
    this.lastActivity = Date.now();
    try {
      await this.page.evaluate((m) => window.postMessage(m, "*"), msg);
    } catch (e) {
      this.log.debug(`post failed: ${e}`);
    }
  }

  // The subset of Studio's handleWebviewMessage (out/extension.js, class fye)
  // that a read-only view needs. Edits are dropped: nothing is ever written.
  async onMessage(msg) {
    this.inflight++;
    this.lastActivity = Date.now();
    this.log.debug(`[webview->host] ${msg.kind}`);
    try {
      switch (msg.kind) {
        case "request-entity": {
          const entity = msg.entity ?? this.entity;
          const layer = msg.layer ?? "diagram";
          this.layer = layer;
          const payload = await this.server.subscribe(entity, layer);
          const errors = [];
          for (const p of payload.problems ?? []) {
            const text = `${p.title ?? p.message ?? JSON.stringify(p)}${p.details ? ` (${p.details})` : ""}`;
            if (p.severity === "error" && !errors.includes(text)) errors.push(text);
            (p.severity === "error" ? this.log.warn : this.log.debug)(`[${entity}] ${p.severity}: ${text}`);
          }
          // An empty diagram plus errors (e.g. an unknown component) is not a
          // picture worth saving.
          const d = payload.diagram ?? {};
          if (errors.length && !(d.components?.length || d.connectors?.length)) {
            this.fatal = `${entity}: ${errors.join("; ")}`;
          }
          await this.post({ kind: "diagram", diagram: payload });
          break;
        }
        case "tree-request": {
          const t = await this.server.tree();
          await this.post({ kind: "library-tree-update", tree: t.tree, problems: t.problems });
          break;
        }
        case "fetch-icon": {
          const r = await this.server.fetchIcon(msg.url);
          await this.post({ kind: "fetch-icon-response", icon: r.icon, uri: msg.url });
          break;
        }
        case "list-parameter-types": {
          const r = await this.server
            .listParameterTypes(msg.entity)
            .catch((e) => ({ types: [], problems: [{ severity: "error", message: String(e) }] }));
          await this.post({ kind: "list-parameter-types-response", entity: msg.entity, types: r.types, problems: r.problems });
          break;
        }
        case "unsubscribe-entity-command":
          await this.server.unsubscribe(msg.entity, this.layer);
          break;
        default:
          this.log.debug(`ignoring webview message '${msg.kind}' (read-only)`);
      }
    } catch (e) {
      if (this.closed) return;
      this.errors.push(`${msg.kind}: ${e?.message ?? e}`);
      this.log.warn(`handling '${msg.kind}' failed: ${e?.message ?? e}`);
    } finally {
      this.inflight--;
      this.lastActivity = Date.now();
    }
  }

  async close() {
    this.closed = true;
    this.server.onAstUpdated = null;
    await this.page?.close().catch(() => {});
  }
}
