/**
 * The input to the renderer: one component definition's diagram, with every
 * icon already resolved to SVG markup.
 *
 * This mirrors the Dyad kernel's `GraphicalLayout`
 * (`pkgs/kernel/src/codegen/icons/layout.ts`), cut down to what drawing
 * needs and made plain JSON, so the renderer never has to ask the compiler
 * for anything. Coordinates follow the kernel's conventions:
 *
 * - A diagram is drawn in diagram units, nominally a 1000 x 1000 box, though
 *   anything may lie outside it.
 * - An icon is drawn in its own 1000 x 1000 box.
 * - A {@link Placement} is a signed extent and a rotation in degrees. A
 *   reversed extent (`x1 > x2` or `y1 > y2`) is a flip. The icon is scaled to
 *   the extent, flipped, then rotated about the extent's centre, exactly as
 *   the kernel's `iconPointOnDiagram` defines.
 */

export const DIAGRAM_SCHEMA = "dyad-diagram-render/diagram@1";

export interface Point {
  x: number;
  y: number;
}

export interface Placement {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  /** Degrees, clockwise (SVG's sense). */
  rot: number;
}

/** A text label (the kernel's `LabelGraphic`). */
export interface Label {
  /** The text, with `$(...)` substitutions already made. */
  text: string;
  /**
   * Where the label is anchored: in the owner's icon coordinates (0..1000)
   * for a component's or connector's label, in diagram coordinates for a
   * diagram label.
   */
  x: number;
  y: number;
  /** Rotation in degrees. */
  rot: number;
  /** Presentation attributes from the label's metadata (`fill`, ...). */
  attrs?: Record<string, string>;
}

/** A connector, either on a component's icon or on the diagram boundary. */
export interface ConnectorShape {
  name: string;
  /**
   * For a connector of a component: its placement in the component's icon
   * coordinates. For a boundary port: its placement on the diagram.
   */
  placement: Placement;
  /** The connector's icon, SVG markup. */
  icon: string;
  /** Labels; drawn for boundary ports only, as Studio does. */
  labels?: Label[];
  /** Which side of its component the connector sits on, if known. */
  edge?: "left" | "right" | "top" | "bottom";
  /**
   * For a boundary port: whether the source places it. Unknown counts as
   * placed, so a diagram is only laid out when it is known to need it.
   */
  explicitPlacement?: boolean;
  /**
   * For an array connector (`u = [RealInput() for i in 1:n]`): its length,
   * the kernel's `ConnectorGraphic.count`. With {@link show}, the renderer
   * fans the connector out into `count` copies, as Studio does; the
   * placement is the whole connector's, not yet fanned out.
   */
  count?: number;
  /**
   * The placement's `show`: fan out only arrays of at most this many
   * elements. Without it an array connector is drawn once (as Studio does).
   */
  show?: number;
  /**
   * The connector's clock (the kernel's `ConnectorGraphic.clockInfo`), when
   * it is clocked. Not drawn; the renderer reports it.
   */
  clockInfo?: unknown;
}

/** A subcomponent (the kernel's `ComponentGraphic`). */
export interface ComponentShape {
  name: string;
  /** The component's type, for information only. */
  type?: string;
  placement: Placement;
  /**
   * Whether the source gives this component a diagram placement. When no
   * component and no port does, the diagram is laid out automatically.
   */
  explicitPlacement: boolean;
  /** The component's icon, SVG markup (the base layer, without connectors). */
  icon: string;
  connectors: ConnectorShape[];
  /** Labels in icon coordinates: by default the instance name. */
  labels: Label[];
}

/** One end of a connection: `component.connector`, or a boundary port. */
export interface ConnectionEnd {
  /** The component, or undefined for a boundary port. */
  component?: string;
  connector: string;
}

/** A connection (the kernel's `ConnectionGraphics`). */
export interface Connection {
  /** The wires, each a polyline in diagram coordinates. */
  routes: Point[][];
  /** Junction dots, in diagram coordinates. */
  junctions: Point[];
  /** Path attributes from the connector type's `path` metadata (`stroke`, ...). */
  pathAttrs: Record<string, string>;
  /** The connectors this connection joins, if known (needed for auto layout). */
  ends?: ConnectionEnd[];
  /**
   * The analysis point on this connection, if any (the kernel's
   * `ConnectionGraphics.analysisPoint`). Drawn as Studio draws it: a
   * crosshair badge at the middle of the wire, with the name above it.
   */
  analysisPoint?: { name: string } | null;
  /**
   * Whether the connection is in a clock partition (the kernel's
   * `isClocked`). Not drawn; the renderer reports it.
   */
  isClocked?: boolean;
  /**
   * The connection's `renderStyle` metadata. Studio 3.5.1 draws `markers`
   * exactly like `standard`, and so does the renderer.
   */
  renderStyle?: "standard" | "markers";
}

