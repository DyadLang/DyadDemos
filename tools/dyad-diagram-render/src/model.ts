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
