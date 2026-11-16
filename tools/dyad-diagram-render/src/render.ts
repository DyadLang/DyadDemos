/**
 * Draw a component's diagram as SVG, the way Dyad Studio's diagram view draws
 * it.
 *
 * `render` is pure: it reads only its arguments (the diagram, already
 * resolved to geometry and icon markup, and the font metrics to measure
 * labels with) and returns a self-contained SVG document. It does no I/O.
 *
 * Everything that comes from the data (names, label text, colours, icon
 * markup) reaches the SVG escaped: text and attribute values through
 * `escapeText`/`escapeAttr`, numbers through `fmt`, icons through
 * `prepareIcon`'s sanitiser. Nothing from the data is written into a comment.
 */

import type { ComponentShape, Connection, ConnectorShape, DiagramData, Label, Placement, Point } from "./model.ts";
import {
  type Box,
  type Matrix,
  addPoint,
  apply,
  boxFrame,
  emptyBox,
  fanOut,
  fmt,
  isEmpty,
  matrixAttr,
  multiply,
  placementMatrix,
  rotate,
  scale,
  translate,
} from "./geometry.ts";
import { fitViewBox, prepareIcon } from "./icon.ts";
import { type DiagramStyle, STUDIO_STYLE } from "./style.ts";
import { type FontMetrics, measureText } from "./text.ts";
import { autoLayout, needsAutoLayout } from "./autolayout.ts";
import { escapeAttr, escapeText } from "./xml.ts";

export interface RenderOptions {
  /** Overrides for Studio's look. */
  style?: Partial<DiagramStyle>;
  /**
   * Metrics of the label font, to size the drawing. Without them labels are
   * measured as 0.55 em per character.
   */
  font?: FontMetrics;
  /** Output pixels per diagram unit (default 1). Ignored when `fit` is given. */
  scale?: number;
  /**
   * Fit the drawing, margin included, into this many pixels, keeping its
   * aspect ratio; the output takes the size the drawing needs. This is
   * dyad-ui-shot's `--fit content`.
   */
  fit?: { width: number; height: number };
  /** Margin around the drawing, in output pixels (default 48). */
  margin?: number;
  /**
   * `"auto"` (the default) lays out a diagram in which nothing has a
   * placement, as Studio does; `"never"` draws it where the placements put it.
   */
  layout?: "auto" | "never";
}

export interface RenderResult {
  svg: string;
  /** Output size in pixels. */
  width: number;
  height: number;
  /** Output pixels per diagram unit. */
  scale: number;
  /** What was drawn, in diagram units, before the margin. */
  bounds: Box;
  /**
   * Warnings: what was in the data but is not drawn (icon content removed
   * by the sanitiser, clock partitions), one message each.
   */
  diagnostics: string[];
}

/** Thrown for render options that cannot give a drawing. */
export class RenderOptionError extends RangeError {}

/**
 * Render a diagram to an SVG document.
 *
 * @param data The diagram
 * @param options How to draw it
 * @returns The SVG markup
 */
export function render(data: DiagramData, options: RenderOptions = {}): string {
  return renderDiagram(data, options).svg;
}

/** The largest output side, in pixels, that is accepted. */
const MAX_PIXELS = 32768;

/**
 * Check the numeric options before drawing anything.
 *
 * @throws RenderOptionError
 */
export function checkRenderOptions(options: RenderOptions): void {
  const { scale: s, fit, margin } = options;
  if (margin !== undefined && !(Number.isFinite(margin) && margin >= 0)) {
    throw new RenderOptionError(`margin must be a number of pixels >= 0, got ${margin}`);
  }
  if (s !== undefined && !(Number.isFinite(s) && s > 0)) {
    throw new RenderOptionError(`scale must be a number > 0, got ${s}`);
  }
  if (fit !== undefined) {
    const { width, height } = fit;
    if (!(Number.isFinite(width) && width > 0 && Number.isFinite(height) && height > 0)) {
      throw new RenderOptionError(`fit must be a positive width and height, got ${width}x${height}`);
    }
    const m = margin ?? 48;
    if (width - 2 * m <= 0 || height - 2 * m <= 0) {
      throw new RenderOptionError(
        `fit ${width}x${height} leaves no room for the drawing inside a ${m} px margin (needs more than ${2 * m} px each way; lower the margin or enlarge the fit)`,
      );
    }
  }
}

