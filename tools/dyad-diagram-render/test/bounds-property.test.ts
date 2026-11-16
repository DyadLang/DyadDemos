import { test } from "node:test";
import assert from "node:assert/strict";
import { DIAGRAM_SCHEMA, type DiagramData, renderDiagram, svgToPng } from "../src/index.ts";
import { decodePng } from "./png-decode.ts";

/**
 * The bounds a drawing reports must take in everything it paints: checked
 * against resvg's raster, with 1 px of slack for anti-aliasing. The canvas
 * margin is wider than any placement box, so paint outside the bounds
 * (an icon shows anywhere in its box) is not cut off by the canvas edge.
 */

const MARGIN = 320;

/** Diagram units of a drawing's pixels that are painted outside its bounds, 1 px of slack allowed. */
async function paintOutsideBounds(d: DiagramData): Promise<string[]> {
  const r = renderDiagram(d, { margin: MARGIN, style: { background: null } });
  const img = decodePng(await svgToPng(r.svg));
  const bw = Math.max(r.bounds.x1 - r.bounds.x0, 1) * r.scale;
  const bh = Math.max(r.bounds.y1 - r.bounds.y0, 1) * r.scale;
  // The bounds in pixels, as renderDiagram centres them.
  const x0 = (r.width - bw) / 2, y0 = (r.height - bh) / 2;
  const x1 = x0 + (r.bounds.x1 - r.bounds.x0) * r.scale, y1 = y0 + (r.bounds.y1 - r.bounds.y0) * r.scale;
  const outside: string[] = [];
  for (let j = 0; j < img.height; j++) {
    for (let i = 0; i < img.width; i++) {
      if (img.data[4 * (j * img.width + i) + 3] === 0) continue;
      // Pixel (i, j) covers [i, i + 1] x [j, j + 1].
      if (i + 1 < x0 - 1 || i > x1 + 1 || j + 1 < y0 - 1 || j > y1 + 1) {
        outside.push(`(${(r.bounds.x0 + (i - x0) / r.scale).toFixed(1)}, ${(r.bounds.y0 + (j - y0) / r.scale).toFixed(1)})`);
      }
    }
  }
  return outside;
}

function diagram(icon: string, placement: DiagramData["components"][number]["placement"]): DiagramData {
  return {
    schema: DIAGRAM_SCHEMA,
    name: "Lib.Bounds",
    components: [{ name: "c", placement, explicitPlacement: true, icon, connectors: [], labels: [] }],
    ports: [],
    connections: [],
    labels: [],
  };
}

// Codex finding: the T segment's reflected control point (220, 80) takes
// the curve out to x = 165, which control points alone would cut at 114.
test("a smooth curve's reflected control point counts in the bounds", async () => {
  const icon = `<svg viewBox="0 0 100 100" preserveAspectRatio="xMinYMin meet"><path d="M90 40 Q0 0 110 40 T110 80" fill="none" stroke="#000" stroke-width="2"/></svg>`;
  const d = diagram(icon, { x1: 0, y1: 0, x2: 200, y2: 100, rot: 0 });
  const r = renderDiagram(d, { margin: 0 });
  // Curve to x = 165, then half the stroke width times the miter limit, 4.
  assert.deepEqual(r.bounds, { x0: 0, y0: 0, x1: 169, y1: 100 });
  assert.deepEqual(await paintOutsideBounds(d), []);
});

