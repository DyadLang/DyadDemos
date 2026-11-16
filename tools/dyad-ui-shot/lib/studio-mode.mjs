// Optional "full Studio" mode: run the real Dyad Studio extension in
// openvscode-server, open the diagram through Studio's own command, and
// screenshot its webview in the workbench. The driver extension
// (driver-extension/) gives this script a local control channel into the
// workbench.
//
// Studio's activation waits for juliahub-vscode-auth to authenticate, so this
// mode only works on a runner with a valid JuliaHub login. Nothing here
// provides, fakes or refreshes one.
import { randomBytes } from "node:crypto";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { paths, requireSetup, childEnv } from "./paths.mjs";
import { spawnOwned, terminate } from "./procs.mjs";
import { beforeDeadline } from "./shoot.mjs";

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

// Every driver request carries the per-run token the driver was started with.
async function driver({ port, token }, method, route, body, timeoutMs = 10000) {
  const res = await fetch(`http://127.0.0.1:${port}${route}`, {
    method,
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(timeoutMs),
  });
  const out = await res.json();
  if (!res.ok) throw new Error(out.error ?? `${route}: HTTP ${res.status}`);
  return out;
}

// Poll `fn` until it returns something truthy. Each attempt is cut off at the
// deadline too, so this never runs past `timeoutMs`.
async function waitFor(what, timeoutMs, fn) {
  const until = Date.now() + timeoutMs;
  let lastErr;
  while (Date.now() < until) {
    try {
      const v = await beforeDeadline(until, what, fn);
      if (v) return v;
    } catch (e) {
      lastErr = e;
    }
    await sleep(Math.min(500, Math.max(0, until - Date.now())));
  }
  throw new Error(`timed out after ${timeoutMs / 1000}s waiting for ${what}${lastErr ? ` (${lastErr.message})` : ""}`);
}

export class StudioServer {
  constructor({ libraryDir, julia, log }) {
    this.libraryDir = libraryDir;
    this.julia = julia;
    this.log = log;
    // Fresh random tokens per run: one for the workbench connection, one for
    // the driver extension's routes.
    this.connectionToken = randomBytes(32).toString("hex");
    this.driver = { port: 0, token: randomBytes(32).toString("hex") };
  }

  // Fails if the server does not answer within `timeoutMs`.
  async start(timeoutMs = 60000) {
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
    const tokenFile = path.join(this.dataDir, "connection-token");
    fs.writeFileSync(tokenFile, this.connectionToken, { mode: 0o600 });
    this.port = await freePort();
    this.driver.port = await freePort();
    this.proc = spawnOwned(
      path.join(paths.openvscode, "bin", "openvscode-server"),
      [
        "--host", "127.0.0.1",
        "--port", String(this.port),
        "--connection-token-file", tokenFile,
        "--server-data-dir", this.dataDir,
        "--extensions-dir", installed,
        "--default-folder", this.libraryDir,
        "--disable-telemetry",
      ],
      {
        env: childEnv({
          DYAD_UI_SHOT_DRIVER_PORT: String(this.driver.port),
          DYAD_UI_SHOT_DRIVER_TOKEN: this.driver.token,
        }),
        stdio: ["ignore", "pipe", "pipe"],
      },
    );
    this.proc.stdout.on("data", (d) => this.log.debug(`[openvscode] ${String(d).trimEnd()}`));
    this.proc.stderr.on("data", (d) => this.log.debug(`[openvscode] ${String(d).trimEnd()}`));
    await waitFor("openvscode-server", timeoutMs, async () => {
      const res = await fetch(this.url(), { redirect: "manual", signal: AbortSignal.timeout(5000) });
      await res.body?.cancel();
      return res.status < 400;
    });
  }

  // The token in the URL makes the workbench set its connection cookie.
  url() {
    return `http://127.0.0.1:${this.port}/?tkn=${this.connectionToken}&folder=${encodeURIComponent(this.libraryDir)}`;
  }

  // Safe to call after a failed or partial start().
  async stop() {
    await terminate(this.proc, 5000);
    if (!this.dataDir) return;
    if (this.keepData || process.env.DYAD_UI_SHOT_KEEP_DATA) {
      this.log.info(`workbench logs kept in ${path.join(this.dataDir, "data", "logs")}`);
    } else fs.rmSync(this.dataDir, { recursive: true, force: true });
  }
}

