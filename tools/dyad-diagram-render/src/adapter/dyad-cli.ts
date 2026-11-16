/**
 * The stop-gap adapter: get a component's {@link DiagramData} from the Dyad
 * CLI binary, without a language server.
 *
 * It runs two commands the 3.5 CLI already has:
 *
 * - `dyad render`, whose SVG holds the kernel's layout with every icon
 *   resolved (read by `render-svg.ts`), and
 * - `dyad layout extract`, which names the components, connectors and
 *   boundary ports in the same order and says which ports are pinned and
 *   which connectors each connection joins.
 *
 * `dyad render`'s warnings say which components have no diagram placement.
 *
 * Inside the CLI none of this is needed: the same data comes straight from
 * the kernel's `diagramLayoutSelector` (see ARCHITECTURE.md). Delete this
 * directory when the renderer moves in-tree.
 */

import { execFile } from "node:child_process";
import type { ComponentShape, Connection, ConnectionEnd, ConnectorShape, DiagramData, Label, Placement, Point } from "../model.ts";
import { DIAGRAM_SCHEMA } from "../model.ts";
import { type RenderedDiagram, parseRenderSvg } from "./render-svg.ts";
import { apply, multiply, placementMatrix } from "../geometry.ts";

/** The kernel's placement for a component with none (`defaultTransform`). */
export const DEFAULT_PLACEMENT: Placement = { x1: 450, y1: 450, x2: 550, y2: 550, rot: 0 };

export interface DyadCliOptions {
  /** The `dyad` executable (default `$DYAD`, else `dyad`). */
  dyad?: string;
  /** Extra environment, e.g. `JULIA_EXECUTABLE`. */
  env?: Record<string, string>;
  /** Timeout per command, in milliseconds (default 300000). */
  timeoutMs?: number;
}

/** The parts of a `dyad-layout/problem@1` file this adapter reads. */
export interface LayoutProblem {
  structure: {
    components: Array<{
      id: string;
      connectors: Array<{ id: string; edge?: string; direction?: string }>;
    }>;
    canvasConnectors: Array<{ id: string; direction?: string }>;
    connections: Array<{
      id: string;
      from: { type: "canvas" | "component"; componentId?: string; connectorId: string };
      to: { type: "canvas" | "component"; componentId?: string; connectorId: string };
    }>;
  };
  constraints?: Array<{ kind?: { kind?: string; componentId?: string } }>;
}

export interface CliOutputs {
  /** `dyad render`'s standard output. */
  svg: string;
  /** `dyad render`'s standard error (its warnings). */
  renderLog: string;
  /** `dyad layout extract`'s JSON. */
  problem: LayoutProblem;
}

/**
 * Run the CLI for one component.
 *
 * @param dir The library directory
 * @param component `Library.Component` or `Library.module.Component`
 */
export async function runDyadCli(dir: string, component: string, options: DyadCliOptions = {}): Promise<CliOutputs> {
  const dyad = options.dyad ?? process.env.DYAD ?? "dyad";
  const env = { ...process.env, ...options.env };
  const timeout = options.timeoutMs ?? 300_000;
  const run = (args: string[]) =>
    new Promise<{ stdout: string; stderr: string; code: number }>((resolve, reject) => {
      execFile(dyad, args, { cwd: dir, env, timeout, maxBuffer: 256 * 1024 * 1024 }, (err, stdout, stderr) => {
        if (err && (err as NodeJS.ErrnoException).code === "ENOENT") {
          reject(new Error(`cannot run ${dyad}: not found (set --dyad or $DYAD)`));
          return;
        }
        const code = err ? (typeof err.code === "number" ? err.code : 1) : 0;
        resolve({ stdout, stderr, code });
      });
    });
  const [r, x] = await Promise.all([
    run(["render", component, "--dir", dir]),
    run(["layout", "extract", component, "--dir", dir]),
  ]);
  if (!r.stdout.includes("<svg")) {
    throw new Error(`dyad render ${component} failed (exit ${r.code}):\n${r.stderr.trim()}`);
  }
  if (x.code !== 0) {
    throw new Error(`dyad layout extract ${component} failed (exit ${x.code}):\n${x.stderr.trim()}`);
  }
  let problem: LayoutProblem;
  try {
    problem = JSON.parse(x.stdout);
  } catch {
    throw new Error(`dyad layout extract ${component} did not print JSON`);
  }
  return { svg: r.stdout, renderLog: r.stderr, problem };
}