/** {@link render}, returning the output size and scale as well. */
export function renderDiagram(input: DiagramData, options: RenderOptions = {}): RenderResult {
  checkRenderOptions(options);
  const style: DiagramStyle = { ...STUDIO_STYLE, ...options.style };
  const data = options.layout !== "never" && needsAutoLayout(input) ? autoLayout(input) : input;
  const ctx = new Context(style, options.font);

  for (const c of data.components) drawComponentBody(ctx, c);
  for (const c of data.components) drawComponentConnectors(ctx, c);
  for (const conn of data.connections) drawWires(ctx, conn.routes, wireColor(ctx, conn));
  for (const p of data.ports) {
    drawIcon(ctx, ctx.ports, p.icon, placementMatrix(p.placement), `port ${p.name}`);
    noteClock(ctx, p, `port ${p.name}`);
  }
  for (const conn of data.connections) {
    const fill = wireColor(ctx, conn);
    for (const j of conn.junctions) {
      ctx.junctions.push(`<circle cx="${fmt(j.x)}" cy="${fmt(j.y)}" r="${fmt(style.junctionRadius)}" fill="${escapeAttr(fill)}"/>`);
      addPoint(ctx.bounds, j, style.junctionRadius);
    }
  }
  for (const conn of data.connections) {
    if (conn.analysisPoint) drawAnalysisPoint(ctx, conn, conn.analysisPoint.name);
  }
  const clocked = data.connections.filter((c) => c.isClocked).length;
  if (clocked > 0) {
    ctx.diagnostics.push(`${clocked} clocked connection(s): clock partitions are not drawn differently from other wires`);
  }
  for (const c of data.components) {
    const m = placementMatrix(c.placement);
    for (const l of c.labels) drawLabel(ctx, l, apply(m, l), c.placement.rot + l.rot);
  }
  for (const p of data.ports) {
    for (const l of p.labels ?? []) {
      const at = labelAnchor(p.placement, l);
      drawLabel(ctx, l, { x: at.x, y: at.y + style.portLabelOffset }, l.rot);
    }
  }
  for (const l of data.labels) drawLabel(ctx, l, l, l.rot);

  const bounds = isEmpty(ctx.bounds) ? { x0: 0, y0: 0, x1: 1000, y1: 1000 } : ctx.bounds;
  const bw = Math.max(bounds.x1 - bounds.x0, 1);
  const bh = Math.max(bounds.y1 - bounds.y0, 1);
  const margin = options.margin ?? 48;
  let s: number;
  if (options.fit) {
    s = Math.min((options.fit.width - 2 * margin) / bw, (options.fit.height - 2 * margin) / bh);
  } else {
    s = options.scale ?? 1;
  }
  const width = Math.round(bw * s + 2 * margin);
  const height = Math.round(bh * s + 2 * margin);
  if (!(s > 0 && Number.isFinite(s)) || width > MAX_PIXELS || height > MAX_PIXELS) {
    throw new RenderOptionError(`the drawing would be ${width}x${height} px at scale ${s}; the limit is ${MAX_PIXELS} px a side`);
  }
  const vx = bounds.x0 - (width - bw * s) / 2 / s;
  const vy = bounds.y0 - (height - bh * s) / 2 / s;
  const vb = [vx, vy, width / s, height / s].map(fmt).join(" ");

  const parts: string[] = [];
  parts.push(
    `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${width}" height="${height}" viewBox="${vb}">`,
  );
  parts.push(`<title>${escapeText(String(data.name))}</title>`);
  if (style.background !== null) {
    parts.push(`<rect x="${fmt(vx)}" y="${fmt(vy)}" width="${fmt(width / s)}" height="${fmt(height / s)}" fill="${escapeAttr(style.background)}"/>`);
  }
  // Studio's stacking: component bodies, then wires, then connectors on top
  // (an output connector's white fill hides the wire's end), then analysis
  // points and labels.
  parts.push(`<g id="components">`, ...ctx.bodies, `</g>`);
  parts.push(`<g id="wires">`, ...ctx.wires, `</g>`);
  parts.push(`<g id="connectors">`, ...ctx.connectors, ...ctx.ports, `</g>`);
  parts.push(`<g id="junctions">`, ...ctx.junctions, `</g>`);
  if (ctx.analysisPoints.length > 0) parts.push(`<g id="analysis-points">`, ...ctx.analysisPoints, `</g>`);
  parts.push(
    `<g id="labels" font-family="${escapeAttr(style.fontFamily)}" font-size="${fmt(style.labelFontSize)}" fill="${escapeAttr(style.labelColor)}" text-anchor="middle">`,
    ...ctx.labels,
    `</g>`,
  );
  parts.push(`</svg>`);
  return { svg: parts.join("\n") + "\n", width, height, scale: s, bounds, diagnostics: ctx.diagnostics };
}

