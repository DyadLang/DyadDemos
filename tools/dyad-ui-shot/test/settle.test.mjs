// Finding 3: a capture that never settles is a failure, not a PNG.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { captureDiagram } from "../lib/shoot.mjs";
import { importDep, paths } from "../lib/paths.mjs";
import { quietLog, needSetup, haveSetup, tmpDir } from "./helpers.mjs";

let browser;
before(async () => {
  if (!haveSetup) return;
  const puppeteer = (await importDep("puppeteer-core")).default;
  browser = await puppeteer.launch({ executablePath: paths.chrome, headless: "shell", args: ["--no-sandbox"] });
});
after(() => browser?.close());

async function pageWith(html) {
  const page = await browser.newPage();
  await page.setViewport({ width: 400, height: 300 });
  await page.setContent(html);
  return page;
}

test("a page that never stops changing fails within the timeout", needSetup, async () => {
  const page = await pageWith(`<div id="n" style="font:40px sans-serif"></div>
    <script>let i = 0; (function tick() { n.textContent = i++; requestAnimationFrame(tick); })();</script>`);
  try {
    const t0 = Date.now();
    await assert.rejects(
      captureDiagram(page, { fit: "studio", isIdle: () => true, timeoutMs: 2000, log: quietLog }),
      /did not settle in time/,
    );
    assert.ok(Date.now() - t0 < 6000, `took ${Date.now() - t0} ms`);
  } finally {
    await page.close();
  }
});

test("a busy message channel also keeps the capture from settling", needSetup, async () => {
  const page = await pageWith(`<p>static</p>`);
  try {
    await assert.rejects(
      captureDiagram(page, { fit: "studio", isIdle: () => false, timeoutMs: 1500, log: quietLog }),
      /did not settle in time.*"idle":false/,
    );
  } finally {
    await page.close();
  }
});

test("an image that never loads keeps the capture from settling", needSetup, async () => {
  const page = await browser.newPage();
  try {
    await page.setViewport({ width: 400, height: 300 });
    await page.setRequestInterception(true);
    page.on("request", (req) => {
      if (req.url().endsWith("/hang.png")) return; // never answered
      req.respond({ status: 200, contentType: "text/html", body: `<img src="/hang.png">` });
    });
    await page.goto("http://test.invalid/", { waitUntil: "domcontentloaded" });
    await assert.rejects(
      captureDiagram(page, { fit: "studio", isIdle: () => true, timeoutMs: 1500, log: quietLog }),
      /loading fonts and images: timed out|did not settle in time/,
    );
  } finally {
    await page.close();
  }
});

// The deadline holds even when the page stops answering: Puppeteer's own
// protocol timeout (minutes) must not be what ends the capture. Like the CLI,
// write the PNG only if the capture returns one.
async function captureToFile(page, timeoutMs) {
  const out = path.join(tmpDir("stall"), "shot.png");
  const t0 = Date.now();
  const err = await captureDiagram(page, { fit: "studio", isIdle: () => true, timeoutMs, log: quietLog }).then(
    (png) => fs.writeFileSync(out, png),
    (e) => e,
  );
  return { err, ms: Date.now() - t0, written: fs.existsSync(out) };
}

const DEADLINE = 200;
const MARGIN = 500;

test("stalled animation frames: the capture fails at its deadline, no PNG written", { ...needSetup, timeout: 20000 }, async () => {
  const page = await pageWith(`<p style="font:30px sans-serif">static</p>`);
  try {
    // Animation-frame callbacks never run; everything else still answers.
    await page.evaluate(() => (window.requestAnimationFrame = () => 0));
    const r = await captureToFile(page, DEADLINE);
    assert.match(r.err?.message ?? "", /did not settle in time.*waiting for an animation frame: timed out/);
    assert.ok(r.ms < DEADLINE + MARGIN, `took ${r.ms} ms with a ${DEADLINE} ms deadline`);
    assert.equal(r.written, false);
  } finally {
    await page.close();
  }
});

test("a page whose main thread hangs: the capture fails at its deadline, no PNG written", { ...needSetup, timeout: 20000 }, async () => {
  const page = await pageWith(`<p style="font:30px sans-serif">static</p>`);
  try {
    // Every evaluate (and the screenshot) now waits on a renderer that never
    // returns to its event loop.
    await page.evaluate(() => setTimeout(() => { for (;;); }, 0));
    const r = await captureToFile(page, DEADLINE);
    assert.match(r.err?.message ?? "", /timed out/);
    assert.ok(r.ms < DEADLINE + MARGIN, `took ${r.ms} ms with a ${DEADLINE} ms deadline`);
    assert.equal(r.written, false);
  } finally {
    await page.close();
  }
});

test("a static page settles and is captured", needSetup, async () => {
  const page = await pageWith(`<p style="font:30px sans-serif">static</p>`);
  try {
    const png = await captureDiagram(page, { fit: "studio", isIdle: () => true, timeoutMs: 10000, log: quietLog });
    assert.equal(png.subarray(1, 4).toString(), "PNG");
  } finally {
    await page.close();
  }
});