/** Get a component's diagram from the CLI. */
export async function diagramFromDyadCli(dir: string, component: string, options: DyadCliOptions = {}): Promise<DiagramData> {
  const outputs = await runDyadCli(dir, component, options);
  return diagramFromCliOutputs(component, outputs);
}

/** Components that `dyad render` warned have no diagram placement. */
export function unplacedComponents(renderLog: string): Set<string> {
  const names = new Set<string>();
  for (const m of renderLog.matchAll(/missing-placement: Component (\S+) in \S+ doesn't include placement metadata for diagrams/g)) {
    names.add(m[1]);
  }
  return names;
}

/** Combine the two commands' outputs into a {@link DiagramData}. */
export function diagramFromCliOutputs(component: string, outputs: CliOutputs): DiagramData {
  const drawn: RenderedDiagram = parseRenderSvg(outputs.svg);
  const { structure: raw } = outputs.problem;
  // `extract` lists each junction of a routed connection as a pseudo
  // component, `__junction_<n>`; the kernel draws them as dots.
  const structure = { ...raw, components: raw.components.filter((c) => !c.id.startsWith("__junction_")) };
  const warnings: string[] = [];

  const unplaced = unplacedComponents(outputs.renderLog);
  if (structure.components.length !== drawn.components.length) {
    warnings.push(`dyad render drew ${drawn.components.length} components, extract lists ${structure.components.length}`);
  }
  const components: ComponentShape[] = drawn.components.map((c, i) => {
    const info = structure.components[i];
    const name = info?.id ?? `component${i + 1}`;
    const connectorInfo = info?.connectors ?? [];
    if (info && connectorInfo.length !== c.connectors.length) {
      warnings.push(`${name}: drew ${c.connectors.length} connectors, extract lists ${connectorInfo.length}`);
    }
    return {
      name,
      placement: c.placement,
      explicitPlacement: !unplaced.has(name),
      icon: c.icon,
      connectors: c.connectors.map((k, j) => ({
        name: connectorInfo[j]?.id ?? `connector${j + 1}`,
        placement: k.placement,
        icon: k.icon,
      })),
      labels: c.labels,
    };
  });

  const pinned = new Set(
    (outputs.problem.constraints ?? []).filter((c) => c.kind?.kind === "pin").map((c) => c.kind?.componentId),
  );
  if (structure.canvasConnectors.length !== drawn.ports.length) {
    warnings.push(`dyad render drew ${drawn.ports.length} boundary connectors, extract lists ${structure.canvasConnectors.length}`);
  }
  const ports: ConnectorShape[] = drawn.ports.map((p, i) => {
    const info = structure.canvasConnectors[i];
    const name = info?.id ?? `port${i + 1}`;
    // Studio labels a boundary connector with its name, below it (the
    // `$(instance)` label Dyad's connector types carry at (500, 1100)).
    const labels: Label[] = [{ text: name, x: 500, y: 1100, rot: 0 }];
    return {
      name,
      placement: p.placement,
      icon: p.icon,
      labels,
      explicitPlacement: info ? pinned.has(info.id) : true,
      edge: info?.direction === "input" ? "left" : info?.direction === "output" ? "right" : undefined,
    };
  });

  // Dyad CLI 3.5.0 draws a component without a diagram placement over the
  // whole 0..1000 box; the kernel's default (and what Studio draws) is a
  // 100 x 100 box at the centre. Such components are moved there, and the
  // wire ends at their connectors with them (below, once the wires are
  // matched to connections).
  const moved = new Set<string>();
  for (const c of components) {
    if (c.explicitPlacement) continue;
    c.placement = { ...DEFAULT_PLACEMENT };
    moved.add(c.name);
  }
  const byName = new Map(components.map((c) => [c.name, c]));
  const connectorCenter = (end: ConnectionEnd): Point | undefined => {
    if (end.component === undefined || !moved.has(end.component)) return undefined;
    const c = byName.get(end.component);
    const k = c?.connectors.find((x) => x.name === end.connector);
    if (!c || !k) return undefined;
    return apply(multiply(placementMatrix(c.placement), placementMatrix(k.placement)), { x: 500, y: 500 });
  };
  // Wires: `dyad render` draws each connection's routes in order, one path
  // per route. Without route metadata (and so without junctions) a
  // connection of n connectors is drawn as n-1 routes, which is how the
  // paths are given back to connections.
  const wires = drawn.wires;
  const connections: Connection[] = [];
  let w = 0;
  const conns = groupConnections(structure.connections);
  const plainRoutes = conns.reduce((n, ends) => n + ends.length - 1, 0);
  if (plainRoutes === wires.length && drawn.junctions.length === 0) {
    for (const ends of conns) {
      const mine = wires.slice(w, w + ends.length - 1);
      w += ends.length - 1;
      connections.push({
        routes: mine.map((x, j) => {
          const pts = [...x.points];
          pts[0] = connectorCenter(ends[j]) ?? pts[0];
          pts[pts.length - 1] = connectorCenter(ends[j + 1]) ?? pts[pts.length - 1];
          return pts;
        }),
        junctions: [],
        pathAttrs: { ...(mine[0]?.attrs ?? {}) },
        ends,
      });
    }
  } else {
    // Routed connections (with junctions) are not labelled in the SVG. Their
    // wires are put back together into nets: wires meeting at an end or at a
    // junction dot are one connection. They are drawn right, but without
    // their ends (which only auto layout needs).
    connections.push(...netsOf(wires, drawn.junctions));
  }
  for (const m of warnings) process.emitWarning(m, { code: "DYAD_DIAGRAM_ADAPTER" });

  return {
    schema: DIAGRAM_SCHEMA,
    name: component,
    components,
    ports,
    connections,
    labels: drawn.labels,
  };
}

/**
 * The connections of a definition. `extract` lists each `connect(a, b, c)`
 * as the pairs it joins (a-b, a-c, ...); consecutive pairs sharing their
 * first end and with ids `__conn_k` are the same statement only if dyad
 * numbered them so, so every pair is kept as its own two-ended connection.
 */
function groupConnections(list: LayoutProblem["structure"]["connections"]): ConnectionEnd[][] {
  const end = (e: { type: string; componentId?: string; connectorId: string }): ConnectionEnd =>
    e.type === "canvas" ? { connector: e.connectorId } : { component: e.componentId, connector: e.connectorId };
  return list.map((c) => [end(c.from), end(c.to)]);
}

/** Group wires into nets: wires sharing an end point, or ending at the same junction dot. */
export function netsOf(
  wires: Array<{ points: Point[]; attrs: Record<string, string> }>,
  junctions: Array<{ point: Point; fill: string }>,
): Connection[] {
  const parent = wires.map((_, i) => i);
  const find = (i: number): number => (parent[i] === i ? i : (parent[i] = find(parent[i])));
  const key = (p: Point) => `${p.x.toFixed(3)},${p.y.toFixed(3)}`;
  const firstAt = new Map<string, number>();
  wires.forEach((w, i) => {
    if (w.points.length === 0) return;
    for (const p of [w.points[0], w.points[w.points.length - 1]]) {
      const k = key(p);
      const other = firstAt.get(k);
      if (other === undefined) firstAt.set(k, i);
      else parent[find(i)] = find(other);
    }
  });
  const nets = new Map<number, Connection>();
  wires.forEach((w, i) => {
    const r = find(i);
    let c = nets.get(r);
    if (!c) {
      c = { routes: [], junctions: [], pathAttrs: { ...w.attrs } };
      nets.set(r, c);
    }
    c.routes.push(w.points);
  });
  const loose: Connection[] = [];
  for (const j of junctions) {
    const owner = firstAt.get(key(j.point));
    if (owner !== undefined) nets.get(find(owner))!.junctions.push(j.point);
    else loose.push({ routes: [], junctions: [j.point], pathAttrs: { stroke: j.fill } });
  }
  return [...nets.values(), ...loose];
}