class Context {
  bodies: string[] = [];
  connectors: string[] = [];
  wires: string[] = [];
  ports: string[] = [];
  junctions: string[] = [];
  analysisPoints: string[] = [];
  labels: string[] = [];
  diagnostics: string[] = [];
  bounds: Box = emptyBox();
  private next = 0;
  readonly style: DiagramStyle;
  readonly font: FontMetrics | undefined;

  constructor(style: DiagramStyle, font: FontMetrics | undefined) {
    this.style = style;
    this.font = font;
  }

  scope(): string {
    return `i${(this.next++).toString(36)}`;
  }
}

function wireColor(ctx: Context, conn: Connection): string {
  const stroke = conn.pathAttrs?.stroke;
  return typeof stroke === "string" ? stroke : ctx.style.wireColor;
}

/**
 * Where a boundary port's label goes: its anchor scaled with the placement's
 * box, but neither turned nor mirrored with it, so that a port's name stays
 * below the port whichever way it faces, as Studio draws it. (A component's
 * labels turn and mirror with the component; see `renderDiagram`.)
 */
export function labelAnchor(p: Placement, l: Point): Point {
  const cx = (p.x1 + p.x2) / 2;
  const cy = (p.y1 + p.y2) / 2;
  return {
    x: cx + ((l.x - 500) * Math.abs(p.x2 - p.x1)) / 1000,
    y: cy + ((l.y - 500) * Math.abs(p.y2 - p.y1)) / 1000,
  };
}

/** A plain box, for a component whose icon is not usable SVG. */
const FALLBACK_ICON =
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000"><rect x="20" y="20" width="960" height="960" fill="#f4f4f5" stroke="#a1a1aa" stroke-width="20"/></svg>';

/**
 * Draw an icon into the box a placement map sends the 1000 x 1000 icon box
 * to. The icon's `preserveAspectRatio` decides how it fills the box (by
 * default aspect kept and centred, so Studio does not stretch icons when the
 * box is not square; `none` stretches) and, as in Studio, the icon is cut to
 * the box.
 */
function drawIcon(ctx: Context, out: string[], icon: string, m: Matrix, owner: string): void {
  const f = boxFrame(m);
  const box = { x: -f.width / 2, y: -f.height / 2, width: f.width, height: f.height };
  let prepared = typeof icon === "string" ? prepareIcon(icon, ctx.scope(), box) : undefined;
  if (!prepared) {
    ctx.diagnostics.push(`${owner}: icon is not SVG; drawn as a plain box`);
    prepared = prepareIcon(FALLBACK_ICON, ctx.scope(), box)!;
  }
  for (const d of prepared.diagnostics) ctx.diagnostics.push(`${owner}: icon: ${d}`);
  let frame = multiply(translate(f.center.x, f.center.y), rotate(f.angle));
  if (f.flip) frame = multiply(frame, scale(1, -1));
  out.push(`<g transform="${matrixAttr(frame)}">${prepared.markup}</g>`);
  // What is drawn is the icon fitted into the box, cut to the box; that,
  // not the whole box, is what the drawing's bounds take in. Content outside
  // the viewBox (when it may have any) can show anywhere in the box.
  const fitted = fitViewBox(prepared.viewBox, prepared.aspect, box);
  const r = prepared.mayOverflow ? box : intersect(fitted, box);
  for (const [dx, dy] of [
    [r.x, r.y],
    [r.x + r.width, r.y],
    [r.x, r.y + r.height],
    [r.x + r.width, r.y + r.height],
  ]) {
    addPoint(ctx.bounds, apply(frame, { x: dx, y: dy }));
  }
}

