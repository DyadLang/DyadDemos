// Regenerate inter_metrics.json: the advance widths, pair kerning and ink extents of the font Dyad
// Studio draws diagram labels in, measured by Chrome's own text shaping.
//
//   node inter_metrics.mjs <chrome-headless-shell> <inter-latin-wght-normal.woff2> > inter_metrics.json
//
// Needs puppeteer-core (dyad-ui-shot's node_modules has it: run it from there or set NODE_PATH).
// The font is in Dyad Studio's .vsix, at extension/out/fonts/.
import puppeteer from "puppeteer-core";
import fs from "fs";
import os from "os";
import path from "path";

const [chrome, font] = process.argv.slice(2);
const b64 = fs.readFileSync(font).toString("base64");
const browser = await puppeteer.launch({
  executablePath: chrome,
  headless: "shell",
  args: ["--no-sandbox"],
  userDataDir: fs.mkdtempSync(path.join(os.tmpdir(), "inter-metrics-")),
});
try {
  const page = await browser.newPage();
  await page.setContent(`<style>@font-face{font-family:I;src:url(data:font/woff2;base64,${b64}) format("woff2");font-weight:100 900}</style>`);
  const res = await page.evaluate(async () => {
    await document.fonts.load("1000px I");
    const ctx = document.createElement("canvas").getContext("2d");
    ctx.font = "1000px I";
    const w = (t) => ctx.measureText(t).width;
    const chars = [];
    for (let c = 32; c < 127; c++) chars.push(String.fromCharCode(c));
    for (const c of "αβγδεθλμπρστφψωΔΘΣΦΨΩ·×–—°µ²³ℓ∂") chars.push(c);
    const advance = {}, kern = {}, ink = {};
    const r1 = (v) => Math.round(v * 10) / 10;
    for (const c of chars) {
      advance[c] = r1(w(c));
      // the painted glyph: [height above the baseline, depth below it, left bearing, right bearing]
      const m = ctx.measureText(c);
      ink[c] = [r1(m.actualBoundingBoxAscent), r1(m.actualBoundingBoxDescent), r1(-m.actualBoundingBoxLeft),
                r1(m.width - m.actualBoundingBoxRight)];
    }
    const fm = ctx.measureText("x");
    for (const a of chars) for (const b of chars) {
      const k = w(a + b) - w(a) - w(b);
      if (Math.abs(k) >= 0.5) kern[a + b] = Math.round(k);
    }
    return { advance, kern, ink, ascent: fm.fontBoundingBoxAscent, descent: fm.fontBoundingBoxDescent };
  });
  const kern = Object.fromEntries(Object.entries(res.kern).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
  process.stdout.write(JSON.stringify({
    font: "Inter, weight 400: out/fonts/inter-latin-wght-normal.woff2 of Dyad Studio 3.5.1, measured by inter_metrics.mjs",
    units_per_em: 1000, ascent: res.ascent, descent: res.descent, advance: res.advance, kern, ink: res.ink,
  }) + "\n");
} finally {
  await browser.close();
}
