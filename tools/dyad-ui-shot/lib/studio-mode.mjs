// Optional "full Studio" mode: run the real Dyad Studio extension in
// openvscode-server, open the diagram through Studio's own command, and
// screenshot its webview in the workbench. The driver extension
// (driver-extension/) gives this script a local control channel into the
// workbench.
//
// Studio's activation waits for juliahub-vscode-auth to authenticate, so this
// mode only works on a runner with a valid JuliaHub login. Nothing here
// provides, fakes or refreshes one.
import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { paths, requireSetup, childEnv } from "./paths.mjs";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

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

async function driver(port, method, route, body, timeoutMs = 10000) {
  const res = await fetch(`http://127.0.0.1:${port}${route}`, {
    method,
    headers: { "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(timeoutMs),
  });
  const out = await res.json();
  if (!res.ok) throw new Error(out.error ?? `${route}: HTTP ${res.status}`);
  return out;
}

async function waitFor(what, timeoutMs, fn) {
  const t0 = Date.now();
  let lastErr;
  while (Date.now() - t0 < timeoutMs) {
    try {
      const v = await fn();
      if (v) return v;
    } catch (e) {
      lastErr = e;
    }
    await sleep(500);
  }
  throw new Error(`timed out after ${timeoutMs / 1000}s waiting for ${what}${lastErr ? ` (${lastErr.message})` : ""}`);
}

class StudioServer {
  constructor({ libraryDir, julia, log }) {
    this.libraryDir = libraryDir;
    this.julia = julia;
    this.log = log;
  }

  async start() {
    const installed = path.join(paths.openvscode, "extensions-installed");
    if (!fs.existsSync(installed)) throw new Error(`no extensions in ${installed}; run setup.sh --studio`);
    fs.mkdirSync(paths.tmp, { recursive: true });
    // A fresh server/user data dir per run: no state leaks between runs.
    this.dataDir = fs.mkdtempSync(path.join(paths.tmp, "openvscode-data-"));
    const machine = path.join(this.dataDir, "data", "Machine");
    fs.mkdirSync(machine, { recursive: true });
    fs.writeFileSync(
      path.join(machine, "settings.json"),
      JSON.stringify(
        {
          "workbench.colorTheme": "Default Light Modern",
          "workbench.startupEditor": "none",
          "workbench.tips.enabled": false,
          "security.workspace.trust.enabled": false,
          "telemetry.telemetryLevel": "off",
          "extensions.autoUpdate": false,
          "extensions.autoCheckUpdates": false,
          "chat.disableAIFeatures": true,
          "julia.executablePath": this.julia,
        },
        null,
        2,
      ),
    );
    this.port = await freePort();
    this.driverPort = await freePort();
    this.proc = spawn(
      path.join(paths.openvscode, "bin", "openvscode-server"),
      [
        "--host", "127.0.0.1",
        "--port", String(this.port),
        "--without-connection-token",
        "--server-data-dir", this.dataDir,
        "--extensions-dir", installed,
        "--default-folder", this.libraryDir,
        "--disable-telemetry",
      ],
      { env: childEnv({ DYAD_UI_SHOT_DRIVER_PORT: String(this.driverPort) }), stdio: ["ignore", "pipe", "pipe"] },
    );
    this.proc.stdout.on("data", (d) => this.log.debug(`[openvscode] ${String(d).trimEnd()}`));
    this.proc.stderr.on("data", (d) => this.log.debug(`[openvscode] ${String(d).trimEnd()}`));
    this.exited = new Promise((r) => this.proc.on("exit", r));
    await waitFor("openvscode-server", 60000, async () => (await fetch(`http://127.0.0.1:${this.port}/`)).ok);
  }

  url() {
    return `http://127.0.0.1:${this.port}/?folder=${encodeURIComponent(this.libraryDir)}`;
  }

  async stop() {
    this.proc.kill("SIGTERM");
    const t = setTimeout(() => this.proc.kill("SIGKILL"), 5000);
    await this.exited;
    clearTimeout(t);
    if (this.keepData || process.env.DYAD_UI_SHOT_KEEP_DATA) {
      this.log.info(`workbench logs kept in ${path.join(this.dataDir, "data", "logs")}`);
    } else fs.rmSync(this.dataDir, { recursive: true, force: true });
  }
}

// The frame (nested inside the webview iframes) that runs dyad-ui for `entity`.
async function findDiagramFrame(page, entity) {
  for (const f of page.frames()) {
    const ok = await f
      .evaluate((e) => document.querySelector("dyad-vscode-ui")?.getAttribute("entity") === e, entity)
      .catch(() => false);
    if (ok) return f;
  }
  return null;
}

export async function runStudio(shots, opt, log, { launchChrome, captureHelpers, toEntity, renderPng }) {
  requireSetup("openvscode", "chrome", "node");
  const { waitForDiagram, switchLayer, captureDiagram } = captureHelpers;
  const browser = await launchChrome(opt);
  let failures = 0;
  try {
    for (const [lib, libShots] of Map.groupBy(shots, (s) => s.lib)) {
      const server = new StudioServer({ libraryDir: lib, julia: opt.julia || process.env.JULIA_EXECUTABLE || "julia +dyad-3.5.0", log });
      log.info(`starting openvscode-server for ${lib}`);
      await server.start();
      const page = await browser.newPage();
      try {
        await page.setViewport({ width: opt.width, height: opt.height, deviceScaleFactor: opt.scale });
        await page.goto(server.url(), { waitUntil: "domcontentloaded" });
        // Extensions only run in a trusted workspace. The machine setting
        // usually prevents the prompt; answer it if it shows up anyway.
        await waitFor("the workbench and the dyad-ui-shot driver", 120000, async () => {
          await page
            .evaluate(() =>
              [...document.querySelectorAll(".dialog-buttons a, .dialog-buttons button")]
                .find((b) => /trust the authors/i.test(b.textContent) && /^\s*Yes/.test(b.textContent))
                ?.click(),
            )
            .catch(() => {});
          return driver(server.driverPort, "GET", "/status");
        });
        log.info("activating Dyad Studio (needs a valid JuliaHub login)");
        try {
          await driver(server.driverPort, "POST", "/activate", null, opt.timeout * 1000);
        } catch (e) {
          throw new Error(
            `Dyad Studio did not activate (${e.message}). Its activation waits for ` +
              `juliahub-vscode-auth; this mode needs a valid JuliaHub login on the runner. ` +
              `Use --mode standalone otherwise.`,
          );
        }
        for (const shot of libShots) {
          const t0 = Date.now();
          try {
            const entity = toEntity(shot.component);
            await driver(server.driverPort, "POST", "/open", { component: entity }, opt.timeout * 1000).catch((e) => {
              throw new Error(
                `Dyad Studio did not open the diagram (${e.message}). Studio's commands wait until it ` +
                  `has a Julia installation and a JuliaHub login; see the "Dyad Studio Client Log" and ` +
                  `"JuliaHub Authentication" logs.`,
              );
            });
            const frame = await waitFor(`the diagram webview of ${shot.component}`, opt.timeout * 1000, () =>
              findDiagramFrame(page, entity),
            );
            // No message counter here: rely on the settle loop alone.
            let since = Date.now();
            const isIdle = () => Date.now() - since > 1000;
            await waitForDiagram(frame, { timeoutMs: opt.timeout * 1000, isIdle });
            await switchLayer(frame, opt.layer, { timeoutMs: opt.timeout * 1000, isIdle });
            since = Date.now();
            const png = await captureDiagram(page, {
              frame,
              fit: opt.fit,
              toolbar: opt.toolbar,
              guides: !opt["no-guides"],
              isIdle,
              log,
            });
            fs.mkdirSync(path.dirname(shot.out), { recursive: true });
            fs.writeFileSync(shot.out, png);
            log.info(`wrote ${shot.out} (${((Date.now() - t0) / 1000).toFixed(1)}s, full Studio)`);
            if (shot.render) await renderPng(browser, shot, opt, log);
          } catch (e) {
            failures++;
            server.keepData = true;
            log.warn(`${shot.component}: ${e.message}`);
          }
        }
      } catch (e) {
        failures += libShots.length;
        server.keepData = true;
        log.warn(e.message);
        // What the workbench showed, for diagnosis.
        const shot = path.join(paths.tmp, "studio-mode-failure.png");
        if (await page.screenshot({ path: shot }).then(() => true, () => false)) log.warn(`workbench screenshot: ${shot}`);
      } finally {
        await page.close().catch(() => {});
        await server.stop();
      }
    }
  } finally {
    await browser.close();
  }
  return failures;
}
