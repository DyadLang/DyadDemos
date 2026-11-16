/** Affine transforms and boxes. */

import type { Placement, Point } from "./model.ts";

/** An affine map `[a, b, c, d, e, f]`, as SVG's `matrix(a b c d e f)`. */
export type Matrix = [number, number, number, number, number, number];

export const IDENTITY: Matrix = [1, 0, 0, 1, 0, 0];

/** The icon box size, in icon units (the kernel's `viewWidth`). */
export const ICON_SIZE = 1000;

export function multiply(m: Matrix, n: Matrix): Matrix {
  return [
    m[0] * n[0] + m[2] * n[1],
    m[1] * n[0] + m[3] * n[1],
    m[0] * n[2] + m[2] * n[3],
    m[1] * n[2] + m[3] * n[3],
    m[0] * n[4] + m[2] * n[5] + m[4],
    m[1] * n[4] + m[3] * n[5] + m[5],
  ];
}

export function translate(x: number, y: number): Matrix {
  return [1, 0, 0, 1, x, y];
}

export function scale(sx: number, sy: number = sx): Matrix {
  return [sx, 0, 0, sy, 0, 0];
}

export function rotate(deg: number): Matrix {
  const r = (deg * Math.PI) / 180;
  const c = Math.cos(r);
  const s = Math.sin(r);
  // Snap the right angles, so a 90 degree turn gives exact zeros.
  const snap = (v: number) => (Math.abs(v) < 1e-12 ? 0 : Math.abs(Math.abs(v) - 1) < 1e-12 ? Math.sign(v) : v);
  return [snap(c), snap(s), snap(-s), snap(c), 0, 0];
}

export function apply(m: Matrix, p: Point): Point {
  return { x: m[0] * p.x + m[2] * p.y + m[4], y: m[1] * p.x + m[3] * p.y + m[5] };
}

/**
 * The map from a placed icon's coordinates (0..1000) to its parent's
 * coordinates. It is the kernel's `iconPointOnDiagram`: scale the icon box to
 * the signed extent (a reversed extent flips), then rotate about the
 * extent's centre.
 */
export function placementMatrix(p: Placement): Matrix {
  const cx = (p.x1 + p.x2) / 2;
  const cy = (p.y1 + p.y2) / 2;
  return multiply(
    multiply(translate(cx, cy), rotate(p.rot)),
    multiply(scale((p.x2 - p.x1) / ICON_SIZE, (p.y2 - p.y1) / ICON_SIZE), translate(-ICON_SIZE / 2, -ICON_SIZE / 2)),
  );
}

/**
 * Split the map of a placed icon box into the parts an undistorted icon is
 * drawn with: where the box's centre lands, the turn and the flip, and the
 * lengths of the box's two sides. An icon drawn this way keeps its aspect
 * ratio inside a stretched box, as Studio draws it.
 */
export interface BoxFrame {
  center: Point;
  /** Degrees. */
  angle: number;
  /** Whether the map mirrors (negative determinant). */
  flip: boolean;
  /** Side lengths, along the box's own x and y axes. */
  width: number;
  height: number;
}

export function boxFrame(m: Matrix): BoxFrame {
  const center = apply(m, { x: ICON_SIZE / 2, y: ICON_SIZE / 2 });
  const xAxis = { x: m[0] * ICON_SIZE, y: m[1] * ICON_SIZE };
  const yAxis = { x: m[2] * ICON_SIZE, y: m[3] * ICON_SIZE };
  const det = m[0] * m[3] - m[1] * m[2];
  return {
    center,
    angle: (Math.atan2(xAxis.y, xAxis.x) * 180) / Math.PI,
    flip: det < 0,
    width: Math.hypot(xAxis.x, xAxis.y),
    height: Math.hypot(yAxis.x, yAxis.y),
  };
}

export interface Box {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
}

export function emptyBox(): Box {
  return { x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity };
}

export function addPoint(b: Box, p: Point, pad = 0): void {
  b.x0 = Math.min(b.x0, p.x - pad);
  b.y0 = Math.min(b.y0, p.y - pad);
  b.x1 = Math.max(b.x1, p.x + pad);
  b.y1 = Math.max(b.y1, p.y + pad);
}

