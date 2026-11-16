#!/usr/bin/env node
// dyad-ui-shot: screenshot Dyad component diagrams as Dyad Studio draws them.
// See README.md.
import fs from "node:fs";
import path from "node:path";
import { parseArgs } from "node:util";
import { spawnSync } from "node:child_process";
import { paths, requireSetup, importDep, childEnv, VERSIONS } from "./lib/paths.mjs";

const USAGE = `\
usage: dyad-ui-shot <library-dir> <Lib.Component> <out.png> [options]
       dyad-ui-shot --batch <list-file> [options]

Opens the component's diagram in Dyad Studio ${VERSIONS.DYAD_STUDIO_VERSION}'s diagram view (headless
Chrome), fits it to view, waits for rendering to settle and writes a PNG.

A batch list has one shot per line: <library-dir> <Lib.Component> <out.png>
[<render.png>]. Relative paths are relative to the list file; blank lines and
lines starting with # are skipped. Shots of the same library share one
language server.

options:
  --width N          viewport width in CSS px (default 1600)
  --height N         viewport height in CSS px (default 1000)
  --fit MODE         content: zoom to the whole drawn diagram and crop the PNG
                     to it (default)
                     studio: Studio's own "Fit to view" button, which fits the
                     1000x1000 canvas box; PNG is the whole viewport
  --scale N          device pixel ratio of the PNG (default 2)
  --toolbar          keep Studio's floating diagram toolbar in the picture
  --no-guides        hide the canvas axes and the diagram-box outline that
                     Studio draws behind every diagram
  --layer L          diagram (default) or icon
  --render-png P     also write \`dyad render\`'s SVG, rasterised by the same
                     Chrome, to P (needs setup.sh --dyad-cli)
  --mode M           standalone (default): Studio's diagram bundle fed by its
                     bundled language server, no VS Code
                     studio: full Dyad Studio in openvscode-server; needs a
                     valid JuliaHub login on the runner (setup.sh --studio)
  --julia CMD        Julia command for the language server (default:
                     $JULIA_EXECUTABLE, else "julia +dyad-3.5.0")
  --no-instantiate   do not run Pkg.instantiate() when Manifest.toml is missing
  --timeout S        per-diagram render timeout in seconds (default 120)
  --verbose          debug logging
  -h, --help         this text
`;

function makeLog(verbose) {
  const ts = () => new Date().toISOString().slice(11, 19);
  return {
    debug: verbose ? (m) => console.error(`${ts()} debug ${m}`) : () => {},
    info: (m) => console.error(`${ts()} ${m}`),
    warn: (m) => console.error(`${ts()} WARN ${m}`),
  };
}

// "Lib.Comp" -> "urn:definition:Lib::Comp", "Lib.a.b.Comp" -> "urn:definition:Lib:a.b:Comp"
function toEntity(name) {
  if (name.startsWith("urn:")) return name;
  const parts = name.split(".");
  if (parts.length < 2) throw new Error(`expected Library.Component, got '${name}'`);
  return `urn:definition:${parts[0]}:${parts.slice(1, -1).join(".")}:${parts.at(-1)}`;
}

function juliaCommand(opt) {
  return (opt.julia || process.env.JULIA_EXECUTABLE || "julia +dyad-3.5.0").trim().split(/\s+/);
}

// The language server resolves a library's Dyad dependencies by running Julia
// against its Manifest.toml, so the library must be instantiated. Offline only:
// this never contacts a package server.
function ensureManifest(libDir, opt, log) {
  if (fs.readdirSync(libDir).some((f) => /^(Julia)?Manifest(-v[\d.]+)?\.toml$/.test(f))) return;
  if (opt["no-instantiate"]) {
    log.warn(`${libDir} has no Manifest.toml; Dyad dependencies will not resolve`);
    return;
  }
  log.info(`instantiating ${libDir} (offline)`);
  const [exe, ...pre] = juliaCommand(opt);
  const r = spawnSync(exe, [...pre, "--startup-file=no", `--project=${libDir}`, "-e", "using Pkg; Pkg.instantiate()"], {
    env: childEnv({ JULIA_PKG_OFFLINE: "true", JULIA_PKG_PRECOMPILE_AUTO: "0" }),
    encoding: "utf8",
  });
  if (r.status !== 0) {
    throw new Error(
      `Pkg.instantiate() failed in ${libDir}; instantiate it yourself and retry:\n${(r.stderr || "").split("\n").slice(-15).join("\n")}`,
    );
  }
}

