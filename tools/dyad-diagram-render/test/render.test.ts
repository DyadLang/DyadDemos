import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DIAGRAM_SCHEMA, type DiagramData, RenderOptionError, render, renderDiagram, renderSvg, validateDiagramData } from "../src/index.ts";
import { labelAnchor, midpoint, normalizeUpright, removeOverlaps, roundedPath, simplify } from "../src/render.ts";
import { MAX_FAN_OUT, fanOut } from "../src/geometry.ts";
import { type XmlElement, parseXml, rootElement, walk } from "../src/xml.ts";

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

test("a port's labelAnchor scales with the box but neither turns nor mirrors", () => {
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

/** Every element name in an SVG document, parsed strictly. */
function elementNames(svg: string): string[] {
  const names: string[] = [];
  walk(rootElement(parseXml(svg))!, (e: XmlElement) => names.push(e.name));
  return names;
}

// Review finding 1: names from the data must not be able to end a comment
// (or anything else) and inject markup.
test("data cannot inject markup through names, labels, colours or the title", () => {
  const evil = "---><script>alert(1)</script><!--";
  const d = tiny();
  d.name = `</title><script>alert(0)</script>`;
  d.components[0].name = evil;
  d.components[0].type = `"><script>alert(2)</script>`;
  d.components[0].labels.push({ text: `<script>alert(3)</script>`, x: 500, y: -100, rot: 0 });
  d.connections[0].pathAttrs.stroke = `red"/><script>alert(4)</script><path d="`;
  d.connections[0].junctions.push({ x: 120, y: 50 });
  d.connections[0].analysisPoint = { name: "<script>alert(5)</script>" };
  d.labels.push({ text: "]]><script>alert(6)</script>", x: 0, y: 0, rot: 0 });
  const svg = render(d);
  assert.doesNotMatch(svg, /<script|<!--/);
  assert.ok(!elementNames(svg).includes("script"));
  assert.match(svg, /data-name="---&gt;&lt;script&gt;alert\(1\)&lt;\/script&gt;&lt;!--"/);
});

test("diagram data read from JSON is checked before drawing", () => {
  const ok = JSON.parse(JSON.stringify(tiny()));
  assert.equal(validateDiagramData(ok), ok);
  const bad = JSON.parse(JSON.stringify(tiny()));
  bad.components[0].placement.x1 = "0\"><script>";
  assert.throws(() => validateDiagramData(bad), /components\[0\]\.placement\.x1 should be a finite number/);
  const bad2 = JSON.parse(JSON.stringify(tiny()));
  bad2.connections[0].pathAttrs.stroke = { toString: 1 };
  assert.throws(() => validateDiagramData(bad2), /pathAttrs\.stroke should be a string/);
  assert.throws(() => validateDiagramData({ schema: "x" }), /schema/);
});

// Review finding 8: options that leave no drawing area are errors.
test("rejects options that leave no room for the drawing", () => {
  assert.throws(() => renderDiagram(tiny(), { fit: { width: 64, height: 64 } }), (e: unknown) => e instanceof RenderOptionError && /fit 64x64 leaves no room.*48 px margin/.test(e.message));
  assert.throws(() => renderDiagram(tiny(), { fit: { width: 96, height: 400 } }), RenderOptionError);
  assert.throws(() => renderDiagram(tiny(), { fit: { width: 0, height: 400 }, margin: 0 }), RenderOptionError);
  assert.throws(() => renderDiagram(tiny(), { scale: -1 }), /scale must be a number > 0/);
  assert.throws(() => renderDiagram(tiny(), { scale: Number.NaN }), RenderOptionError);
  assert.throws(() => renderDiagram(tiny(), { margin: -5 }), /margin must be/);
  assert.throws(() => renderDiagram(tiny(), { scale: 1e6 }), /limit is 32768 px/);
  // Just enough room is fine, and gives a positive viewBox.
  const r = renderDiagram(tiny(), { fit: { width: 64, height: 64 }, margin: 4 });
  assert.ok(r.scale > 0);
  const vb = /viewBox="([^"]+)"/.exec(r.svg)![1].split(" ").map(Number);
  assert.ok(vb[2] > 0 && vb[3] > 0);
});