export interface DiagramData {
  schema: typeof DIAGRAM_SCHEMA;
  /** The component definition, `Library.Component`. */
  name: string;
  components: ComponentShape[];
  /** Boundary connectors of the definition itself. */
  ports: ConnectorShape[];
  connections: Connection[];
  /** Free labels on the diagram, in diagram coordinates. */
  labels: Label[];
}

/** Thrown by {@link validateDiagramData} for data that is not a diagram. */
export class DiagramDataError extends Error {}

/**
 * Check that a value read from JSON has the shape of {@link DiagramData}
 * (types only), so that malformed input fails with a clear message rather
 * than half-way through drawing.
 *
 * @returns The same value, typed
 */
export function validateDiagramData(value: unknown): DiagramData {
  const fail = (path: string, want: string): never => {
    throw new DiagramDataError(`diagram data: ${path} should be ${want}`);
  };
  const obj = (v: unknown, path: string): Record<string, unknown> =>
    typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : fail(path, "an object");
  const arr = (v: unknown, path: string): unknown[] => (Array.isArray(v) ? v : fail(path, "an array"));
  const num = (v: unknown, path: string) => (typeof v === "number" && Number.isFinite(v) ? v : fail(path, "a finite number"));
  const str = (v: unknown, path: string) => (typeof v === "string" ? v : fail(path, "a string"));
  const optStr = (v: unknown, path: string) => v === undefined || str(v, path);
  const strings = (v: unknown, path: string) => {
    if (v === undefined) return;
    for (const [k, x] of Object.entries(obj(v, path))) str(x, `${path}.${k}`);
  };
  const point = (v: unknown, path: string) => {
    const p = obj(v, path);
    num(p.x, `${path}.x`);
    num(p.y, `${path}.y`);
  };
  const placement = (v: unknown, path: string) => {
    const p = obj(v, path);
    for (const k of ["x1", "y1", "x2", "y2", "rot"]) num(p[k], `${path}.${k}`);
  };
  const label = (v: unknown, path: string) => {
    const l = obj(v, path);
    str(l.text, `${path}.text`);
    for (const k of ["x", "y", "rot"]) num(l[k], `${path}.${k}`);
    strings(l.attrs, `${path}.attrs`);
  };
  const connector = (v: unknown, path: string) => {
    const c = obj(v, path);
    str(c.name, `${path}.name`);
    placement(c.placement, `${path}.placement`);
    str(c.icon, `${path}.icon`);
    if (c.labels !== undefined) arr(c.labels, `${path}.labels`).forEach((l, i) => label(l, `${path}.labels[${i}]`));
    if (c.count !== undefined) num(c.count, `${path}.count`);
    if (c.show !== undefined) num(c.show, `${path}.show`);
  };

  const d = obj(value, "the data");
  if (d.schema !== DIAGRAM_SCHEMA) fail("schema", JSON.stringify(DIAGRAM_SCHEMA));
  str(d.name, "name");
  arr(d.components, "components").forEach((v, i) => {
    const path = `components[${i}]`;
    const c = obj(v, path);
    str(c.name, `${path}.name`);
    optStr(c.type, `${path}.type`);
    placement(c.placement, `${path}.placement`);
    if (typeof c.explicitPlacement !== "boolean") fail(`${path}.explicitPlacement`, "a boolean");
    str(c.icon, `${path}.icon`);
    arr(c.connectors, `${path}.connectors`).forEach((k, j) => connector(k, `${path}.connectors[${j}]`));
    arr(c.labels, `${path}.labels`).forEach((l, j) => label(l, `${path}.labels[${j}]`));
  });
  arr(d.ports, "ports").forEach((p, i) => connector(p, `ports[${i}]`));
  arr(d.connections, "connections").forEach((v, i) => {
    const path = `connections[${i}]`;
    const c = obj(v, path);
    arr(c.routes, `${path}.routes`).forEach((r, j) => arr(r, `${path}.routes[${j}]`).forEach((p, k) => point(p, `${path}.routes[${j}][${k}]`)));
    arr(c.junctions, `${path}.junctions`).forEach((p, j) => point(p, `${path}.junctions[${j}]`));
    strings(obj(c.pathAttrs, `${path}.pathAttrs`), `${path}.pathAttrs`);
    if (c.analysisPoint !== undefined && c.analysisPoint !== null) str(obj(c.analysisPoint, `${path}.analysisPoint`).name, `${path}.analysisPoint.name`);
    if (c.renderStyle !== undefined && c.renderStyle !== "standard" && c.renderStyle !== "markers") fail(`${path}.renderStyle`, '"standard" or "markers"');
  });
  arr(d.labels, "labels").forEach((l, i) => label(l, `labels[${i}]`));
  return value as DiagramData;
}