function parseBatch(file) {
  const base = path.dirname(path.resolve(file));
  return fs
    .readFileSync(file, "utf8")
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => {
      const [lib, component, out, render] = l.split(/\s+/);
      if (!out) throw new Error(`bad batch line (need <library-dir> <Lib.Component> <out.png>): ${l}`);
      return {
        lib: path.resolve(base, lib),
        component,
        out: path.resolve(base, out),
        render: render ? path.resolve(base, render) : null,
      };
    });
}

async function launchChrome(opt) {
  const puppeteer = (await importDep("puppeteer-core")).default;
  return puppeteer.launch({
    executablePath: paths.chrome,
    headless: "shell",
    env: childEnv(),
    args: [
      "--no-sandbox",
      "--hide-scrollbars",
      "--font-render-hinting=none",
      "--disable-gpu",
    ],
  });
}

// `dyad render` SVG, rasterised by the same Chrome at the same viewport size,
// for side-by-side comparisons.
async function renderPng(browser, shot, opt, log) {
  const r = spawnSync(paths.dyadCli, ["render", shot.component, "--dir", shot.lib], {
    encoding: "utf8",
    env: childEnv(),
    maxBuffer: 256 << 20,
  });
  if (r.status !== 0 || !r.stdout.includes("<svg")) throw new Error(`dyad render failed: ${r.stderr || r.stdout}`);
  const page = await browser.newPage();
  try {
    await page.setViewport({ width: opt.width, height: opt.height, deviceScaleFactor: opt.scale });
    await page.setContent(
      `<!doctype html><html><body style="margin:0;background:#fff">${r.stdout}</body></html>`,
    );
    // dyad render writes viewBox="0 0 1000 1000" with overflow visible, and its
    // transform-origin="center center" resolves against the outermost svg
    // viewport, so the viewBox must stay as is: the drawn content is measured
    // in page space, then cropped and scaled by an HTML wrapper.
    const clip = await page.evaluate(
      ({ w, h, pad }) => {
        const s = document.querySelector("svg");
        s.setAttribute("width", 1000);
        s.setAttribute("height", 1000);
        Object.assign(s.style, { overflow: "visible", position: "absolute", left: "0", top: "0" });
        const zoom = document.createElement("div");
        const crop = document.createElement("div");
        s.parentNode.insertBefore(zoom, s);
        zoom.appendChild(crop);
        crop.appendChild(s);
        Object.assign(crop.style, { position: "relative", overflow: "hidden" });
        const r0 = s.getBoundingClientRect();
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const e of s.querySelectorAll("path,rect,circle,ellipse,line,polyline,polygon,text,image,use")) {
          if (e.closest("defs,pattern,clipPath,mask,marker,symbol")) continue;
          const cs = getComputedStyle(e);
          if (cs.visibility === "hidden" || cs.display === "none") continue;
          let { left: l, top: t, right: rr, bottom: b } = e.getBoundingClientRect();
          // Clip to enclosing nested <svg> viewports that do not overflow.
          for (let a = e.parentElement; a && a !== s; a = a.parentElement) {
            if (a.tagName.toLowerCase() === "svg" && getComputedStyle(a).overflow !== "visible") {
              const v = a.getBoundingClientRect();
              l = Math.max(l, v.left); t = Math.max(t, v.top); rr = Math.min(rr, v.right); b = Math.min(b, v.bottom);
            }
          }
          if (rr < l || b < t || (rr === l && b === t)) continue;
          x0 = Math.min(x0, l); y0 = Math.min(y0, t); x1 = Math.max(x1, rr); y1 = Math.max(y1, b);
        }
        const x = x0 - r0.left - pad, y = y0 - r0.top - pad, cw = x1 - x0 + 2 * pad, ch = y1 - y0 + 2 * pad;
        s.style.left = `${-x}px`;
        s.style.top = `${-y}px`;
        crop.style.width = `${cw}px`;
        crop.style.height = `${ch}px`;
        const k = Math.min(w / cw, h / ch);
        zoom.style.transform = `scale(${k})`;
        zoom.style.transformOrigin = "0 0";
        return { x: 0, y: 0, width: Math.ceil(cw * k), height: Math.ceil(ch * k) };
      },
      { w: opt.width, h: opt.height, pad: 24 },
    );
    fs.mkdirSync(path.dirname(shot.render), { recursive: true });
    await page.screenshot({ path: shot.render, type: "png", clip });
    log.info(`wrote ${shot.render} (dyad render)`);
  } finally {
    await page.close();
  }
}