type Rect = { x: number; y: number; width: number; height: number };

function intersect(a: Rect, b: Rect): Rect {
  const x = Math.max(a.x, b.x);
  const y = Math.max(a.y, b.y);
  return { x, y, width: Math.max(0, Math.min(a.x + a.width, b.x + b.width) - x), height: Math.max(0, Math.min(a.y + a.height, b.y + b.height) - y) };
}

function drawComponentBody(ctx: Context, c: ComponentShape): void {
  const start = ctx.bodies.length;
  drawIcon(ctx, ctx.bodies, c.icon, placementMatrix(c.placement), `component ${c.name}`);
  // The component's name (and type) go into an escaped attribute, never a comment.
  const type = c.type ? ` data-type="${escapeAttr(String(c.type))}"` : "";
  ctx.bodies[start] = `<g data-name="${escapeAttr(String(c.name))}"${type}>${ctx.bodies[start]}</g>`;
}

function drawComponentConnectors(ctx: Context, c: ComponentShape): void {
  const m = placementMatrix(c.placement);
  for (const conn of c.connectors) drawConnector(ctx, conn, m, c.name);
}

/**
 * A connector of a component. An array connector whose placement's `show`
 * allows it is fanned out into one copy per element, as Studio draws it.
 */
function drawConnector(ctx: Context, conn: ConnectorShape, parent: Matrix, component: string): void {
  const owner = `connector ${component}.${conn.name}`;
  // Studio fans an array connector out only when its placement has a `show`.
  const placements = conn.count !== undefined && conn.show !== undefined ? fanOut(conn.placement, conn.count, conn.show) : [conn.placement];
  for (const p of placements) drawIcon(ctx, ctx.connectors, conn.icon, multiply(parent, placementMatrix(p)), owner);
  noteClock(ctx, conn, owner);
}

function noteClock(ctx: Context, conn: ConnectorShape, owner: string): void {
  if (conn.clockInfo !== undefined && conn.clockInfo !== null) {
    ctx.diagnostics.push(`${owner}: clock information is not drawn`);
  }
}

/**
 * An analysis point, as Studio 3.5.1 draws it (measured from screenshots):
 * a crosshair in the wire's colour at the middle of the connection's wire
 * (a white disc of radius 12 with a 2-unit ring, a dot, and four ticks from
 * 9.5 to 15 units out), with the point's name above it, 20 units high.
 */
function drawAnalysisPoint(ctx: Context, conn: Connection, name: string): void {
  const route = conn.routes.map(simplify).find((r) => r.length >= 2);
  if (!route) {
    ctx.diagnostics.push(`analysis point ${name}: its connection has no wire to draw it on`);
    return;
  }
  const at = midpoint(route);
  const color = escapeAttr(wireColor(ctx, conn));
  const ticks = [
    [0, -1],
    [1, 0],
    [0, 1],
    [-1, 0],
  ]
    .map(([dx, dy]) => `M${fmt(at.x + dx * 9.5)} ${fmt(at.y + dy * 9.5)}L${fmt(at.x + dx * 15)} ${fmt(at.y + dy * 15)}`)
    .join("");
  const fs = 20;
  const baseline = at.y - 22.25;
  ctx.analysisPoints.push(
    `<g class="analysis-point">` +
      `<circle cx="${fmt(at.x)}" cy="${fmt(at.y)}" r="12" fill="#ffffff" stroke="${color}" stroke-width="2"/>` +
      `<circle cx="${fmt(at.x)}" cy="${fmt(at.y)}" r="3.75" fill="${color}"/>` +
      `<path d="${ticks}" stroke="${color}" stroke-width="2" fill="none"/>` +
      `<text x="${fmt(at.x)}" y="${fmt(baseline)}" font-family="${escapeAttr(ctx.style.fontFamily)}" font-size="${fs}" fill="${color}" text-anchor="middle">${escapeText(name)}</text>` +
      `</g>`,
  );
  addPoint(ctx.bounds, at, 15);
  const width = ctx.font ? measureText(ctx.font, name, fs) : 0.55 * fs * name.length;
  addPoint(ctx.bounds, { x: at.x - width / 2, y: baseline - fs * 0.8 });
  addPoint(ctx.bounds, { x: at.x + width / 2, y: baseline + fs * 0.25 });
}