/** mulberry32: a small seeded generator, so a failure can be replayed. */
function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Random valid path data over a viewBox, every command in both cases. */
function randomPath(rand: () => number, [vx, vy, vw, vh]: number[]): string {
  const pick = <T>(xs: T[]): T => xs[Math.floor(rand() * xs.length)];
  const r = (v: number) => Math.round(v * 100) / 100;
  // Coordinates up to half the viewBox past its edges; relative steps a third of it.
  const ax = () => r(vx - vw / 2 + rand() * 2 * vw);
  const ay = () => r(vy - vh / 2 + rand() * 2 * vh);
  const dx = () => r((rand() - 0.5) * (2 / 3) * vw);
  const dy = () => r((rand() - 0.5) * (2 / 3) * vh);
  const parts = [`M${ax()} ${ay()}`];
  const n = 1 + Math.floor(rand() * 6);
  for (let k = 0; k < n; k++) {
    const c = pick(["L", "H", "V", "C", "S", "Q", "T", "A", "Z", "S", "T", "M"]);
    const rel = rand() < 0.5;
    const X = rel ? dx : ax, Y = rel ? dy : ay;
    const args: number[] = [];
    switch (c) {
      case "H": args.push(X()); break;
      case "V": args.push(Y()); break;
      case "C": args.push(X(), Y(), X(), Y(), X(), Y()); break;
      case "S": case "Q": args.push(X(), Y(), X(), Y()); break;
      case "A": args.push(r(rand() * vw / 2), r(rand() * vh / 2), r(rand() * 360), +(rand() < 0.5), +(rand() < 0.5), X(), Y()); break;
      case "Z": break;
      default: args.push(X(), Y());
    }
    parts.push((rel ? c.toLowerCase() : c) + args.join(" "));
  }
  return parts.join(" ");
}

test("bounds hold every painted pixel, for random paths in random placements", { timeout: 120_000 }, async () => {
  const seed = Number(process.env.BOUNDS_SEED ?? 20261116);
  const iterations = Number(process.env.BOUNDS_ITERATIONS ?? 60);
  const rand = rng(seed);
  const pick = <T>(xs: T[]): T => xs[Math.floor(rand() * xs.length)];
  for (let k = 0; k < iterations; k++) {
    const vb = [Math.round((rand() - 0.5) * 100), Math.round((rand() - 0.5) * 100), 20 + Math.round(rand() * 180), 20 + Math.round(rand() * 180)];
    const paths = Array.from({ length: 1 + Math.floor(rand() * 2) }, () => {
      const stroke = rand() < 0.8 ? ` stroke="#000" stroke-width="${Math.round(rand() * 0.08 * Math.max(vb[2], vb[3]) * 10) / 10}"` : "";
      const fill = rand() < 0.5 ? ` fill="none"` : "";
      const cap = rand() < 0.3 ? ` stroke-linecap="${pick(["butt", "round", "square"])}"` : "";
      const join = rand() < 0.3 ? ` stroke-linejoin="${pick(["miter", "round", "bevel"])}"` : "";
      return `<path d="${randomPath(rand, vb)}"${fill}${stroke}${cap}${join}/>`;
    });
    const par = pick(["none", "xMinYMin meet", "xMidYMid meet", "xMaxYMax meet", "xMinYMax slice", "xMidYMid slice"]);
    const icon = `<svg viewBox="${vb.join(" ")}" preserveAspectRatio="${par}">${paths.join("")}</svg>`;
    // Up to 200 x 200 (diagonal 283 < MARGIN), flipped or turned at random.
    const w = 20 + Math.round(rand() * 180), h = 20 + Math.round(rand() * 180);
    const x = Math.round((rand() - 0.5) * 400), y = Math.round((rand() - 0.5) * 400);
    const [x1, x2] = rand() < 0.2 ? [x + w, x] : [x, x + w];
    const [y1, y2] = rand() < 0.2 ? [y + h, y] : [y, y + h];
    const placement = { x1, y1, x2, y2, rot: pick([0, 90, 180, 270, Math.round(rand() * 360)]) };
    const outside = await paintOutsideBounds(diagram(icon, placement));
    assert.deepEqual(
      outside.slice(0, 5),
      [],
      `case ${k} (seed ${seed}): ${outside.length} painted pixel(s) outside the bounds\nicon: ${icon}\nplacement: ${JSON.stringify(placement)}`,
    );
  }
});
