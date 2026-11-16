/**
 * The fuzz test's work, run in a worker thread so that the test can stop it
 * if it hangs (a loop in the main thread could not be interrupted). Not a
 * test file itself: it does nothing unless started as a worker.
 */
import { parentPort, workerData } from "node:worker_threads";
import { pathPoints, prepareIcon, scopeCss } from "../src/icon.ts";
import { DIAGRAM_SCHEMA, type DiagramData } from "../src/model.ts";
import { renderDiagram } from "../src/render.ts";
import { parseXml } from "../src/xml.ts";

/** A small seeded PRNG (mulberry32), so a failure can be replayed. */
function random(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const samples = {
  path: [
    "M0 0Z1 1", "M10 10 L 90 10 C 90 50 50 90 10 90 z m5 5 h10v10H5Z", "M0,0a25,25 -30 01 50,-25 l 50,-25",
    "m1e3-1e-3.5.5s1 1 2 2t3 3q1 1 2 2", "M 1 1 A 0 0 0 1 1 5 5", "M+.5-.5e+2 L-1E-2,3", "M0 0 Z Z z L1 1",
  ],
  transform: ["translate(10,20) rotate(45 5 5) scale(2,-1)", "matrix(1 0 0 1 0 0)skewX(30)", "rotate(", "scale(1e309)"],
  style: [
    "fill:url(#g);stroke:red;stroke-width:3pt", "stroke-width:2em;marker-end:url(#m)", 'fill:url("data:image/png;base64,AA")',
    "a:b;;;c:d(e;f)", "stroke:url('#g' ) ; filter : none !important", "@import 'x';", "{}}{", "/* ]]> */",
  ],
  css: [
    ".a{fill:red} #b .c{stroke:#000;stroke-width:10}", "@media print{.a{fill:red}} @import url(x.css);", ".a{fill:url(#g)",
    "}{;@;{{{}", "/* unclosed", ".a{b:url(}", "@font-face{src:url(https://x)}.b{}",
  ],
};
const alphabet = {
  path: "MmLlHhVvCcSsQqTtAaZz0123456789.-+eE ,",
  transform: "translaterotscmixkwXY(),.-0123456789 ",
  style: "abcdefilnorstuwx:;()#'\"\\/*!{}@,.- 0123456789",
  css: "abcdefilnorstuwx:;()#'\"\\/*!{}@,.-<>[] 0123456789\n",
};

/** A random string from an alphabet, or a sample cut short and mutated. */
function input(rnd: () => number, kind: keyof typeof samples): string {
  const chars = alphabet[kind];
  const pick = () => chars[Math.floor(rnd() * chars.length)];
  if (rnd() < 0.5) return Array.from({ length: Math.floor(rnd() * 40) }, pick).join("");
  const base = samples[kind][Math.floor(rnd() * samples[kind].length)];
  let s = base.slice(0, Math.floor(rnd() * (base.length + 1)));
  for (let k = Math.floor(rnd() * 4); k > 0; k--) {
    const at = Math.floor(rnd() * (s.length + 1));
    s = s.slice(0, at) + pick() + s.slice(at + (rnd() < 0.5 ? 1 : 0));
  }
  return s;
}

const attr = (v: string) => v.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
const text = (v: string) => v.replace(/&/g, "&amp;").replace(/</g, "&lt;");

function diagram(icon: string): DiagramData {
  return {
    schema: DIAGRAM_SCHEMA,
    name: "Fuzz.D",
    components: [{ name: "c", placement: { x1: 0, y1: 0, x2: 200, y2: 100, rot: 0 }, explicitPlacement: true, icon, connectors: [], labels: [] }],
    ports: [],
    connections: [],
    labels: [],
  };
}

if (parentPort) {
  const { seed, iterations } = workerData as { seed: number; iterations: number };
  const rnd = random(seed);
  for (let i = 0; i < iterations; i++) {
    const d = input(rnd, "path");
    const transform = input(rnd, "transform");
    const style = input(rnd, "style");
    const css = input(rnd, "css");
    // Report what is about to run, so a hang names its input.
    parentPort.postMessage({ i, d, transform, style, css });
    pathPoints(d);
    scopeCss(css, "z");
    const icon =
      `<svg viewBox="0 0 100 100"><style>${text(css)}</style>` +
      `<path d="${attr(d)}" style="${attr(style)}" stroke="#000" stroke-width="${Math.floor(rnd() * 50)}"/>` +
      `<g transform="${attr(transform)}"><rect width="10" height="10" style="${attr(style)}"/></g></svg>`;
    prepareIcon(icon, "s");
    renderDiagram(diagram(icon), { margin: 0 });
    // Truncated markup must fail cleanly, not hang.
    try {
      parseXml(icon.slice(0, Math.floor(rnd() * icon.length)));
    } catch {
      // A parse error is fine.
    }
  }
  parentPort.postMessage({ done: true });
}