/** The point halfway along a polyline. */
export function midpoint(pts: Point[]): Point {
  const lengths = pts.slice(1).map((p, i) => Math.hypot(p.x - pts[i].x, p.y - pts[i].y));
  let left = lengths.reduce((a, b) => a + b, 0) / 2;
  for (let i = 0; i < lengths.length; i++) {
    if (left <= lengths[i] && lengths[i] > 0) {
      const t = left / lengths[i];
      return { x: pts[i].x + (pts[i + 1].x - pts[i].x) * t, y: pts[i].y + (pts[i + 1].y - pts[i].y) * t };
    }
    left -= lengths[i];
  }
  return pts[pts.length - 1];
}

/**
 * A connection's wires: polylines with their bends rounded off, as Studio
 * draws them. All the routes of one connection are one `<path>`, so where
 * they run on top of each other (into a junction) the line does not darken.
 * Only the connector type's `stroke` is used; Studio sets the width itself.
 */
function drawWires(ctx: Context, routes: Point[][], stroke: string): void {
  let d = "";
  for (const pts of removeOverlaps(routes.map(simplify))) {
    if (pts.length < 2) continue;
    for (const p of pts) addPoint(ctx.bounds, p, ctx.style.wireWidth / 2);
    d += roundedPath(pts, ctx.style.wireCornerRadius);
  }
  if (d === "") return;
  ctx.wires.push(
    `<path d="${d}" fill="none" stroke="${escapeAttr(stroke)}" stroke-width="${fmt(ctx.style.wireWidth)}" stroke-linejoin="round" stroke-linecap="butt"/>`,
  );
}

/**
 * Cut from each polyline the stretches an earlier polyline of the same net
 * already covers. Routes into a junction often share a run; drawn twice, a
 * thin anti-aliased line comes out darker there. Only horizontal and
 * vertical runs are merged (Dyad's routes are orthogonal).
 */
export function removeOverlaps(lines: Point[][]): Point[][] {
  const covered = new Map<string, Array<[number, number]>>();
  const out: Point[][] = [];
  for (const pts of lines) {
    let current: Point[] = [];
    const flush = () => {
      if (current.length >= 2) out.push(current);
      current = [];
    };
    for (let i = 0; i + 1 < pts.length; i++) {
      const a = pts[i];
      const b = pts[i + 1];
      const horizontal = Math.abs(a.y - b.y) < 1e-6;
      const vertical = Math.abs(a.x - b.x) < 1e-6;
      let pieces: Array<[Point, Point]>;
      if (!horizontal && !vertical) {
        pieces = [[a, b]];
      } else {
        const key = horizontal ? `h${a.y.toFixed(3)}` : `v${a.x.toFixed(3)}`;
        const t0 = horizontal ? a.x : a.y;
        const t1 = horizontal ? b.x : b.y;
        const lo = Math.min(t0, t1);
        const hi = Math.max(t0, t1);
        const spans = covered.get(key) ?? [];
        const free = subtractSpans([lo, hi], spans);
        spans.push([lo, hi]);
        covered.set(key, spans);
        const at = (t: number): Point => (horizontal ? { x: t, y: a.y } : { x: a.x, y: t });
        // Keep the pieces in the segment's own direction.
        const ordered = t0 <= t1 ? free : free.map(([u, v]) => [v, u] as [number, number]).reverse();
        pieces = ordered.map(([u, v]) => [at(u), at(v)]);
      }
      for (const [p, q] of pieces) {
        const last = current[current.length - 1];
        if (last && Math.abs(last.x - p.x) < 1e-6 && Math.abs(last.y - p.y) < 1e-6) {
          current.push(q);
        } else {
          flush();
          current = [p, q];
        }
      }
      // A segment cut short ends the polyline there.
      const last = current[current.length - 1];
      if (!last || Math.abs(last.x - b.x) > 1e-6 || Math.abs(last.y - b.y) > 1e-6) flush();
    }
    flush();
  }
  return out;
}

