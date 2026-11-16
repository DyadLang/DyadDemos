#!/usr/bin/env node
/**
 * Render a batch of diagrams for side-by-side comparison with Studio
 * screenshots (dyad-ui-shot's PNGs).
 *
 *   node scripts/compare.ts LIST [--dyad PATH] [--julia PATH]
 *
 * Each line of LIST: `<library-dir> <Lib.Component> <out.png> [<reference.png>]`.
 * With a reference, the output is fitted to the reference's pixel size, the
 * way dyad-ui-shot's `--fit content` fits Studio's view. Prints the time each
 * diagram took (CLI data, then rendering and rasterising).
 */

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { parseArgs } from "node:util";
import { performance } from "node:perf_hooks";
import { renderSvg, svgToPng } from "../src/index.ts";
import { diagramFromDyadCli } from "../src/adapter/dyad-cli.ts";

function pngSize(file: string): { width: number; height: number } {
  const b = readFileSync(file);
  return { width: b.readUInt32BE(16), height: b.readUInt32BE(20) };
}

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: { dyad: { type: "string" }, julia: { type: "string" }, "save-data": { type: "boolean" } },
});
const list = positionals[0];
if (!list) {
  console.error("usage: compare.ts LIST [--dyad PATH] [--julia PATH] [--save-data]");
  process.exit(2);
}
const base = dirname(resolve(list));
for (const line of readFileSync(list, "utf8").split("\n")) {
  const parts = line.trim().split(/\s+/);
  if (parts.length < 3 || line.trim().startsWith("#")) continue;
  const [dir, component, out, ref] = parts.map((p, i) => (i === 1 ? p : resolve(base, p)));
  const t0 = performance.now();
  const data = await diagramFromDyadCli(dir, component, {
    dyad: values.dyad,
    env: values.julia ? { JULIA_EXECUTABLE: values.julia } : undefined,
  });
  const t1 = performance.now();
  const fit = ref ? pngSize(ref) : undefined;
  // dyad-ui-shot fits Studio's view at 2 device pixels per CSS pixel, with
  // a margin of about 24 CSS pixels.
  const r = renderSvg(data, fit ? { fit, margin: 48 } : { scale: 2 });
  const t2 = performance.now();
  const png = await svgToPng(r.svg);
  const t3 = performance.now();
  writeFileSync(out, png);
  writeFileSync(out.replace(/\.png$/, ".svg"), r.svg);
  if (values["save-data"]) writeFileSync(out.replace(/\.png$/, ".json"), JSON.stringify(data, null, 1));
  console.log(
    `${component}: ${r.width}x${r.height}  data ${(t1 - t0).toFixed(0)} ms, svg ${(t2 - t1).toFixed(0)} ms, png ${(t3 - t2).toFixed(0)} ms`,
  );
}