/** One component whose icon has the given preserveAspectRatio, placed 200 x 100 at the origin. */
function aspectDiagram(par: string | undefined, extra = ""): DiagramData {
  const icon = `<svg viewBox="0 0 1000 1000"${par ? ` preserveAspectRatio="${par}"` : ""}><rect x="20" y="20" width="960" height="960" fill="#00f"/>${extra}</svg>`;
  return {
    schema: DIAGRAM_SCHEMA,
    name: "Lib.Aspect",
    components: [{ name: "c", placement: { x1: 0, y1: 0, x2: 200, y2: 100, rot: 0 }, explicitPlacement: true, icon, connectors: [], labels: [] }],
    ports: [],
    connections: [],
    labels: [],
  };
}

// Review finding 5: the bounds follow the icon as it is actually fitted.
test("bounds follow preserveAspectRatio, as Studio fits the icon", () => {
  // Studio stretches a `none` icon over the whole 200 x 100 box.
  assert.deepEqual(renderDiagram(aspectDiagram("none"), { margin: 0 }).bounds, { x0: 0, y0: 0, x1: 200, y1: 100 });
  // The default (xMidYMid meet) draws a centred 100 x 100 square.
  assert.deepEqual(renderDiagram(aspectDiagram(undefined), { margin: 0 }).bounds, { x0: 50, y0: 0, x1: 150, y1: 100 });
  assert.deepEqual(renderDiagram(aspectDiagram("xMinYMin meet"), { margin: 0 }).bounds, { x0: 0, y0: 0, x1: 100, y1: 100 });
  // `slice` covers the box and is cut to it.
  assert.deepEqual(renderDiagram(aspectDiagram("xMaxYMid slice"), { margin: 0 }).bounds, { x0: 0, y0: 0, x1: 200, y1: 100 });
  // Content outside the viewBox shows within the box (Studio cuts icons to
  // their box): this square ends at 1250 icon units, 125 diagram units.
  const over = renderDiagram(aspectDiagram("xMinYMin meet", `<rect x="1050" y="400" width="200" height="200"/>`), { margin: 0 });
  assert.deepEqual(over.bounds, { x0: 0, y0: 0, x1: 125, y1: 100 });
  // Content that cannot be measured may show anywhere in the box.
  const text = renderDiagram(aspectDiagram("xMinYMin meet", `<text x="1050" y="400">t</text>`), { margin: 0 });
  assert.deepEqual(text.bounds, { x0: 0, y0: 0, x1: 200, y1: 100 });
  assert.match(over.svg, /preserveAspectRatio="xMinYMin meet"[^>]*overflow="hidden"|overflow="hidden"[^>]*preserveAspectRatio/);
  // Turned by 90 degrees, a stretched icon spans 100 x 200.
  const turned = aspectDiagram("none");
  turned.components[0].placement.rot = 90;
  assert.deepEqual(renderDiagram(turned, { margin: 0 }).bounds, { x0: 50, y0: -50, x1: 150, y1: 150 });
});

/** A gain-like component with a parameter label above and its name below. */
function turnedDiagram(placement: { x1: number; y1: number; x2: number; y2: number; rot: number }): DiagramData {
  return {
    schema: DIAGRAM_SCHEMA,
    name: "Lib.Turned",
    components: [
      {
        name: "g",
        placement,
        explicitPlacement: true,
        icon: box,
        connectors: [],
        labels: [
          { text: "name", x: 500, y: 1100, rot: 0 },
          { text: "k=1", x: 500, y: -100, rot: 0 },
        ],
      },
    ],
    ports: [],
    connections: [],
    labels: [],
  };
}

function labelAt(svg: string, text: string): { x: number; rot: number; y: number } {
  const m = new RegExp(`<text x="([\\d.-]+)" y="([\\d.-]+)"(?: transform="rotate\\(([\\d.-]+) [^"]*")?>${text}</text>`).exec(svg)!;
  return { x: Number(m[1]), y: Number(m[2]), rot: Number(m[3] ?? 0) };
}