/** The parts of `[lo, hi]` outside every span. */
function subtractSpans([lo, hi]: [number, number], spans: Array<[number, number]>): Array<[number, number]> {
  let free: Array<[number, number]> = [[lo, hi]];
  for (const [s0, s1] of spans) {
    const next: Array<[number, number]> = [];
    for (const [u, v] of free) {
      if (s1 <= u + 1e-6 || s0 >= v - 1e-6) {
        next.push([u, v]);
        continue;
      }
      if (s0 > u + 1e-6) next.push([u, s0]);
      if (s1 < v - 1e-6) next.push([s1, v]);
    }
    free = next;
  }
  return free.filter(([u, v]) => v - u > 1e-6);
}

/** Drop repeated points and points in the middle of a straight run. */
export function simplify(route: Point[]): Point[] {
  const out: Point[] = [];
  for (const p of route) {
    const last = out[out.length - 1];
    if (last && Math.abs(last.x - p.x) < 1e-6 && Math.abs(last.y - p.y) < 1e-6) continue;
    out.push(p);
    while (out.length >= 3) {
      const [a, b, c] = out.slice(-3);
      const cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      const dot = (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y);
      if (Math.abs(cross) < 1e-6 && dot >= 0) out.splice(out.length - 2, 1);
      else break;
    }
  }
  return out;
}

/** SVG path data for a polyline whose interior corners are rounded with radius `r`. */
export function roundedPath(pts: Point[], r: number): string {
  let d = `M${fmt(pts[0].x)} ${fmt(pts[0].y)}`;
  for (let i = 1; i < pts.length - 1; i++) {
    const a = pts[i - 1];
    const b = pts[i];
    const c = pts[i + 1];
    const lin = Math.hypot(b.x - a.x, b.y - a.y);
    const lout = Math.hypot(c.x - b.x, c.y - b.y);
    const rr = Math.min(r, lin / 2, lout / 2);
    if (rr <= 1e-6) {
      d += `L${fmt(b.x)} ${fmt(b.y)}`;
      continue;
    }
    const p1 = { x: b.x - ((b.x - a.x) / lin) * rr, y: b.y - ((b.y - a.y) / lin) * rr };
    const p2 = { x: b.x + ((c.x - b.x) / lout) * rr, y: b.y + ((c.y - b.y) / lout) * rr };
    d += `L${fmt(p1.x)} ${fmt(p1.y)}Q${fmt(b.x)} ${fmt(b.y)} ${fmt(p2.x)} ${fmt(p2.y)}`;
  }
  const last = pts[pts.length - 1];
  return d + `L${fmt(last.x)} ${fmt(last.y)}`;
}

/**
 * A label, centred on its anchor and turned by `turn`, but never upside
 * down (see {@link normalizeUpright}). The baseline is placed so
 * that the capital letters are centred on the anchor (CSS's `central`
 * baseline), computed here rather than left to the SVG renderer.
 */
function drawLabel(ctx: Context, label: Label, at: Point, turn: number): void {
  const text = String(label.text).trim();
  if (text === "") return;
  const fs = ctx.style.labelFontSize;
  const cap = ctx.font ? ctx.font.capHeight / ctx.font.unitsPerEm : 0.727;
  const width = ctx.font ? measureText(ctx.font, text, fs) : 0.55 * fs * text.length;
  const baseline = at.y + (cap * fs) / 2;
  const rot = normalizeUpright(turn);
  const transform = rot === 0 ? "" : ` transform="rotate(${fmt(rot)} ${fmt(at.x)} ${fmt(at.y)})"`;
  ctx.labels.push(`<text x="${fmt(at.x)}" y="${fmt(baseline)}"${transform}>${escapeText(text)}</text>`);
  // Bounds of the (possibly turned) text box.
  const m = multiply(translate(at.x, at.y), rotate(rot));
  for (const [dx, dy] of [
    [-width / 2, -fs * 0.6],
    [width / 2, -fs * 0.6],
    [-width / 2, fs * 0.6],
    [width / 2, fs * 0.6],
  ]) {
    addPoint(ctx.bounds, apply(m, { x: dx, y: dy }));
  }
}

/**
 * A rotation that never draws text upside down, as Studio turns labels: a
 * label turned by 90 degrees reads top to bottom, one turned by 270 bottom
 * to top, and one turned by 180 is drawn upright.
 */
export function normalizeUpright(rot: number): number {
  let r = ((rot % 360) + 360) % 360;
  if (r > 90 && r < 270) r -= 180;
  if (r > 180) r -= 360;
  return Object.is(r, -0) ? 0 : r;
}
