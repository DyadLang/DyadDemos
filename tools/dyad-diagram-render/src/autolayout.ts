/**
 * A fallback layout for diagrams with no placements at all.
 *
 * Studio lays such a diagram out automatically (with the Dyad autolayout
 * package, which uses ELK); a diagram with any placement is drawn as placed,
 * unplaced parts at the default spot. This module follows the same rule
 * ({@link needsAutoLayout} is the kernel's `hasNoPositionalInformation`) but
 * lays out with a small layered algorithm of its own: components flow left
 * to right along their connections, and a component hanging off a top or
 * bottom connector (a fixed support, a ground) goes on the row below.
 *
 * Inside the Dyad CLI this module is replaced by `@juliacomputing/dyad-autolayout`
 * (see ARCHITECTURE.md), which gives Studio's own result.
 */

import type { ComponentShape, ConnectorShape, Connection, DiagramData, Placement, Point } from "./model.ts";
import { apply, multiply, placementMatrix } from "./geometry.ts";

type Edge = "left" | "right" | "top" | "bottom";

/** Whether nothing in the diagram has a placement (and there is something to place). */
export function needsAutoLayout(d: DiagramData): boolean {
  if (d.components.length === 0) return false;
  return d.components.every((c) => !c.explicitPlacement) && d.ports.every((p) => p.explicitPlacement === false);
}

export interface AutoLayoutOptions {
  /** Component size, in diagram units (Dyad's default placement is 100 x 100). */
  size?: number;
  /** Gap between columns, as a fraction of the size. */
  columnGap?: number;
  /** Gap between rows, as a fraction of the size. */
  rowGap?: number;
}

/** Lay the diagram out; returns a copy with new placements and routes. */
export function autoLayout(d: DiagramData, options: AutoLayoutOptions = {}): DiagramData {
  const size = options.size ?? 100;
  const columnGap = options.columnGap ?? 0.3;
  const rowGap = options.rowGap ?? 0.6;
  // A negative gap would let the row search below move a component back
  // onto the one it is moving past, for ever.
  if (!(Number.isFinite(size) && size > 0) || !(Number.isFinite(columnGap) && columnGap >= 0) || !(Number.isFinite(rowGap) && rowGap >= 0)) {
    throw new RangeError(`autoLayout: size must be > 0 and gaps >= 0, got size ${size}, columnGap ${columnGap}, rowGap ${rowGap}`);
  }
  const colStep = size * (1 + columnGap);
  const rowStep = size * (1 + rowGap);
  const byName = new Map(d.components.map((c) => [c.name, c]));

  // Directed links between components, from the connector sides.
  interface Link {
    from: string;
    to: string;
    /** How far below `from` the `to` component hangs, in sizes (0: same row). */
    drop: number;
  }
  const links: Link[] = [];
  for (const conn of d.connections) {
    const ends = (conn.ends ?? []).filter((e) => e.component !== undefined && byName.has(e.component));
    for (let i = 0; i + 1 < ends.length; i++) {
      const a = ends[i];
      const b = ends[i + 1];
      const ea = connectorEdge(byName.get(a.component!)!, a.connector);
      const eb = connectorEdge(byName.get(b.component!)!, b.connector);
      const forward = (e: Edge | undefined) => e === "right" || e === "bottom";
      const backward = (e: Edge | undefined) => e === "left" || e === "top";
      let from = a.component!;
      let to = b.component!;
      let toEdge = eb;
      let fromEdge = ea;
      if (backward(ea) && forward(eb)) {
        [from, to, toEdge, fromEdge] = [to, from, ea, eb];
      }
      // Hanging off a bottom connector goes further down than hanging off a
      // side connector, as ELK's layered layout places them.
      const drop = toEdge === "top" || (fromEdge === "bottom" && toEdge !== "left") ? (fromEdge === "bottom" ? 1.8 : 1.05) : 0;
      links.push({ from, to, drop });
    }
  }

  // Layers: longest path from the sources, ignoring links that close a cycle.
  const layer = new Map<string, number>();
  const names = d.components.map((c) => c.name);
  const incoming = new Map(names.map((n) => [n, links.filter((l) => l.to === n && l.from !== n)]));
  const visiting = new Set<string>();
  const layerOf = (n: string): number => {
    const known = layer.get(n);
    if (known !== undefined) return known;
    if (visiting.has(n)) return 0;
    visiting.add(n);
    let l = 0;
    for (const link of incoming.get(n) ?? []) l = Math.max(l, layerOf(link.from) + 1);
    visiting.delete(n);
    layer.set(n, l);
    return l;
  };
  for (const n of names) layerOf(n);

  // Rows: follow the predecessor, lower when hanging below it; move down
  // past anything already in the same column.
  const top = new Map<string, number>();
  const columns = new Map<number, Array<[number, number]>>();
  const order = [...names].sort((a, b) => layer.get(a)! - layer.get(b)! || names.indexOf(a) - names.indexOf(b));
  for (const n of order) {
    const pred = (incoming.get(n) ?? []).find((l) => top.has(l.from));
    let y = pred ? top.get(pred.from)! + pred.drop * size : 0;
    const used = columns.get(layer.get(n)!) ?? [];
    for (let moved = true; moved; ) {
      moved = false;
      for (const [y0, y1] of used) {
        if (y < y1 && y + size > y0) {
          y = y1 + (rowStep - size);
          moved = true;
        }
      }
    }
    used.push([y, y + size]);
    columns.set(layer.get(n)!, used);
    top.set(n, y);
  }

  const components: ComponentShape[] = d.components.map((c) => {
    const x = layer.get(c.name)! * colStep;
    const y = top.get(c.name)!;
    const placement: Placement = { x1: x, y1: y, x2: x + size, y2: y + size, rot: 0 };
    return { ...c, placement };
  });
  const placed = new Map(components.map((c) => [c.name, c]));

  // Ports: inputs in a column on the left, the rest on the right.
  const maxLayer = Math.max(0, ...layer.values());
  let left = 0;
  let right = 0;
  const ports: ConnectorShape[] = d.ports.map((p) => {
    const onLeft = p.edge === "left";
    const x = onLeft ? -colStep : (maxLayer + 1) * colStep;
    const y = (onLeft ? left++ : right++) * size;
    return { ...p, placement: { x1: x + size * 0.3, y1: y + size * 0.3, x2: x + size * 0.7, y2: y + size * 0.7, rot: 0 } };
  });
  const placedPorts = new Map(ports.map((p) => [p.name, p]));

  const connections: Connection[] = d.connections.map((conn) => {
    const ends = conn.ends ?? [];
    const routes: Point[][] = [];
    for (let i = 0; i + 1 < ends.length; i++) {
      const a = endPoint(ends[i], placed, placedPorts);
      const b = endPoint(ends[i + 1], placed, placedPorts);
      if (a && b) routes.push(orthogonalRoute(a.point, a.edge, b.point, b.edge));
    }
    return { ...conn, routes: routes.length > 0 ? routes : conn.routes, junctions: [] };
  });

  return { ...d, components, ports, connections };
}

