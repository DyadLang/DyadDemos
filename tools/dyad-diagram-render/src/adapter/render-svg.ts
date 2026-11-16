/**
 * Read the diagram back out of the SVG that `dyad render` (Dyad CLI 3.5)
 * prints.
 *
 * That SVG is the kernel's `GraphicalLayout` serialised by the kernel's own
 * renderer (`pkgs/kernel/src/codegen/icons/diagram.ts`), with every icon
 * fetched and every `$(...)` substituted. Its top-level children come in a
 * fixed order: components (`<g filter="url(#drop-shadow)">`), wires
 * (`<path>`), boundary connectors (`<g>` without a filter), junctions
 * (`<circle>`) and diagram labels (`<text>`). Each component's `<g>` holds a
 * 1000-unit `<svg>` with the icon layer, one `<g>` per connector and the
 * labels. Every `<g>` carries the kernel's
 * `translate(cx-500 cy-500) rotate(rot) scale(sw sh)` transform, from which
 * the placement is recovered exactly.
 *
 * Names are not in the SVG; `dyad-cli.ts` adds them from `dyad layout
 * extract`.
 */

import type { Label, Placement, Point } from "../model.ts";
import {
  type XmlElement,
  elementChildren,
  getAttr,
  parseXml,
  rootElement,
  serializeXml,
  textContent,
} from "../xml.ts";

export interface RenderedConnector {
  placement: Placement;
  icon: string;
}

export interface RenderedComponent {
  placement: Placement;
  icon: string;
  connectors: RenderedConnector[];
  labels: Label[];
}

export interface RenderedWire {
  points: Point[];
  attrs: Record<string, string>;
}

export interface RenderedDiagram {
  components: RenderedComponent[];
  ports: RenderedConnector[];
  wires: RenderedWire[];
  junctions: Array<{ point: Point; fill: string }>;
  labels: Label[];
}

export class RenderSvgError extends Error {}

const KERNEL_TRANSFORM =
  /^\s*translate\(\s*(-?[\d.e+-]+)[\s,]+(-?[\d.e+-]+)\s*\)\s*rotate\(\s*(-?[\d.e+-]+)\s*\)\s*scale\(\s*(-?[\d.e+-]+)[\s,]+(-?[\d.e+-]+)\s*\)\s*$/;

/** The placement a kernel `transform` attribute encodes (see `transformAttr`). */
export function placementFromTransform(transform: string | undefined): Placement {
  const m = transform === undefined ? null : KERNEL_TRANSFORM.exec(transform);
  if (!m) throw new RenderSvgError(`unexpected transform ${JSON.stringify(transform)}`);
  const [tx, ty, rot, sw, sh] = m.slice(1).map(Number);
  const cx = tx + 500;
  const cy = ty + 500;
  const w = sw * 1000;
  const h = sh * 1000;
  return { x1: cx - w / 2, x2: cx + w / 2, y1: cy - h / 2, y2: cy + h / 2, rot };
}

export function parseRenderSvg(svgText: string): RenderedDiagram {
  const root = rootElement(parseXml(svgText));
  if (!root || root.name !== "svg") throw new RenderSvgError("not an SVG document");
  const out: RenderedDiagram = { components: [], ports: [], wires: [], junctions: [], labels: [] };
  for (const el of elementChildren(root)) {
    switch (el.name) {
      case "defs":
        break;
      case "g":
        if (getAttr(el, "filter") !== undefined) out.components.push(readComponent(el));
        else out.ports.push(readConnector(el));
        break;
      case "path":
        out.wires.push(readWire(el));
        break;
      case "circle":
        out.junctions.push({
          point: { x: Number(getAttr(el, "cx")), y: Number(getAttr(el, "cy")) },
          fill: getAttr(el, "fill") ?? "black",
        });
        break;
      case "text":
        out.labels.push(readLabel(el));
        break;
      default:
        throw new RenderSvgError(`unexpected <${el.name}> at the top level`);
    }
  }
  return out;
}

function readComponent(g: XmlElement): RenderedComponent {
  const placement = placementFromTransform(getAttr(g, "transform"));
  const wrapper = elementChildren(g).find((e) => e.name === "svg");
  if (!wrapper) throw new RenderSvgError("component without an icon wrapper");
  const groups = elementChildren(wrapper).filter((e) => e.name === "g");
  const [iconLayer, ...connectorGroups] = groups;
  if (!iconLayer) throw new RenderSvgError("component without an icon layer");
  return {
    placement,
    icon: serializeXml(iconLayer.children).trim(),
    connectors: connectorGroups.map(readConnector),
    labels: elementChildren(wrapper)
      .filter((e) => e.name === "text")
      .map(readLabel),
  };
}

function readConnector(g: XmlElement): RenderedConnector {
  return {
    placement: placementFromTransform(getAttr(g, "transform")),
    icon: serializeXml(g.children).trim(),
  };
}

function readWire(p: XmlElement): RenderedWire {
  const d = getAttr(p, "d") ?? "";
  const nums = d.match(/-?\d*\.?\d+(?:e[+-]?\d+)?/gi)?.map(Number) ?? [];
  const points: Point[] = [];
  for (let i = 0; i + 1 < nums.length; i += 2) points.push({ x: nums[i], y: nums[i + 1] });
  const attrs: Record<string, string> = {};
  for (const [k, v] of p.attrs) {
    if (["d", "stroke-stroke", "fill", "vector-effect"].includes(k)) continue;
    attrs[k] = v;
  }
  return { points, attrs };
}

function readLabel(t: XmlElement): Label {
  const rotate = /rotate\(\s*(-?[\d.e+-]+)/.exec(getAttr(t, "transform") ?? "");
  const attrs: Record<string, string> = {};
  for (const [k, v] of t.attrs) {
    if (!["x", "y", "transform"].includes(k)) attrs[k] = v;
  }
  return {
    text: textContent(t),
    x: Number(getAttr(t, "x") ?? 0),
    y: Number(getAttr(t, "y") ?? 0),
    rot: rotate ? Number(rotate[1]) : 0,
    attrs,
  };
}