async function runStandalone(shots, opt, log) {
  requireSetup("studio", "chrome", "node");
  const { DyadLanguageServer } = await import("./lib/lsp.mjs");
  const { StudioWebview } = await import("./lib/webview.mjs");
  const { waitForDiagram, switchLayer, captureDiagram } = await import("./lib/shoot.mjs");

  const browser = await launchChrome(opt);
  let failures = 0;
  try {
    const byLib = Map.groupBy(shots, (s) => s.lib);
    for (const [lib, libShots] of byLib) {
      ensureManifest(lib, opt, log);
      log.info(`starting language server for ${lib}`);
      const server = new DyadLanguageServer({ libraryDir: lib, julia: juliaCommand(opt).join(" "), log });
      await server.start();
      try {
        // Waits for the workspace (and its Julia dependency resolution) to load.
        await server.tree();
        for (const shot of libShots) {
          const t0 = Date.now();
          const view = new StudioWebview({ browser, server, log });
          try {
            const entity = toEntity(shot.component);
            await view.open(entity, { width: opt.width, height: opt.height, scale: opt.scale });
            const isIdle = () => view.inflight === 0 && Date.now() - view.lastActivity > 300;
            const waitOpts = { timeoutMs: opt.timeout * 1000, isIdle, fatal: () => view.fatal };
            await waitForDiagram(view.page.mainFrame(), waitOpts);
            await switchLayer(view.page.mainFrame(), opt.layer, waitOpts);
            const png = await captureDiagram(view.page, {
              fit: opt.fit,
              toolbar: opt.toolbar,
              guides: !opt["no-guides"],
              isIdle,
              log,
            });
            fs.mkdirSync(path.dirname(shot.out), { recursive: true });
            fs.writeFileSync(shot.out, png);
            log.info(`wrote ${shot.out} (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
            if (view.errors.length) log.warn(`page errors for ${shot.component}:\n  ${view.errors.join("\n  ")}`);
            if (shot.render) await renderPng(browser, shot, opt, log);
          } catch (e) {
            failures++;
            log.warn(`${shot.component}: ${e.message}`);
            if (view.errors.length) log.warn(`page errors:\n  ${view.errors.join("\n  ")}`);
          } finally {
            await view.close();
          }
        }
      } finally {
        await server.stop();
      }
    }
  } finally {
    await browser.close();
  }
  return failures;
}

async function main() {
  const { values: opt, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      batch: { type: "string" },
      width: { type: "string", default: "1600" },
      height: { type: "string", default: "1000" },
      fit: { type: "string", default: "content" },
      scale: { type: "string", default: "2" },
      toolbar: { type: "boolean", default: false },
      "no-guides": { type: "boolean", default: false },
      layer: { type: "string", default: "diagram" },
      "render-png": { type: "string" },
      mode: { type: "string", default: "standalone" },
      julia: { type: "string" },
      "no-instantiate": { type: "boolean", default: false },
      timeout: { type: "string", default: "120" },
      verbose: { type: "boolean", default: false },
      help: { type: "boolean", short: "h", default: false },
    },
  });
  if (opt.help) {
    process.stdout.write(USAGE);
    return 0;
  }
  for (const k of ["width", "height", "scale", "timeout"]) {
    opt[k] = Number(opt[k]);
    if (!(opt[k] > 0)) throw new Error(`--${k} must be a positive number`);
  }
  if (!["studio", "content"].includes(opt.fit)) throw new Error(`--fit must be studio or content`);
  if (!["diagram", "icon"].includes(opt.layer)) throw new Error(`--layer must be diagram or icon`);
  const log = makeLog(opt.verbose);

  let shots;
  if (opt.batch) {
    if (positionals.length) throw new Error("--batch takes no positional arguments");
    shots = parseBatch(opt.batch);
  } else {
    if (positionals.length !== 3) {
      process.stderr.write(USAGE);
      return 2;
    }
    const [lib, component, out] = positionals;
    shots = [{ lib: path.resolve(lib), component, out: path.resolve(out), render: opt["render-png"] ? path.resolve(opt["render-png"]) : null }];
  }
  for (const s of shots) {
    if (!fs.existsSync(path.join(s.lib, "Project.toml"))) throw new Error(`${s.lib} has no Project.toml`);
    if (!fs.existsSync(path.join(s.lib, "dyad"))) throw new Error(`${s.lib} has no dyad/ folder`);
  }
  if (shots.some((s) => s.render)) requireSetup("dyadCli");

  let failures;
  if (opt.mode === "standalone") failures = await runStandalone(shots, opt, log);
  else if (opt.mode === "studio") {
    const { runStudio } = await import("./lib/studio-mode.mjs");
    failures = await runStudio(shots, opt, log, { launchChrome, captureHelpers: await import("./lib/shoot.mjs"), toEntity, renderPng });
  } else throw new Error(`--mode must be standalone or studio`);
  if (failures) log.warn(`${failures} of ${shots.length} shot(s) failed`);
  return failures ? 1 : 0;
}

main().then(
  (code) => process.exit(code),
  (e) => {
    console.error(`dyad-ui-shot: ${e.message}`);
    process.exit(1);
  },
);
