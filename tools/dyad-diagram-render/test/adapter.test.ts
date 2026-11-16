import { test } from "node:test";
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  DEFAULT_PLACEMENT,
  DyadCliError,
  absolutePathLike,
  analysisPointsIn,
  componentSource,
  diagramFromCliOutputs,
  diagramFromDyadCli,
  netsOf,
  runDyadCli,
  unplacedComponents,
} from "../src/adapter/dyad-cli.ts";
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

/** A stand-in for the dyad CLI: logs where and how it ran, prints fixtures. */
function fakeDyad(dir: string): string {
  const script = join(dir, "bin", "fake-dyad");
  mkdirSync(join(dir, "bin"), { recursive: true });
  writeFileSync(
    script,
    `#!/bin/sh
printf '%s\\n' "$(pwd)" "$*" "$JULIA_EXECUTABLE" >> "$FAKE_LOG"
case "$1" in
  render) cat "$FAKE_SVG"; printf '%s' "$FAKE_RENDER_ERR" >&2; exit \${FAKE_RENDER_EXIT:-0};;
  layout) cat "$FAKE_PROBLEM"; printf '%s' "$FAKE_EXTRACT_ERR" >&2; exit \${FAKE_EXTRACT_EXIT:-0};;
esac
exit 64
`,
  );
  chmodSync(script, 0o755);
  return script;
}

function fakeLibrary(): { root: string; log: string; env: Record<string, string> } {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "dyad-adapter-")));
  mkdirSync(join(root, "lib", "dyad"), { recursive: true });
  writeFileSync(join(root, "lib", "dyad", "features.dyad"), fixture("RenderRef/dyad/features.dyad"));
  fakeDyad(root);
  const log = join(root, "log.txt");
  const env = {
    FAKE_LOG: log,
    FAKE_SVG: fileURLToPath(new URL("fixtures/RenderRef.AnalysisPoints.render.svg", import.meta.url)),
    FAKE_PROBLEM: fileURLToPath(new URL("fixtures/RenderRef.AnalysisPoints.problem.json", import.meta.url)),
    JULIA_EXECUTABLE: "bin/julia",
  };
  return { root, log, env };
}

// Review finding 3: relative paths must not be read from inside the library.
test("resolves a relative library directory, dyad and julia path before running", async () => {
  const { root, log, env } = fakeLibrary();
  const cwd = process.cwd();
  process.chdir(root);
  try {
    const diagnostics: string[] = [];
    const d = await diagramFromDyadCli("lib", "RenderRef.AnalysisPoints", { dyad: "./bin/fake-dyad", env, onDiagnostic: (m) => diagnostics.push(m) });
    assert.equal(d.components.length, 3);
    const lines = readFileSync(log, "utf8").trim().split("\n");
    // Two commands, three lines each: working directory, arguments, JULIA_EXECUTABLE.
    assert.equal(lines.length, 6);
    for (let i = 0; i < 6; i += 3) {
      assert.equal(lines[i], join(root, "lib"));
      assert.match(lines[i + 1], new RegExp(` RenderRef\\.AnalysisPoints --dir ${join(root, "lib")}$`));
      assert.equal(lines[i + 2], join(root, "bin", "julia"));
    }
    assert.deepEqual(diagnostics, []);
  } finally {
    process.chdir(cwd);
  }
  assert.equal(absolutePathLike("dyad", "/x"), "dyad");
  assert.equal(absolutePathLike("./dyad", "/x"), "/x/dyad");
  assert.equal(absolutePathLike("bin/dyad", "/x"), "/x/bin/dyad");
  assert.equal(absolutePathLike("/usr/bin/dyad", "/x"), "/usr/bin/dyad");
  assert.equal(absolutePathLike("..", "/x/y"), "/x");
});

// Review finding 4: a failing dyad render fails, whatever it printed.
test("fails clearly when dyad render exits non-zero, even if it printed SVG", async () => {
  const { root, env } = fakeLibrary();
  const dyad = join(root, "bin", "fake-dyad");
  await assert.rejects(
    runDyadCli(join(root, "lib"), "RenderRef.AnalysisPoints", { dyad, env: { ...env, FAKE_RENDER_EXIT: "1", FAKE_RENDER_ERR: "Error: lookup-failed: X" } }),
    (e: unknown) => e instanceof DyadCliError && /dyad render RenderRef\.AnalysisPoints .* failed \(exit 1\):\nError: lookup-failed: X/.test(e.message),
  );
  await assert.rejects(
    runDyadCli(join(root, "lib"), "RenderRef.AnalysisPoints", { dyad, env: { ...env, FAKE_SVG: "/dev/null" } }),
    /dyad render .* failed \(exit 0, but it printed no SVG\):\n\(no output on stderr\)/,
  );
  await assert.rejects(
    runDyadCli(join(root, "lib"), "RenderRef.AnalysisPoints", { dyad, env: { ...env, FAKE_EXTRACT_EXIT: "2", FAKE_EXTRACT_ERR: "boom" } }),
    /dyad layout extract .* failed \(exit 2\):\nboom/,
  );
  await assert.rejects(runDyadCli(join(root, "lib"), "X.Y", { dyad: join(root, "nope") }), /cannot run .*nope: not found/);
});