// Measured on Studio 3.5.1 (dyad-ui-shot): a component's labels turn and
// mirror with it; text turned by 90 reads top to bottom, by 270 bottom to
// top, and by 180 is drawn upright.
test("component labels turn and mirror with the component, as in Studio", () => {
  const at = (p: { x1: number; y1: number; x2: number; y2: number; rot: number }) => {
    const svg = renderSvg(turnedDiagram(p)).svg;
    return { name: labelAt(svg, "name"), k: labelAt(svg, "k=1") };
  };
  // Upright: name below (y 110), parameter above (y -10).
  let l = at({ x1: 0, y1: 0, x2: 100, y2: 100, rot: 0 });
  assert.equal(l.name.x, 50);
  assert.equal(l.name.rot, 0);
  assert.ok(l.name.y > 110 && l.k.y < 0);
  // 90: name on the left, parameter on the right, reading top to bottom.
  l = at({ x1: 0, y1: 0, x2: 100, y2: 100, rot: 90 });
  assert.equal(l.name.x, -10);
  assert.equal(l.k.x, 110);
  assert.equal(l.name.rot, 90);
  // 180: swapped, upright.
  l = at({ x1: 0, y1: 0, x2: 100, y2: 100, rot: 180 });
  assert.ok(l.name.y < 0 && l.k.y > 100);
  assert.equal(l.name.rot, 0);
  // 270: name on the right, reading bottom to top.
  l = at({ x1: 0, y1: 0, x2: 100, y2: 100, rot: 270 });
  assert.equal(l.name.x, 110);
  assert.equal(l.name.rot, -90);
  // Mirrored left-right: labels stay where they were.
  l = at({ x1: 100, y1: 0, x2: 0, y2: 100, rot: 0 });
  assert.ok(l.name.y > 110 && l.k.y < 0);
  // Mirrored top-bottom: name above, parameter below, text upright.
  l = at({ x1: 0, y1: 100, x2: 100, y2: 0, rot: 0 });
  assert.ok(l.name.y < 0 && l.k.y > 100);
  assert.equal(l.name.rot, 0);
  // Mirrored and turned by 90: like the 90 case.
  l = at({ x1: 100, y1: 0, x2: 0, y2: 100, rot: 90 });
  assert.equal(l.name.x, -10);
  assert.equal(l.name.rot, 90);
  assert.deepEqual([0, 90, 180, 270, 360, -90, 135].map(normalizeUpright), [0, 90, 0, -90, 0, -90, -45]);
});

// Review finding 6: analysis points, clocks, render styles and array connectors.
test("draws an analysis point as Studio does: a crosshair mid-wire, its name above", () => {
  const d = tiny();
  d.connections[0].analysisPoint = { name: "u" };
  const r = renderSvg(d);
  assert.match(r.svg, /<g id="analysis-points">\n<g class="analysis-point"><circle cx="125" cy="50" r="12" fill="#ffffff" stroke="rgb\(0,0,127\)" stroke-width="2"\/>/);
  assert.match(r.svg, /<circle cx="125" cy="50" r="3.75" fill="rgb\(0,0,127\)"\/>/);
  assert.match(r.svg, /<text x="125" y="27.75"[^>]*font-size="20" fill="rgb\(0,0,127\)"[^>]*>u<\/text>/);
  // Drawn after the junctions and before the labels.
  assert.ok(r.svg.indexOf('id="junctions"') < r.svg.indexOf('id="analysis-points"'));
  assert.ok(r.svg.indexOf('id="analysis-points"') < r.svg.indexOf('id="labels"'));
  assert.deepEqual(midpoint([{ x: 0, y: 0 }, { x: 10, y: 0 }, { x: 10, y: 30 }]), { x: 10, y: 10 });
});

test("clock information is reported, never dropped silently", () => {
  const d = tiny();
  d.connections[0].isClocked = true;
  d.components[0].connectors[0].clockInfo = { kind: "periodic" };
  const r = renderSvg(d);
  assert.ok(r.diagnostics.some((m) => /1 clocked connection/.test(m)));
  assert.ok(r.diagnostics.some((m) => /connector gain\.u: clock information is not drawn/.test(m)));
  assert.deepEqual(renderSvg(tiny()).diagnostics, []);
});

test("the markers render style is drawn like standard, as Studio 3.5.1 draws it", () => {
  const d = tiny();
  d.connections[0].renderStyle = "markers";
  assert.equal(render(d), render(tiny()));
});

test("array connectors fan out when their placement's show allows, as in Studio", () => {
  // The kernel's and Studio's rule: 3 copies along the left edge, pitch 200.
  const p = { x1: -100, y1: 450, x2: 0, y2: 550, rot: 0 };
  assert.deepEqual(fanOut(p, 3, 5).map((q) => [q.y1, q.y2]), [[250, 350], [450, 550], [650, 750]]);
  assert.deepEqual(fanOut(p, 3, undefined).map((q) => [q.y1, q.y2]), [[250, 350], [450, 550], [650, 750]]);
  assert.equal(fanOut(p, 6, 5).length, 1);
  assert.equal(fanOut(p, 9, undefined).length, 1);
  // An interior connector is cut into cells.
  assert.deepEqual(fanOut({ x1: 300, y1: 450, x2: 700, y2: 550, rot: 0 }, 4, 4).map((q) => [q.x1, q.x2]), [[300, 400], [400, 500], [500, 600], [600, 700]]);

  const count = (d: DiagramData) => (render(d).match(/<polygon/g) ?? []).length;
  const d = tiny();
  const u = d.components[0].connectors[0];
  u.placement = p;
  u.count = 3;
  assert.equal(count(d), 2, "without show an array connector is drawn once (port + connector)");
  u.show = 5;
  assert.equal(count(d), 4, "with show >= count it is drawn once per element");
  u.show = 2;
  assert.equal(count(d), 2);
});

