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
import { type DiagramData, renderPng, renderSvg } from "../src/index.ts";
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
  const t0 = performance.now();
  let data: DiagramData;
  if (values.data !== undefined) {
    data = JSON.parse(readFileSync(values.data, "utf8"));
  } else {
    data = await diagramFromDyadCli(values.dir ?? ".", positionals[0], {
      dyad: values.dyad,
      env: values.julia ? { JULIA_EXECUTABLE: values.julia } : undefined,
    });
  }
  const t1 = performance.now();
  if (values["save-data"]) writeFileSync(values["save-data"], JSON.stringify(data, null, 1));

  let fit: { width: number; height: number } | undefined;
  if (values.fit) {
    const m = /^(\d+)x(\d+)$/.exec(values.fit);
    if (!m) throw new Error(`--fit wants WxH, got ${values.fit}`);
    fit = { width: Number(m[1]), height: Number(m[2]) };
  }
  const options = {
    scale: values.scale ? Number(values.scale) : undefined,
    fit,
    margin: values.margin ? Number(values.margin) : undefined,
    layout: values["no-layout"] ? ("never" as const) : ("auto" as const),
  };
  const out = values.output;
  let t2: number;
  if (out?.endsWith(".png")) {
    const r = await renderPng(data, options);
    t2 = performance.now();
    writeFileSync(out, r.png);
  } else {
    const r = renderSvg(data, options);
    t2 = performance.now();
    if (out) writeFileSync(out, r.svg);
    else process.stdout.write(r.svg);
  }
  if (values.time) {
    const src = values.data !== undefined ? "read data" : "dyad CLI";
    console.error(`${src} ${(t1 - t0).toFixed(0)} ms, render ${(t2 - t1).toFixed(0)} ms`);
  }
  return 0;
}

main().then(
  (code) => process.exit(code),
  (err) => {
    console.error(`dyad-diagram-render: ${err instanceof Error ? err.message : err}`);
    process.exit(1);
  },
);
