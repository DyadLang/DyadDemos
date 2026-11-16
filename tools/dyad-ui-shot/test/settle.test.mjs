// Finding 3: a capture that never settles is a failure, not a PNG.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { captureDiagram } from "../lib/shoot.mjs";
import { importDep, paths } from "../lib/paths.mjs";
import { quietLog, needSetup, haveSetup } from "./helpers.mjs";

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

test("a static page settles and is captured", needSetup, async () => {
  const page = await pageWith(`<p style="font:30px sans-serif">static</p>`);
  try {
    const png = await captureDiagram(page, { fit: "studio", isIdle: () => true, timeoutMs: 10000, log: quietLog });
    assert.equal(png.subarray(1, 4).toString(), "PNG");
  } finally {
    await page.close();
  }
});
