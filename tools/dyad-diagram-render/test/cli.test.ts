import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const bin = fileURLToPath(new URL("../bin/dyad-diagram-render.ts", import.meta.url));
const data = fileURLToPath(new URL("fixtures/RigidBody6DOF.diagram.json", import.meta.url));

function run(...args: string[]) {
  return spawnSync(process.execPath, [bin, ...args], { encoding: "utf8" });
}

// Review finding 8, end to end.
test("--fit with no room inside the margin is an error, not a negative scale", () => {
  const r = run("--data", data, "--fit", "64x64");
  assert.equal(r.status, 1);
  assert.equal(r.stdout, "");
  assert.match(r.stderr, /bad options: fit 64x64 leaves no room for the drawing inside a 48 px margin/);
  assert.equal(run("--data", data, "--fit", "64x64", "--margin", "8").status, 0);
});

test("non-numeric or non-positive numbers are errors", () => {
  for (const args of [
    ["--scale", "abc"],
    ["--scale", "0"],
    ["--scale", ""],
    ["--margin", "-1"],
    ["--fit", "0x100"],
    ["--fit", "100"],
  ]) {
    const r = run("--data", data, ...args);
    assert.equal(r.status, 1, args.join(" "));
    assert.match(r.stderr, /^dyad-diagram-render: /, args.join(" "));
  }
});

// Review finding 1, end to end: a hostile name in --data.
test("--data with a hostile component name gives SVG without a script", () => {
  const d = JSON.parse(readFileSync(data, "utf8"));
  d.components[0].name = "---><script>alert(1)</script>";
  const file = join(mkdtempSync(join(tmpdir(), "dyad-cli-")), "evil.json");
  writeFileSync(file, JSON.stringify(d));
  const r = run("--data", file);
  assert.equal(r.status, 0, r.stderr);
  assert.doesNotMatch(r.stdout, /<script|<!--/);
  d.components[0].placement.x1 = "1";
  writeFileSync(file, JSON.stringify(d));
  const bad = run("--data", file);
  assert.equal(bad.status, 1);
  assert.match(bad.stderr, /components\[0\]\.placement\.x1 should be a finite number/);
});

test("renderer diagnostics are printed as warnings", () => {
  const d = JSON.parse(readFileSync(data, "utf8"));
  d.components[0].icon = `<svg viewBox="0 0 10 10"><script>alert(1)</script></svg>`;
  const file = join(mkdtempSync(join(tmpdir(), "dyad-cli-")), "icon.json");
  writeFileSync(file, JSON.stringify(d));
  const r = run("--data", file);
  assert.equal(r.status, 0);
  assert.match(r.stderr, /^dyad-diagram-render: warning: component \S+: icon: dropped <script>$/m);
});

test("a PNG too big for the rasteriser fails with advice", () => {
  const out = join(mkdtempSync(join(tmpdir(), "dyad-cli-")), "big.png");
  const r = run("--data", data, "--scale", "4", "-o", out);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /more than the rasteriser's 67108864 pixels; use a smaller --scale or --fit/);
});