/** The side of its component a connector is on, from its placement. */
export function connectorEdge(c: ComponentShape, connector: string): Edge | undefined {
  const k = c.connectors.find((x) => x.name === connector);
  if (!k) return undefined;
  if (k.edge) return k.edge;
  const cx = (k.placement.x1 + k.placement.x2) / 2 - 500;
  const cy = (k.placement.y1 + k.placement.y2) / 2 - 500;
  if (Math.abs(cx) >= Math.abs(cy)) return cx < 0 ? "left" : "right";
  return cy < 0 ? "top" : "bottom";
}

function endPoint(
  end: { component?: string; connector: string },
  components: Map<string, ComponentShape>,
  ports: Map<string, ConnectorShape>,
): { point: Point; edge: Edge | undefined } | undefined {
  if (end.component === undefined) {
    const p = ports.get(end.connector);
    if (!p) return undefined;
    return { point: apply(placementMatrix(p.placement), { x: 500, y: 500 }), edge: p.edge === "left" ? "right" : "left" };
  }
  const c = components.get(end.component);
  const k = c?.connectors.find((x) => x.name === end.connector);
  if (!c || !k) return undefined;
  const m = multiply(placementMatrix(c.placement), placementMatrix(k.placement));
  return { point: apply(m, { x: 500, y: 500 }), edge: connectorEdge(c, end.connector) };
}

const vertical = (e: Edge | undefined) => e === "top" || e === "bottom";

/** An orthogonal route between two connector points, leaving each along its side's normal. */
export function orthogonalRoute(a: Point, ea: Edge | undefined, b: Point, eb: Edge | undefined): Point[] {
  if (Math.abs(a.x - b.x) < 1e-6 || Math.abs(a.y - b.y) < 1e-6) return [a, b];
  const va = vertical(ea);
  const vb = vertical(eb);
  if (!va && !vb) {
    const mx = (a.x + b.x) / 2;
    return [a, { x: mx, y: a.y }, { x: mx, y: b.y }, b];
  }
  if (va && vb) {
    const my = (a.y + b.y) / 2;
    return [a, { x: a.x, y: my }, { x: b.x, y: my }, b];
  }
  if (!va && vb) return [a, { x: b.x, y: a.y }, b];
  return [a, { x: a.x, y: b.y }, b];
}
