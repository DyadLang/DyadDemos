#!/usr/bin/env node
/**
 * dyad-diagram-render: draw a Dyad component's diagram like Dyad Studio does.
 *
 *   dyad-diagram-render <Lib.Component> [-d DIR] [-o OUT.png|OUT.svg] [options]
 *   dyad-diagram-render --data diagram.json [-o OUT] [options]
 */

import { writeFileSync, readFileSync } from "node:fs";
import { parseArgs } from "node:util";
import { performance } from "node:perf_hooks";
import { type DiagramData, type RenderOptions, checkRenderOptions, renderPng, renderSvg, validateDiagramData } from "../src/index.ts";
import { diagramFromDyadCli } from "../src/adapter/dyad-cli.ts";

const usage = `usage:
  dyad-diagram-render <Library.Component> [-d DIR] [-o OUT] [options]
  dyad-diagram-render --data DIAGRAM.json [-o OUT] [options]

Draw a component's diagram the way Dyad Studio's diagram view draws it.
OUT ending in .png writes a PNG, anything else (or stdout) SVG.

options:
  -d, --dir DIR        the Dyad library (default: .)
  -o, --output OUT     where to write (default: SVG on stdout)
      --data FILE      read diagram data (JSON) instead of asking the dyad CLI
      --save-data FILE also write the diagram data the drawing was made from
      --dyad PATH      the dyad executable (default: $DYAD, else dyad)
      --julia PATH     JULIA_EXECUTABLE for the dyad CLI
      --scale N        output pixels per diagram unit (default 1)
      --fit WxH        fit the drawing into W x H pixels instead (e.g. 3200x2000)
      --margin N       margin in pixels (default 48)
      --no-layout      never lay out an unplaced diagram automatically
      --time           print timings to stderr
  -h, --help`;

async function main(): Promise<number> {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      dir: { type: "string", short: "d" },
      output: { type: "string", short: "o" },
      data: { type: "string" },
      "save-data": { type: "string" },
      dyad: { type: "string" },
      julia: { type: "string" },
      scale: { type: "string" },
      fit: { type: "string" },
      margin: { type: "string" },
      "no-layout": { type: "boolean" },
      time: { type: "boolean" },
      help: { type: "boolean", short: "h" },
    },
  });
  if (values.help) {
    console.log(usage);
    return 0;
  }
  if ((positionals.length !== 1) === (values.data === undefined)) {
    console.error(usage);
    return 2;
  }
  // The options are checked before anything slow runs.
  let fit: { width: number; height: number } | undefined;
  if (values.fit !== undefined) {
    const m = /^(\d+)x(\d+)$/.exec(values.fit);
    if (!m) throw new Error(`--fit wants WxH in pixels, e.g. 3200x2000; got ${values.fit}`);
    fit = { width: Number(m[1]), height: Number(m[2]) };
  }
  const options: RenderOptions = {
    scale: numberOption("--scale", values.scale),
    fit,
    margin: numberOption("--margin", values.margin),
    layout: values["no-layout"] ? "never" : "auto",
  };
  try {
    checkRenderOptions(options);
  } catch (err) {
    throw new Error(`bad options: ${err instanceof Error ? err.message : err}`);
  }
  const warn = (message: string) => console.error(`dyad-diagram-render: warning: ${message}`);

  const t0 = performance.now();
  let data: DiagramData;
  if (values.data !== undefined) {
    data = validateDiagramData(JSON.parse(readFileSync(values.data, "utf8")));
  } else {
    data = await diagramFromDyadCli(values.dir ?? ".", positionals[0], {
      dyad: values.dyad,
      env: values.julia ? { JULIA_EXECUTABLE: values.julia } : undefined,
      onDiagnostic: warn,
    });
  }
  const t1 = performance.now();
  if (values["save-data"]) writeFileSync(values["save-data"], JSON.stringify(data, null, 1));
  const out = values.output;
  let t2: number;
  if (out?.endsWith(".png")) {
    const r = await renderPng(data, options);
    t2 = performance.now();
    for (const d of r.diagnostics) warn(d);
    writeFileSync(out, r.png);
  } else {
    const r = renderSvg(data, options);
    t2 = performance.now();
    for (const d of r.diagnostics) warn(d);
    if (out) writeFileSync(out, r.svg);
    else process.stdout.write(r.svg);
  }
  if (values.time) {
    const src = values.data !== undefined ? "read data" : "dyad CLI";
    console.error(`${src} ${(t1 - t0).toFixed(0)} ms, render ${(t2 - t1).toFixed(0)} ms`);
  }
  return 0;
}

/** A numeric option, or undefined when not given; anything but a number is an error. */
function numberOption(flag: string, value: string | undefined): number | undefined {
  if (value === undefined) return undefined;
  const n = Number(value);
  if (value.trim() === "" || !Number.isFinite(n)) throw new Error(`${flag} wants a number, got ${JSON.stringify(value)}`);
  return n;
}

main().then(
  (code) => process.exit(code),
  (err) => {
    console.error(`dyad-diagram-render: ${err instanceof Error ? err.message : err}`);
    process.exit(1);
  },
);
