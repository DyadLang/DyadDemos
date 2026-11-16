import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DEFAULT_PLACEMENT, diagramFromCliOutputs, netsOf, unplacedComponents } from "../src/adapter/dyad-cli.ts";
import { parseRenderSvg, placementFromTransform, RenderSvgError } from "../src/adapter/render-svg.ts";

const fixture = (name: string) => readFileSync(new URL(`fixtures/${name}`, import.meta.url), "utf8");

test("recovers placements from the kernel's transform", () => {
  assert.deepEqual(placementFromTransform("translate(1250 -200) rotate(0) scale(0.1 0.1)"), {
    x1: 1700,
    x2: 1800,
    y1: 250,
    y2: 350,
    rot: 0,
  });
  // A flipped extent comes back reversed.
  const p = placementFromTransform("translate(0 0) rotate(90) scale(-0.1 0.05)");
  assert.ok(p.x1 > p.x2 && p.rot === 90 && p.y2 - p.y1 === 50);
  assert.throws(() => placementFromTransform("matrix(1 0 0 1 0 0)"), RenderSvgError);
});

test("reads dyad render's SVG", () => {
  const d = parseRenderSvg(fixture("HL20Aero.render.svg"));
  assert.equal(d.components.length, 3);
  assert.equal(d.ports.length, 21);
  assert.ok(d.wires.length > 40);
  assert.equal(d.junctions.length, 10);
  for (const c of d.components) {
    assert.match(c.icon, /^<svg/);
    assert.ok(c.connectors.length > 0);
    assert.equal(c.labels.length >= 1, true);
  }
});

test("names components and ports from extract and drops junction pseudo-components", () => {
  const d = diagramFromCliOutputs("HL20Demo.shared.HL20Aero", {
    svg: fixture("HL20Aero.render.svg"),
    renderLog: fixture("HL20Aero.render.log"),
    problem: JSON.parse(fixture("HL20Aero.problem.json")),
  });
  assert.deepEqual(
    d.components.map((c) => c.name),
    ["air", "lon", "lat"],
  );
  assert.equal(d.ports[0].name, "alpha_deg");
  assert.equal(d.ports[0].labels![0].text, "alpha_deg");
  assert.ok(d.components.every((c) => c.explicitPlacement));
  // Wires meeting at junctions are put back into nets with their dots.
  assert.equal(
    d.connections.reduce((n, c) => n + c.junctions.length, 0),
    10,
  );
  assert.ok(d.connections.some((c) => c.routes.length > 1 && c.junctions.length > 0));
});

test("moves unplaced components to the kernel's default box and keeps connection ends", () => {
  const d = diagramFromCliOutputs("DrivelineSciML.DrivelineSystem", {
    svg: fixture("DrivelineSystem.render.svg"),
    renderLog: fixture("DrivelineSystem.render.log"),
    problem: JSON.parse(fixture("DrivelineSystem.problem.json")),
  });
  assert.equal(d.components.length, 7);
  for (const c of d.components) {
    assert.equal(c.explicitPlacement, false);
    assert.deepEqual(c.placement, DEFAULT_PLACEMENT);
  }
  assert.equal(d.connections.length, 6);
  assert.deepEqual(d.connections[0].ends, [
    { component: "torque", connector: "support" },
    { component: "torque_support", connector: "spline" },
  ]);
  assert.equal(d.connections[0].pathAttrs.stroke, "#aaa");
});

test("reads the missing-placement warnings", () => {
  const names = unplacedComponents(fixture("DrivelineSystem.render.log"));
  assert.ok(names.has("torque") && names.has("ground"));
});

test("netsOf joins wires at shared ends and junctions", () => {
  const nets = netsOf(
    [
      { points: [{ x: 0, y: 0 }, { x: 5, y: 0 }], attrs: { stroke: "red" } },
      { points: [{ x: 5, y: 0 }, { x: 5, y: 5 }], attrs: { stroke: "red" } },
      { points: [{ x: 9, y: 9 }, { x: 8, y: 8 }], attrs: { stroke: "blue" } },
    ],
    [{ point: { x: 5, y: 0 }, fill: "red" }],
  );
  assert.equal(nets.length, 2);
  assert.equal(nets[0].routes.length, 2);
  assert.deepEqual(nets[0].junctions, [{ x: 5, y: 0 }]);
});