test("passes dyad's own warnings on as diagnostics", async () => {
  const { root, env } = fakeLibrary();
  const diagnostics: string[] = [];
  await diagramFromDyadCli(join(root, "lib"), "RenderRef.AnalysisPoints", {
    dyad: join(root, "bin", "fake-dyad"),
    env: { ...env, FAKE_RENDER_ERR: "Warning: something odd\n", FAKE_EXTRACT_ERR: "Warning: also odd" },
    onDiagnostic: (m) => diagnostics.push(m),
  });
  assert.deepEqual(diagnostics, ["dyad: Warning: something odd", "dyad: Warning: also odd"]);
  // The same warning from both commands is passed on once.
  diagnostics.length = 0;
  await diagramFromDyadCli(join(root, "lib"), "RenderRef.AnalysisPoints", {
    dyad: join(root, "bin", "fake-dyad"),
    env: { ...env, FAKE_RENDER_ERR: "Warning: same\n", FAKE_EXTRACT_ERR: "Warning: same\n" },
    onDiagnostic: (m) => diagnostics.push(m),
  });
  assert.deepEqual(diagnostics, ["dyad: Warning: same"]);
});

// Review finding 6, in the adapter: analysis points come from the source;
// array fan-out, which the CLI output cannot describe, is reported.
test("reads analysis points from the component's source onto their connection", () => {
  const source = fixture("RenderRef/dyad/features.dyad");
  assert.deepEqual(analysisPointsIn(source), [
    { name: "u", ends: [{ component: "g1", connector: "y" }, { component: "g2", connector: "u" }] },
  ]);
  const d = diagramFromCliOutputs("RenderRef.AnalysisPoints", {
    svg: fixture("RenderRef.AnalysisPoints.render.svg"),
    renderLog: "",
    problem: JSON.parse(fixture("RenderRef.AnalysisPoints.problem.json")),
    source: componentSourceOf(source, "AnalysisPoints"),
  }, () => assert.fail("no diagnostics expected"));
  assert.deepEqual(d.connections.map((c) => c.analysisPoint?.name), [undefined, "u"]);
  const diagnostics: string[] = [];
  diagramFromCliOutputs("X.Y", {
    svg: fixture("RenderRef.AnalysisPoints.render.svg"),
    renderLog: "",
    problem: JSON.parse(fixture("RenderRef.AnalysisPoints.problem.json")),
    source: "component Y\nrelations\n  v: analysis_point(src.y, g2.u)\nend\n",
  }, (m) => diagnostics.push(m));
  assert.deepEqual(diagnostics, ["analysis point v: no connection between its two connectors could be matched, so it is not drawn"]);
});

test("finds a component's source in the library", () => {
  const { root } = fakeLibrary();
  const src = componentSource(join(root, "lib"), "RenderRef.AnalysisPoints")!;
  assert.match(src, /^component AnalysisPoints\n/);
  assert.match(src, /u: analysis_point\(g1\.y, g2\.u\)/);
  assert.doesNotMatch(src, /component Markers/);
  assert.equal(componentSource(join(root, "lib"), "RenderRef.Nothing"), undefined);
});

test("reports wires that end at a fanned-out array connector the CLI draws once", () => {
  const diagnostics: string[] = [];
  diagramFromCliOutputs("RenderRef.ArrayShow", {
    svg: fixture("RenderRef.ArrayShow.render.svg"),
    renderLog: "",
    problem: JSON.parse(fixture("RenderRef.ArrayShow.problem.json")),
  }, (m) => diagnostics.push(m));
  assert.equal(diagnostics.length, 2);
  assert.match(diagnostics[0], /^ab\.u: a wire ends at \(390, 460\), not at the connector/);
});

function componentSourceOf(text: string, name: string): string {
  const i = text.indexOf(`component ${name}\n`);
  return text.slice(i, text.indexOf("\nend\n", i) + 5);
}
