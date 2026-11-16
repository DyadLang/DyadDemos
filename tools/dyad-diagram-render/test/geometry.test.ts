import { test } from "node:test";
import assert from "node:assert/strict";
import { apply, boxFrame, placementMatrix } from "../src/geometry.ts";
import type { Placement } from "../src/model.ts";

/** The Dyad kernel's `iconPointOnDiagram`, as its documentation defines it. */
function kernelPoint(p: Placement, q: { x: number; y: number }) {
  const r = (Math.PI * p.rot) / 180;
  const sx = ((q.x - 500) * (p.x2 - p.x1)) / 1000;
  const sy = ((q.y - 500) * (p.y2 - p.y1)) / 1000;
  return {
    x: (p.x1 + p.x2) / 2 + sx * Math.cos(r) - sy * Math.sin(r),
    y: (p.y1 + p.y2) / 2 + sx * Math.sin(r) + sy * Math.cos(r),
  };
}

const cases: Placement[] = [
  { x1: 0, y1: 0, x2: 100, y2: 100, rot: 0 },
  { x1: 650, y1: 200, x2: 1650, y2: 1000, rot: 0 },
  { x1: 100, y1: 0, x2: 0, y2: 50, rot: 0 },
  { x1: 0, y1: 100, x2: 100, y2: 0, rot: 90 },
  { x1: -50, y1: -20, x2: 50, y2: 30, rot: 270 },
  { x1: 10, y1: 10, x2: 40, y2: 70, rot: 30 },
];

test("placementMatrix is the kernel's iconPointOnDiagram", () => {
  for (const p of cases) {
    const m = placementMatrix(p);
    for (const q of [
      { x: 0, y: 0 },
      { x: 1000, y: 250 },
      { x: 500, y: 1100 },
      { x: -50, y: 750 },
    ]) {
      const a = apply(m, q);
      const b = kernelPoint(p, q);
      assert.ok(Math.abs(a.x - b.x) < 1e-9 && Math.abs(a.y - b.y) < 1e-9, `${JSON.stringify(p)} ${JSON.stringify(q)}`);
    }
  }
});

test("boxFrame recovers centre, turn, flip and side lengths", () => {
  const f = boxFrame(placementMatrix({ x1: 0, y1: 0, x2: 200, y2: 100, rot: 90 }));
  assert.deepEqual([f.center.x, f.center.y], [100, 50]);
  assert.equal(Math.round(f.angle), 90);
  assert.equal(f.flip, false);
  assert.deepEqual([Math.round(f.width), Math.round(f.height)], [200, 100]);
  assert.equal(boxFrame(placementMatrix({ x1: 100, y1: 0, x2: 0, y2: 100, rot: 0 })).flip, true);
});