export function isEmpty(b: Box): boolean {
  return !(b.x1 >= b.x0 && b.y1 >= b.y0);
}

/** Format a number for SVG output: short, and never `-0` or exponent form. */
export function fmt(v: number): string {
  if (!Number.isFinite(v)) return "0";
  const r = Math.round(v * 1000) / 1000;
  return Object.is(r, -0) ? "0" : String(r);
}

export function matrixAttr(m: Matrix): string {
  return `matrix(${m.map(fmt).join(" ")})`;
}

/** The longest array {@link fanOut} draws element by element (a copy per icon unit). */
export const MAX_FAN_OUT = 1000;

/**
 * The placements of an array connector's elements, fanned out the way the
 * Dyad kernel and Studio do it (in the icon's 0..1000 coordinates; for a
 * boundary port, in the diagram's nominal 0..1000 box, as Studio does):
 *
 * - only arrays of at least 2 elements, and not more than `show` (when
 *   given), are fanned out; anything else is one placement. (Studio, and
 *   the renderer, fan out only connectors whose placement has a `show`.)
 * - a connector on an edge of the icon (its centre in the outer 20 %) is
 *   repeated along that edge: copies of its own size, a pitch of up to two
 *   sizes, centred on the connector and kept within the 100..900 span (or
 *   within the placement itself when it is a long band along the edge);
 * - an interior connector's box is cut into `count` equal cells along its
 *   longer side.
 *
 * Arrays too long for the span, or longer than {@link MAX_FAN_OUT}, are
 * drawn once.
 */
export function fanOut(p: Placement, count: number, show: number | undefined): Placement[] {
  const { x1, y1, x2, y2 } = p;
  if (!Number.isInteger(count) || count < 2 || count > MAX_FAN_OUT || (show !== undefined && count > show) || ![x1, y1, x2, y2].every(Number.isFinite)) {
    return [p];
  }
  const w = Math.abs(x2 - x1);
  const h = Math.abs(y2 - y1);
  const cx = (x1 + x2) / 2;
  const cy = (y1 + y2) / 2;
  const edge = iconEdge(cx, cy);
  if (edge === undefined) {
    const alongX = w >= h;
    const cell = (alongX ? w : h) / count;
    const size = Math.min(cell, alongX ? h : w);
    const start = alongX ? Math.min(x1, x2) : Math.min(y1, y2);
    return Array.from({ length: count }, (_, i) => {
      const c = start + cell * (i + 0.5);
      return alongX
        ? { ...p, x1: c - size / 2, x2: c + size / 2, y1: cy - size / 2, y2: cy + size / 2 }
        : { ...p, x1: cx - size / 2, x2: cx + size / 2, y1: c - size / 2, y2: c + size / 2 };
    });
  }
  const vertical = edge === "left" || edge === "right";
  const along = vertical ? h : w;
  const cross = vertical ? w : h;
  const band = along > cross;
  const spanStart = band ? (vertical ? Math.min(y1, y2) : Math.min(x1, x2)) : 100;
  const spanLength = band ? along : 800;
  if (!(cross > 0) || count * cross > spanLength) return [p];
  const strip = Math.min((2 * count - 1) * cross, spanLength);
  const pitch = (strip - cross) / (count - 1);
  const centre = vertical ? cy : cx;
  const start = Math.min(Math.max(centre - strip / 2, spanStart), spanStart + spanLength - strip);
  return Array.from({ length: count }, (_, i) => {
    const lo = start + pitch * i;
    return vertical ? { ...p, y1: lo, y2: lo + cross } : { ...p, x1: lo, x2: lo + cross };
  });
}

/** The icon edge a point is near (within 20 % of the icon box), the nearer one at a corner. */
function iconEdge(x: number, y: number): "left" | "right" | "top" | "bottom" | undefined {
  const zone = 0.2 * ICON_SIZE;
  const v = x < zone ? "left" : x > ICON_SIZE - zone ? "right" : undefined;
  const hz = y < zone ? "top" : y > ICON_SIZE - zone ? "bottom" : undefined;
  if (v && hz) return (v === "left" ? x : ICON_SIZE - x) <= (hz === "top" ? y : ICON_SIZE - y) ? v : hz;
  return v ?? hz;
}
