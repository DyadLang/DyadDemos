import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { autoLayout, needsAutoLayout, orthogonalRoute } from "../src/autolayout.ts";
import type { DiagramData } from "../src/model.ts";

const driveline: DiagramData = JSON.parse(readFileSync(new URL("fixtures/DrivelineSystem.diagram.json", import.meta.url), "utf8"));

test("lays out only a diagram with no placements at all", () => {
  assert.equal(needsAutoLayout(driveline), true);
  const placed = { ...driveline, components: driveline.components.map((c, i) => ({ ...c, explicitPlacement: i === 0 })) };
  assert.equal(needsAutoLayout(placed), false);
  assert.equal(needsAutoLayout({ ...driveline, components: [] }), false);
});

test("a chain flows left to right; supports and grounds hang below", () => {
  const out = autoLayout(driveline);
  const x = (n: string) => out.components.find((c) => c.name === n)!.placement.x1;
  const y = (n: string) => out.components.find((c) => c.name === n)!.placement.y1;
  const chain = ["torque", "J_eng", "isolator", "J_load", "load_damper"];
  for (let i = 0; i + 1 < chain.length; i++) assert.ok(x(chain[i]) < x(chain[i + 1]), chain[i]);
  for (const n of chain) assert.equal(y(n), 0, n);
  assert.ok(y("torque_support") > y("ground") && y("ground") > 0);
  assert.ok(x("ground") > x("load_damper"));
  // Every connection got a route between its two connectors.
  for (const c of out.connections) assert.equal(c.routes.length, 1);
});

test("orthogonal routes leave along each connector's side", () => {
  assert.deepEqual(orthogonalRoute({ x: 0, y: 0 }, "right", { x: 10, y: 0 }, "left"), [
    { x: 0, y: 0 },
    { x: 10, y: 0 },
  ]);
  assert.deepEqual(orthogonalRoute({ x: 0, y: 0 }, "right", { x: 10, y: 20 }, "top"), [
    { x: 0, y: 0 },
    { x: 10, y: 0 },
    { x: 10, y: 20 },
  ]);
  assert.deepEqual(orthogonalRoute({ x: 0, y: 0 }, "bottom", { x: 10, y: 20 }, "top"), [
    { x: 0, y: 0 },
    { x: 0, y: 10 },
    { x: 10, y: 10 },
    { x: 10, y: 20 },
  ]);
});

// The sweep: a negative row gap made the row search loop for ever.
test("rejects layout options that cannot give a layout", () => {
  const d: DiagramData = JSON.parse(readFileSync(new URL("./fixtures/DrivelineSystem.diagram.json", import.meta.url), "utf8"));
  assert.throws(() => autoLayout(d, { rowGap: -0.5 }), RangeError);
  assert.throws(() => autoLayout(d, { size: 0 }), RangeError);
  assert.throws(() => autoLayout(d, { columnGap: Number.NaN }), RangeError);
  assert.equal(autoLayout(d, { rowGap: 0 }).components.length, d.components.length);
});