// Re-check finding 4: boundary array ports fan out like connectors. Studio
// 3.5.1 draws `RenderRef.ArrayBlock`'s `u` (count 3, show 5, placed at
// x -100..0, y 450..550) as three triangles at y 250, 450 and 650, with the
// name below the first only.
test("boundary array ports fan out as in Studio, the label under the first copy", () => {
  const d = tiny();
  d.ports.push({
    name: "u",
    placement: { x1: -100, y1: 450, x2: 0, y2: 550, rot: 0 },
    icon: triangle,
    labels: [{ text: "u", x: 500, y: 1100, rot: 0 }],
    count: 3,
    show: 5,
  });
  const polygons = (r: string) => (r.match(/<polygon/g) ?? []).length;
  const r = renderDiagram(d, { margin: 0 });
  assert.equal(polygons(r.svg), 5, "IN, gain.u and three copies of u");
  const centres = [...r.svg.matchAll(/<g transform="matrix\(1 0 0 1 (-?[\d.]+) (-?[\d.]+)\)"><g class="i\w+"><svg[^>]*><polygon/g)].map((m) => [Number(m[1]), Number(m[2])]);
  assert.deepEqual(centres.filter(([x]) => x === -50), [[-50, 300], [-50, 500], [-50, 700]]);
  const labels = [...r.svg.matchAll(/<text x="(-?[\d.]+)" y="(-?[\d.]+)"[^>]*>u<\/text>/g)];
  assert.equal(labels.length, 1);
  assert.equal(Number(labels[0][1]), -50);
  // 22.5 below the first copy's (500, 1100) anchor, at y 360, plus half a cap height.
  assert.ok(Math.abs(Number(labels[0][2]) - (382.5 + (0.727 * 16) / 2)) < 0.01);
  assert.equal(r.bounds.y1, 750);
  // Without show, or longer than show, a port is drawn once, as a connector is.
  d.ports[1].show = undefined;
  assert.equal(polygons(render(d)), 3);
  d.ports[1].show = 2;
  assert.equal(polygons(render(d)), 3);
});

test("fanOut draws arrays longer than MAX_FAN_OUT once instead of looping over them", () => {
  const p = { x1: 300, y1: 450, x2: 700, y2: 550, rot: 0 };
  assert.equal(fanOut(p, MAX_FAN_OUT, undefined).length, MAX_FAN_OUT);
  assert.equal(fanOut(p, 1e9, 1e9).length, 1);
});

// Re-check finding 3: Studio draws a heavy stroke past the fitted viewBox, up
// to the placement box (`RenderRef.StrokeRef`: the 400-wide red line at
// x = 980 of a 0..1000 viewBox, in a 400 x 200 box at x 100..500, reaches
// x = 436); the bounds take it in.
test("bounds include an icon's stroke beyond its viewBox, as Studio draws it", () => {
  const icon = readFileSync(new URL("./fixtures/RenderRef/assets/stroke-wide.svg", import.meta.url), "utf8");
  const d = aspectDiagram(undefined);
  d.components[0].icon = icon;
  d.components[0].placement = { x1: 100, y1: 400, x2: 500, y2: 600, rot: 0 };
  assert.deepEqual(renderDiagram(d, { margin: 0 }).bounds, { x0: 200, y0: 400, x1: 436, y1: 600 });
});

// Re-check finding 5: a drawing smaller than a pixel is an error up front.
test("rejects a scale that leaves less than one pixel", () => {
  assert.throws(
    () => renderDiagram(tiny(), { scale: 0.0001, margin: 0 }),
    (e: unknown) => e instanceof RenderOptionError && /would be 0x0 px.*at least 1x1 px/.test(e.message),
  );
  assert.throws(() => renderDiagram(tiny(), { fit: { width: 0.4, height: 0.4 }, margin: 0 }), RenderOptionError);
  // A tiny scale with a margin is fine: the margin alone is a drawing.
  assert.equal(renderDiagram(tiny(), { scale: 0.0001, margin: 1 }).width, 2);
});
