// Score a drawn diagram with dyad-layout's own objective (WASM build).
//
// stdin: {"wasmDir", "problem": LayoutProblem, "solution": LayoutSolution, "options"}
// stdout: {"version", "existing": LayoutSolution, "rerouted": LayoutSolution}
//
//   existing - score_existing_solution_json: the drawn routes, scored as they are
//   rerouted - score_layout_json: the same placements, re-routed by dyad-layout's router
//
// wasmDir is dyad-layout's wasm/pkg directory (committed in the
// JuliaComputing/dyad-layout repository, tag v0.1.1 for the Dyad 3.5.0 CLI).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const input = JSON.parse(readFileSync(0, "utf8"));
const glue = await import(pathToFileURL(join(input.wasmDir, "dyad_layout_wasm.js")).href);
glue.initSync({ module: readFileSync(join(input.wasmDir, "dyad_layout_wasm_bg.wasm")) });

const problem = JSON.stringify(input.problem);
const options = JSON.stringify(input.options ?? {});
const out = { version: glue.version() };
out.existing = JSON.parse(glue.score_existing_solution_json(problem, JSON.stringify(input.solution), options));
try {
  out.rerouted = JSON.parse(
    glue.score_layout_json(
      problem,
      JSON.stringify(input.solution.componentPlacements),
      JSON.stringify(input.solution.canvasConnectorPlacements),
      options,
    ),
  );
} catch (e) {
  out.reroutedError = String(e);
}
// The routes are echoed back by the scorer; drop them to keep reports small.
for (const k of ["existing", "rerouted"]) {
  if (out[k]) {
    out[k].routedConnections = out[k].routedConnections.length;
    delete out[k].componentPlacements;
    delete out[k].canvasConnectorPlacements;
  }
}
process.stdout.write(JSON.stringify(out));
