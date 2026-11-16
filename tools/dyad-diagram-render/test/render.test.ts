import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DIAGRAM_SCHEMA, type DiagramData, render, renderDiagram, renderSvg } from "../src/index.ts";
import { labelAnchor, removeOverlaps, roundedPath, simplify } from "../src/render.ts";
import { parseXml, rootElement } from "../src/xml.ts";

const triangle = `<svg viewBox="0 0 210 210"><polygon points="5,5 205,105 5,205" fill="navy"/></svg>`;
const box = `<svg viewBox="0 0 1000 1000"><style>.b{fill:#eee}</style><rect class="b" width="1000" height="1000"/></svg>`;

function tiny(): DiagramData {
  return {
    schema: DIAGRAM_SCHEMA,
    name: "Lib.Tiny",
    components: [
      {
        name: "gain",
        placement: { x1: 200, y1: 0, x2: 300, y2: 100, rot: 0 },
        explicitPlacement: true,
        icon: box,
        connectors: [{ name: "u", placement: { x1: -50, y1: 450, x2: 50, y2: 550, rot: 0 }, icon: triangle }],
        labels: [{ text: "gain", x: 500, y: 1100, rot: 0 }],
      },
    ],
    ports: [
      {
        name: "IN",
        placement: { x1: -50, y1: 0, x2: 50, y2: 100, rot: 0 },
        icon: triangle,
        labels: [{ text: "IN", x: 500, y: 1100, rot: 0 }],
      },
    ],
    connections: [
      {
        routes: [
          [
            { x: 50, y: 50 },
            { x: 120, y: 50 },
            { x: 200, y: 50 },
          ],
        ],
        junctions: [],
        pathAttrs: { stroke: "rgb(0,0,127)" },
      },
    ],
    labels: [],
  };
}

test("renders well-formed SVG with Studio's stacking order", () => {
  const svg = render(tiny());
  const root = rootElement(parseXml(svg))!;
  assert.equal(root.name, "svg");
  const ids = svg.match(/<g id="(\w+)"/g)!.map((s) => s.slice(7, -1));
  assert.deepEqual(ids, ["components", "wires", "connectors", "junctions", "labels"]);
  assert.match(svg, /<text [^>]*>gain<\/text>/);
  assert.match(svg, /<text [^>]*>IN<\/text>/);
  assert.match(svg, /stroke="rgb\(0,0,127\)"/);
});

test("gives every icon copy its own scope", () => {
  const svg = render(tiny());
  const scopes = new Set(svg.match(/<g class="(i\w+)">/g));
  assert.equal(scopes.size, 3);
});

test("is deterministic", () => {
  assert.equal(render(tiny()), render(tiny()));
});

test("labels are a fixed size, centred on their anchor, and a port's name sits lower", () => {
  const svg = renderSvg(tiny()).svg;
  const gain = /<text x="([\d.-]+)" y="([\d.-]+)">gain<\/text>/.exec(svg)!;
  assert.equal(Number(gain[1]), 250);
  // Anchor y = 0 + 1.1 * 100 = 110; the baseline is half a cap height lower.
  assert.ok(Number(gain[2]) > 110 && Number(gain[2]) < 117);
  const port = /<text x="([\d.-]+)" y="([\d.-]+)">IN<\/text>/.exec(svg)!;
  assert.ok(Number(port[2]) > Number(gain[2]) + 20);
  assert.match(svg, /font-size="16"/);
});

test("fits the drawing into a box, keeping its aspect", () => {
  const r = renderDiagram(tiny(), { fit: { width: 800, height: 800 }, margin: 10 });
  assert.equal(Math.max(r.width, r.height), 800);
  assert.ok(r.width > r.height);
});

test("labelAnchor scales with the box but neither turns nor mirrors", () => {
  assert.deepEqual(labelAnchor({ x1: 0, y1: 0, x2: 100, y2: 100, rot: 90 }, { x: 500, y: 1100 }), { x: 50, y: 110 });
  assert.deepEqual(labelAnchor({ x1: 100, y1: 100, x2: 0, y2: 0, rot: 0 }, { x: 500, y: 1100 }), { x: 50, y: 110 });
});

test("simplify drops repeated and collinear points", () => {
  assert.deepEqual(
    simplify([
      { x: 0, y: 0 },
      { x: 0, y: 0 },
      { x: 5, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 5 },
    ]),
    [
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 5 },
    ],
  );
});

test("roundedPath rounds interior corners, never more than half a segment", () => {
  const d = roundedPath(
    [
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 4 },
    ],
    4,
  );
  assert.equal(d, "M0 0L8 0Q10 0 10 2L10 4");
});

test("removeOverlaps keeps each shared run once", () => {
  const out = removeOverlaps([
    [
      { x: 0, y: 0 },
      { x: 0, y: 100 },
    ],
    [
      { x: 0, y: 0 },
      { x: 0, y: 50 },
      { x: 30, y: 50 },
    ],
  ]);
  assert.deepEqual(out, [
    [
      { x: 0, y: 0 },
      { x: 0, y: 100 },
    ],
    [
      { x: 0, y: 50 },
      { x: 30, y: 50 },
    ],
  ]);
});

test("an icon that is not SVG is drawn as a plain box", () => {
  const d = tiny();
  d.components[0].icon = "not svg";
  assert.match(render(d), /fill="#f4f4f5"/);
});

test("the committed fixtures render", () => {
  for (const name of ["RigidBody6DOF", "DrivelineSystem"]) {
    const data = JSON.parse(readFileSync(new URL(`fixtures/${name}.diagram.json`, import.meta.url), "utf8"));
    const svg = renderSvg(data).svg;
    assert.ok(rootElement(parseXml(svg)), name);
  }
});