// Load the workbench in `page` and wait for the driver extension to answer,
// all within `timeoutMs`.
export async function openWorkbench(page, server, timeoutMs = 120000) {
  const until = Date.now() + timeoutMs;
  await beforeDeadline(until, "loading the workbench", () =>
    page.goto(server.url(), { waitUntil: "domcontentloaded", timeout: timeoutMs }),
  );
  // Extensions only run in a trusted workspace. The machine setting
  // usually prevents the prompt; answer it if it shows up anyway.
  return waitFor("the workbench and the dyad-ui-shot driver", Math.max(0, until - Date.now()), async () => {
    await page
      .evaluate(() =>
        [...document.querySelectorAll(".dialog-buttons a, .dialog-buttons button")]
          .find((b) => /trust the authors/i.test(b.textContent) && /^\s*Yes/.test(b.textContent))
          ?.click(),
      )
      .catch(() => {});
    return driver(server.driver, "GET", "/status");
  });
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

// Failures are pushed to `failures`; a library that fails does not stop the
// run.
export async function runStudio(shots, opt, log, failures, { launchChrome, captureHelpers, toEntity, renderPng, checkLibrary }) {
  requireSetup("openvscode", "chrome", "node");
  const { waitForDiagram, switchLayer, captureDiagram } = captureHelpers;
  const timeoutMs = opt.timeout * 1000;
  const browser = await launchChrome(opt);
  try {
    for (const [lib, libShots] of Map.groupBy(shots, (s) => s.lib)) {
      const server = new StudioServer({ libraryDir: lib, julia: opt.julia || process.env.JULIA_EXECUTABLE || "julia +dyad-3.5.0", log });
      const done = new Set();
      let page;
      try {
        checkLibrary(lib);
        log.info(`starting openvscode-server for ${lib}`);
        // Starting the server and loading the workbench are one step, under
        // one --timeout deadline.
        const until = Date.now() + timeoutMs;
        await server.start(timeoutMs);
        page = await browser.newPage();
        await beforeDeadline(until, "opening a page", () =>
          page.setViewport({ width: opt.width, height: opt.height, deviceScaleFactor: opt.scale }),
        );
        await openWorkbench(page, server, Math.max(0, until - Date.now()));
        log.info("activating Dyad Studio (needs a valid JuliaHub login)");
        try {
          await driver(server.driver, "POST", "/activate", null, timeoutMs);
        } catch (e) {
          throw new Error(
            `Dyad Studio did not activate (${e.message}). Its activation waits for ` +
              `juliahub-vscode-auth; this mode needs a valid JuliaHub login on the runner. ` +
              `Use --mode standalone otherwise.`,
          );
        }
        for (const shot of libShots) {
          const t0 = Date.now();
          done.add(shot);
          try {
            const entity = toEntity(shot.component);
            await driver(server.driver, "POST", "/open", { component: entity }, timeoutMs).catch((e) => {
              throw new Error(
                `Dyad Studio did not open the diagram (${e.message}). Studio's commands wait until it ` +
                  `has a Julia installation and a JuliaHub login; see the "Dyad Studio Client Log" and ` +
                  `"JuliaHub Authentication" logs.`,
              );
            });
            const frame = await waitFor(`the diagram webview of ${shot.component}`, timeoutMs, () =>
              findDiagramFrame(page, entity),
            );
            // No message counter here: rely on the settle loop alone.
            let since = Date.now();
            const isIdle = () => Date.now() - since > 1000;
            await waitForDiagram(frame, { timeoutMs, isIdle });
            await switchLayer(frame, opt.layer, { timeoutMs, isIdle });
            since = Date.now();
            const png = await captureDiagram(page, {
              frame,
              fit: opt.fit,
              toolbar: opt.toolbar,
              guides: opt.guides,
              isIdle,
              timeoutMs,
              log,
            });
            fs.mkdirSync(path.dirname(shot.out), { recursive: true });
            fs.writeFileSync(shot.out, png);
            log.info(`wrote ${shot.out} (${((Date.now() - t0) / 1000).toFixed(1)}s, full Studio)`);
            if (shot.render) await renderPng(browser, shot, opt, log);
          } catch (e) {
            failures.push({ shot, error: e.message });
            server.keepData = true;
            log.warn(`${shot.component}: ${e.message}`);
          }
        }
      } catch (e) {
        for (const shot of libShots) if (!done.has(shot)) failures.push({ shot, error: e.message });
        server.keepData = true;
        log.warn(`${lib}: ${e.message}`);
        // What the workbench showed, for diagnosis.
        const shot = path.join(paths.tmp, "studio-mode-failure.png");
        const saved = page && (await beforeDeadline(Date.now() + 5000, "workbench screenshot", () => page.screenshot({ path: shot })).then(() => true, () => false));
        if (saved) log.warn(`workbench screenshot: ${shot}`);
      } finally {
        await page?.close().catch(() => {});
        await server.stop();
      }
    }
  } finally {
    await browser.close();
  }
}
