/**
 * Making a library's SVG icon safe to inline many times in one document.
 *
 * Icons are separate SVG files, written to be shown on their own: several use
 * the same class names (`.b`, `.st0`) and ids with different meanings, and a
 * `<style>` sheet applies to the whole document it sits in. Inlined as they
 * are, the last icon's `.b` would restyle every other icon. So each inlined
 * copy gets its own scope: its classes and ids are renamed with a prefix, and
 * every selector in its style sheets is limited to the copy.
 *
 * Icons come from libraries, so they are also treated as untrusted. Nothing
 * in an inlined icon may run code or load anything:
 *
 * - `<script>`, `<foreignObject>` and other embedding elements, event-handler
 *   attributes (`on*`) and animations of links are removed;
 * - attributes are allowlisted per element (core, presentation and the
 *   element's own geometry). Attributes that may hold a URL but are not
 *   links (`ping`, `src`, `action`, `xml:base`, ...) are dropped; other
 *   unknown attributes (editor metadata) are dropped silently;
 * - every URL (`href`, `xlink:href`, `url(...)` in attributes and in style
 *   sheets) must be a fragment of the icon itself (`#id`) or, on an
 *   `<image>`, a `data:` image of a raster type or of SVG; SVG data is
 *   sanitised the same way, recursively. Anything else is dropped;
 * - style-sheet at-rules (`@import`, `@font-face`, `@media`, ...) and
 *   declarations with CSS escapes are dropped.
 *
 * Every removal but that of harmless unknown attributes is reported in
 * {@link PreparedIcon.diagnostics}.
 */

import {
  type XmlElement,
  type XmlNode,
  decodeEntities,
  escapeAttr,
  escapeText,
  getAttr,
  parseXml,
  removeAttr,
  rootElement,
  serializeXml,
  setAttr,
} from "./xml.ts";

/** How an icon's viewBox is fitted into its box (SVG's `preserveAspectRatio`). */
export interface AspectRatio {
  /** `none` stretches; otherwise where the viewBox is aligned, e.g. `xMidYMid`. */
  align: "none" | `x${"Min" | "Mid" | "Max"}Y${"Min" | "Mid" | "Max"}`;
  /** `slice` covers the box (cut to it), `meet` fits inside it. */
  slice: boolean;
}

export interface PreparedIcon {
  /** Markup for the icon: a `<g class=scope>` wrapping its `<svg>` element. */
  markup: string;
  /** The icon's viewBox, `[minX, minY, width, height]`. */
  viewBox: [number, number, number, number];
  /** The icon's own `preserveAspectRatio`. */
  aspect: AspectRatio;
  /**
   * Whether anything may be drawn outside the viewBox. Computed
   * conservatively: true unless every shape is simple enough to measure and
   * lies inside, strokes included.
   */
  mayOverflow: boolean;
  /**
   * What the content may paint, `[x0, y0, x1, y1]` in viewBox units, strokes
   * included (see {@link paintedBounds}); undefined when that cannot be told.
   */
  painted: [number, number, number, number] | undefined;
  /** What was removed from the icon, and why. */
  diagnostics: string[];
}

/** Elements that run code or embed other documents; removed with their content. */
const dropElements = new Set(["script", "foreignObject", "iframe", "embed", "object", "handler", "listener", "audio", "video"]);
const animations = new Set(["set", "animate", "animateMotion", "animateTransform", "animateColor"]);
/** Elements whose `href` may be a `data:` image. */
const imageElements = new Set(["image", "feImage"]);
const safeRasterTypes = new Set(["image/png", "image/jpeg", "image/jpg", "image/gif", "image/webp", "image/bmp"]);
/** How deep SVG `data:` images inside icons are followed. */
const MAX_NESTING = 2;

/**
 * Attributes that hold a URL (or a list of them) in SVG, HTML or XLink, other
 * than links. None is needed to draw an icon, so each is dropped with a
 * diagnostic.
 */
const urlAttributes = new Set([
  "ping", "src", "srcset", "action", "formaction", "background", "cite", "longdesc", "poster", "data", "codebase",
  "archive", "classid", "usemap", "manifest", "profile", "icon", "lowsrc", "dynsrc", "base", "arcrole",
  "requiredextensions", "itemtype", "itemid", "resource", "about", "vocab",
]);

/**
 * Attributes an inlined icon keeps: an allowlist. Every element may carry
 * the core attributes and SVG's presentation attributes; each element its
 * own geometry on top. Anything else is dropped: silently when it is
 * harmless (editor metadata such as `inkscape:label`, `data-name`), with a
 * diagnostic when it can carry a URL ({@link urlAttributes}). Links
 * (`href`, `xlink:href`, any `*href`) go through the URL policy, and so does
 * every kept value that contains `url(`.
 */
const coreAttributes = ["id", "class", "style", "lang", "xml:space", "xml:lang", "systemLanguage", "requiredFeatures", "role"];
const presentationAttributes = [
  "alignment-baseline", "baseline-shift", "clip", "clip-path", "clip-rule", "color", "color-interpolation",
  "color-interpolation-filters", "color-rendering", "direction", "display", "dominant-baseline",
  "enable-background", "fill", "fill-opacity", "fill-rule", "filter", "flood-color", "flood-opacity", "font",
  "font-family", "font-size", "font-size-adjust", "font-stretch", "font-style", "font-variant", "font-weight",
  "glyph-orientation-horizontal", "glyph-orientation-vertical", "image-rendering", "isolation", "kerning",
  "letter-spacing", "lighting-color", "marker", "marker-end", "marker-mid", "marker-start", "mask", "mask-type",
  "mix-blend-mode", "opacity", "overflow", "paint-order", "pointer-events", "shape-rendering", "stop-color",
  "stop-opacity", "stroke", "stroke-dasharray", "stroke-dashoffset", "stroke-linecap", "stroke-linejoin",
  "stroke-miterlimit", "stroke-opacity", "stroke-width", "text-anchor", "text-decoration", "text-rendering",
  "transform", "transform-origin", "unicode-bidi", "vector-effect", "visibility", "word-spacing", "writing-mode",
];
const box = ["x", "y", "width", "height"];
const textPosition = ["x", "y", "dx", "dy", "rotate", "textLength", "lengthAdjust"];
const gradient = ["gradientUnits", "gradientTransform", "spreadMethod"];
const filterPrimitive = [
  ...box, "result", "in", "in2", "stdDeviation", "edgeMode", "dx", "dy", "mode", "operator", "k1", "k2", "k3", "k4",
  "values", "type", "tableValues", "slope", "intercept", "amplitude", "exponent", "offset", "order", "kernelMatrix",
  "divisor", "bias", "targetX", "targetY", "preserveAlpha", "kernelUnitLength", "surfaceScale", "diffuseConstant",
  "specularConstant", "specularExponent", "scale", "xChannelSelector", "yChannelSelector", "radius",
  "baseFrequency", "numOctaves", "seed", "stitchTiles", "azimuth", "elevation", "z", "pointsAtX", "pointsAtY",
  "pointsAtZ", "limitingConeAngle", "preserveAspectRatio", "crossorigin",
];
const animation = [
  "attributeName", "attributeType", "from", "to", "by", "values", "dur", "begin", "end", "repeatCount", "repeatDur",
  "fill", "calcMode", "keyTimes", "keySplines", "keyPoints", "additive", "accumulate", "restart", "min", "max",
  "type", "path", "rotate", "origin",
];
const elementAttributes: Record<string, string[]> = {
  svg: [...box, "viewBox", "preserveAspectRatio", "version", "baseProfile", "zoomAndPan"],
  symbol: [...box, "viewBox", "preserveAspectRatio", "refX", "refY"],
  use: box,
  image: [...box, "preserveAspectRatio"],
  rect: [...box, "rx", "ry", "pathLength"],
  circle: ["cx", "cy", "r", "pathLength"],
  ellipse: ["cx", "cy", "rx", "ry", "pathLength"],
  line: ["x1", "y1", "x2", "y2", "pathLength"],
  polyline: ["points", "pathLength"],
  polygon: ["points", "pathLength"],
  path: ["d", "pathLength"],
  text: textPosition,
  tspan: textPosition,
  textPath: ["startOffset", "method", "spacing", "side", "textLength", "lengthAdjust"],
  marker: ["viewBox", "preserveAspectRatio", "refX", "refY", "markerUnits", "markerWidth", "markerHeight", "orient"],
  linearGradient: ["x1", "y1", "x2", "y2", ...gradient],
  radialGradient: ["cx", "cy", "r", "fx", "fy", "fr", ...gradient],
  stop: ["offset"],
  pattern: [...box, "patternUnits", "patternContentUnits", "patternTransform", "viewBox", "preserveAspectRatio"],
  clipPath: ["clipPathUnits"],
  mask: [...box, "maskUnits", "maskContentUnits"],
  filter: [...box, "filterUnits", "primitiveUnits"],
  style: ["type", "media", "title"],
  set: animation,
  animate: animation,
  animateColor: animation,
  animateMotion: animation,
  animateTransform: animation,
};

/** Whether an attribute (by its qualified name) is a link or may hold a URL. */
function isUrlAttribute(qname: string): boolean {
  const local = localName(qname).toLowerCase();
  return local.endsWith("href") || urlAttributes.has(local) || qname === "xlink:role";
}

const allowedFor = new Map<string, Set<string>>();

/** Whether an element may keep an attribute (by its qualified name). */
function attributeAllowed(element: string, attr: string): boolean {
  let set = allowedFor.get(element);
  if (!set) {
    const own = element.startsWith("fe") ? filterPrimitive : (elementAttributes[element] ?? []);
    set = new Set([...coreAttributes, ...presentationAttributes, ...own]);
    allowedFor.set(element, set);
  }
  return set.has(attr) || /^aria-[a-z]+$/.test(attr);
}

/**
 * Prepare an icon for inlining.
 *
 * The icon's own size is dropped, as the Dyad kernel's `iconLayer` does, and
 * the `<svg>` is given `box` instead: its own `viewBox` and
 * `preserveAspectRatio` (by default centred, aspect kept) decide how it fills
 * the box. Like Studio, the icon is cut to the box (`overflow="hidden"`).
 *
 * @param source The icon's SVG markup
 * @param scope A prefix unique within the output document (`[A-Za-z][\w-]*`)
 * @param box Where the icon is drawn, in the parent's coordinates
 * @returns The scoped markup, or undefined if the markup is not SVG
 */
export function prepareIcon(
  source: string,
  scope: string,
  box: { x: number; y: number; width: number; height: number } = { x: 0, y: 0, width: 1000, height: 1000 },
): PreparedIcon | undefined {
  const svg = parseSvg(source);
  if (!svg) return undefined;

  const viewBox = parseViewBox(attrValue(svg, "viewBox")) ?? intrinsicViewBox(svg);
  const aspect = parseAspectRatio(attrValue(svg, "preserveAspectRatio"));
  for (const a of ["width", "height", "x", "y", "overflow"]) removeAttr(svg, a);
  setAttr(svg, "viewBox", viewBox.join(" "));
  setAttr(svg, "x", fmtNum(box.x));
  setAttr(svg, "y", fmtNum(box.y));
  setAttr(svg, "width", fmtNum(box.width));
  setAttr(svg, "height", fmtNum(box.height));
  // Studio cuts an icon to its placement box; a root style may not undo that.
  const rootStyle = attrValue(svg, "style");
  if (rootStyle !== undefined) setAttr(svg, "style", escapeAttr(rootStyle.replace(/(^|;)\s*overflow\s*:[^;]*/gi, "$1")));
  setAttr(svg, "overflow", "hidden");

  const diagnostics: string[] = [];
  const ids = new Set<string>();
  collectIds(svg, ids);
  const renameId = (id: string) => (ids.has(id) ? `${scope}-${id}` : id);
  sanitizeElement(svg, { scope, renameId, diagnostics, depth: 0 });
  const painted = paintedBounds(svg, viewBox);
  const mayOverflow = outside(painted, viewBox);

  const wrapper: XmlElement = { kind: "element", name: "g", attrs: [["class", scope]], children: [svg] };
  return { markup: serializeXml(wrapper), viewBox, aspect, mayOverflow, painted, diagnostics };
}

function parseSvg(source: string): XmlElement | undefined {
  let nodes: XmlNode[];
  try {
    nodes = parseXml(source);
  } catch {
    return undefined;
  }
  const svg = rootElement(nodes);
  return svg && localName(svg.name) === "svg" ? svg : undefined;
}

interface SanitizeContext {
  /** Class prefix, or undefined to leave classes and selectors alone (a separate document). */
  scope?: string;
  renameId: (id: string) => string;
  diagnostics: string[];
  depth: number;
}

function collectIds(el: XmlElement, ids: Set<string>): void {
  const id = attrValue(el, "id");
  if (id !== undefined) ids.add(id);
  for (const c of el.children) if (c.kind === "element") collectIds(c, ids);
}

/**
 * Sanitise an element and everything below it, in place. Attribute values
 * are decoded before they are checked or rewritten, and written back
 * escaped, so an escaped reference (`url(&quot;#g&quot;)`) is treated like a
 * plain one and nothing can be hidden behind an entity.
 */
function sanitizeElement(e: XmlElement, ctx: SanitizeContext): void {
  const name = localName(e.name);
  e.children = e.children.filter((c) => {
    if (c.kind !== "element") return true;
    const n = localName(c.name);
    if (dropElements.has(n)) {
      ctx.diagnostics.push(`dropped <${c.name}>`);
      return false;
    }
    if (animations.has(n)) {
      const target = attrValue(c, "attributeName") ?? "";
      if (isUrlAttribute(target) || /^on/i.test(target)) {
        ctx.diagnostics.push(`dropped <${c.name}> animating ${target}`);
        return false;
      }
    }
    return true;
  });

  const attrs: Array<[string, string]> = [];
  for (const [k, raw] of e.attrs) {
    const key = localName(k);
    const v = decodeEntities(raw);
    if (/^on/i.test(key)) {
      ctx.diagnostics.push(`dropped event handler ${k} on <${e.name}>`);
      continue;
    }
    // Namespace declarations name a namespace; nothing is loaded from them.
    if (k === "xmlns" || k.startsWith("xmlns:")) {
      attrs.push([k, escapeAttr(v)]);
      continue;
    }
    if (isUrlAttribute(k) && !/href$/i.test(key)) {
      ctx.diagnostics.push(`dropped ${k}="${clip(v)}" on <${e.name}>: it may hold a URL`);
      continue;
    }
    if (!/href$/i.test(key) && !attributeAllowed(name, k)) continue;
    let out: string | undefined = v;
    if (k === "id") out = ctx.renameId(v);
    else if (k === "class" && ctx.scope !== undefined) {
      const scope = ctx.scope;
      out = v.split(/\s+/).filter(Boolean).map((c) => `${scope}-${c}`).join(" ");
    } else if (/href$/i.test(key)) {
      out = checkHref(v, imageElements.has(name), ctx);
      if (out === undefined) ctx.diagnostics.push(`dropped ${k}="${clip(v)}" on <${e.name}>: only #fragment links${imageElements.has(name) ? " and data: images" : ""} are allowed`);
    } else if (k === "style") {
      out = sanitizeDeclarations(v, ctx, `style on <${e.name}>`);
    } else if (/url\(|image-set\(|expression\(/i.test(v) || v.includes("\\")) {
      out = rewriteUrls(v, ctx);
      if (out === undefined) ctx.diagnostics.push(`dropped ${k}="${clip(v)}" on <${e.name}>: only url(#fragment) and data: images are allowed`);
    }
    if (out !== undefined) attrs.push([k, escapeAttr(out)]);
  }
  e.attrs = attrs;

  if (name === "style") {
    const css = e.children.map((c) => (c.kind === "text" ? cssText(c.text) : "")).join("");
    const scoped = ctx.scope !== undefined ? scopeCss(css, ctx.scope, ctx.renameId, ctx) : filterCss(css, ctx);
    // Written as escaped text, never CDATA, so no `]]>` in the sheet can end it.
    e.children = [{ kind: "text", text: escapeText(scoped) }];
    return;
  }
  for (const c of e.children) if (c.kind === "element") sanitizeElement(c, ctx);
}

function cssText(text: string): string {
  return text.replace(/<!\[CDATA\[([\s\S]*?)\]\]>|([^<]+)/g, (_m, cdata: string | undefined, plain: string | undefined) =>
    cdata !== undefined ? cdata : decodeEntities(plain ?? ""),
  );
}

function clip(s: string): string {
  return s.length > 60 ? `${s.slice(0, 57)}...` : s;
}

/** The allowed form of a link, or undefined if it is not allowed. */
function checkHref(v: string, image: boolean, ctx: SanitizeContext): string | undefined {
  const url = v.trim();
  if (url.startsWith("#")) return `#${ctx.renameId(url.slice(1))}`;
  if (image) return checkDataImage(url, ctx);
  return undefined;
}

/**
 * A `data:` URL of a safe image type, or undefined. SVG data is parsed and
 * sanitised (as its own document) and re-encoded; anything that cannot be is
 * dropped.
 */
function checkDataImage(url: string, ctx: SanitizeContext): string | undefined {
  const m = /^data:([^,]*?),(.*)$/is.exec(url.replace(/\s+/g, ""));
  if (!m) return undefined;
  const params = m[1].toLowerCase().split(";");
  const type = params[0];
  const base64 = params.includes("base64");
  const payload = m[2];
  if (safeRasterTypes.has(type)) {
    return base64 && /^[A-Za-z0-9+/=]*$/.test(payload) ? `data:${type};base64,${payload}` : undefined;
  }
  if (type !== "image/svg+xml") return undefined;
  if (ctx.depth >= MAX_NESTING) {
    ctx.diagnostics.push("dropped an SVG data: image nested too deep");
    return undefined;
  }
  let text: string;
  try {
    text = base64 ? Buffer.from(payload, "base64").toString("utf8") : decodeURIComponent(payload);
  } catch {
    return undefined;
  }
  const inner = parseSvg(text);
  if (!inner) return undefined;
  const nested: SanitizeContext = { renameId: (id) => id, diagnostics: [], depth: ctx.depth + 1 };
  sanitizeElement(inner, nested);
  for (const d of nested.diagnostics) ctx.diagnostics.push(`in an SVG data: image: ${d}`);
  return `data:image/svg+xml;base64,${Buffer.from(serializeXml(inner), "utf8").toString("base64")}`;
}

/**
 * Rewrite every `url(...)` in a CSS value or presentation attribute:
 * fragments are renamed, data: images checked. Returns undefined if any URL
 * (or a CSS escape, which could hide one) is not allowed.
 */
function rewriteUrls(value: string, ctx: SanitizeContext): string | undefined {
  if (value.includes("\\") || /image-set\(|expression\(|-moz-binding/i.test(value)) return undefined;
  let ok = true;
  let taken = 0;
  const out = value.replace(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)'"\s]*))\s*\)/gi, (_m, dq?: string, sq?: string, bare?: string) => {
    taken++;
    const url = (dq ?? sq ?? bare ?? "").trim();
    if (url.startsWith("#")) return `url(#${ctx.renameId(url.slice(1))})`;
    const data = checkDataImage(url, ctx);
    if (data === undefined) ok = false;
    return `url("${data ?? ""}")`;
  });
  // A `url(` the pattern did not take (unbalanced, odd quoting) is refused.
  if (!ok || (value.match(/url\(/gi)?.length ?? 0) !== taken) return undefined;
  return out;
}

/** Split CSS declarations on `;`, outside parentheses and strings. */
function splitDeclarations(body: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let quote = "";
  let start = 0;
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (quote) {
      if (c === quote) quote = "";
    } else if (c === '"' || c === "'") quote = c;
    else if (c === "(") depth++;
    else if (c === ")") depth = Math.max(0, depth - 1);
    else if (c === ";" && depth === 0) {
      out.push(body.slice(start, i));
      start = i + 1;
    }
  }
  out.push(body.slice(start));
  return out.map((d) => d.trim()).filter(Boolean);
}

/** Keep only the declarations whose URLs are allowed. */
function sanitizeDeclarations(body: string, ctx: SanitizeContext, where: string): string {
  const kept: string[] = [];
  for (const decl of splitDeclarations(body)) {
    if (!/url\(|image-set\(|expression\(|-moz-binding/i.test(decl) && !decl.includes("\\")) {
      kept.push(decl);
      continue;
    }
    const v = rewriteUrls(decl, ctx);
    if (v === undefined) ctx.diagnostics.push(`dropped "${clip(decl)}" from ${where}: only url(#fragment) and data: images are allowed`);
    else kept.push(v);
  }
  return kept.join(";");
}

function fmtNum(v: number): string {
  const r = Math.round(v * 1000) / 1000;
  return Object.is(r, -0) ? "0" : String(r);
}

function localName(name: string): string {
  const i = name.indexOf(":");
  return i === -1 ? name : name.slice(i + 1);
}

function attrValue(el: XmlElement, name: string): string | undefined {
  const v = getAttr(el, name);
  return v === undefined ? undefined : decodeEntities(v);
}

export function parseViewBox(v: string | undefined): [number, number, number, number] | undefined {
  if (v === undefined) return undefined;
  const parts = v.trim().split(/[\s,]+/).map(Number);
  if (parts.length !== 4 || parts.some((p) => !Number.isFinite(p)) || parts[2] <= 0 || parts[3] <= 0) {
    return undefined;
  }
  return parts as [number, number, number, number];
}

/** SVG's `preserveAspectRatio`; anything unreadable is the default, `xMidYMid meet`. */
export function parseAspectRatio(v: string | undefined): AspectRatio {
  const words = (v ?? "").trim().split(/\s+/).filter((w) => w !== "defer");
  const align = words[0];
  if (align === "none") return { align: "none", slice: false };
  if (align !== undefined && /^x(Min|Mid|Max)Y(Min|Mid|Max)$/.test(align)) {
    return { align: align as AspectRatio["align"], slice: words[1] === "slice" };
  }
  return { align: "xMidYMid", slice: false };
}

/**
 * Where a viewBox lands when fitted into a box, following
 * `preserveAspectRatio`: the scale on each axis and the drawn rectangle.
 */
export function fitViewBox(
  viewBox: [number, number, number, number],
  aspect: AspectRatio,
  box: { x: number; y: number; width: number; height: number },
): { sx: number; sy: number; x: number; y: number; width: number; height: number } {
  const [, , vw, vh] = viewBox;
  if (aspect.align === "none") {
    return { sx: box.width / vw, sy: box.height / vh, ...box };
  }
  const s = aspect.slice ? Math.max(box.width / vw, box.height / vh) : Math.min(box.width / vw, box.height / vh);
  const w = vw * s;
  const h = vh * s;
  const ax = aspect.align.slice(1, 4);
  const ay = aspect.align.slice(5, 8);
  const off = (a: string, free: number) => (a === "Min" ? 0 : a === "Mid" ? free / 2 : free);
  return { sx: s, sy: s, x: box.x + off(ax, box.width - w), y: box.y + off(ay, box.height - h), width: w, height: h };
}

function intrinsicViewBox(svg: XmlElement): [number, number, number, number] {
  const w = parseFloat(getAttr(svg, "width") ?? "");
  const h = parseFloat(getAttr(svg, "height") ?? "");
  return [0, 0, Number.isFinite(w) && w > 0 ? w : 1000, Number.isFinite(h) && h > 0 ? h : 1000];
}

/** Elements whose content is not drawn where it stands. */
const notDrawn = new Set(["defs", "clipPath", "mask", "marker", "pattern", "symbol", "linearGradient", "radialGradient", "filter", "style", "title", "desc", "metadata"]);

type Rect4 = [number, number, number, number];

/**
 * Whether anything in an icon may be drawn outside its viewBox: true unless
 * {@link paintedBounds} can measure the content and it lies inside.
 */
export function contentMayOverflow(svg: XmlElement, viewBox: Rect4): boolean {
  return outside(paintedBounds(svg, viewBox), viewBox);
}

/** Whether painted bounds (undefined: unknown) may reach outside a viewBox. */
function outside(b: Rect4 | undefined, viewBox: Rect4): boolean {
  if (b === undefined) return true;
  const [vx, vy, vw, vh] = viewBox;
  const eps = 1e-9 * Math.max(vw, vh);
  return b[0] < vx - eps || b[1] < vy - eps || b[2] > vx + vw + eps || b[3] > vy + vh + eps;
}

/**
 * The box, `[x0, y0, x1, y1]` in viewBox units, that an icon's content may
 * paint, strokes included; undefined when that cannot be told.
 *
 * Only simple shapes without transforms are measured (paths by their
 * control points, which bound the curve; arcs by their ellipse). Text,
 * `<use>`, images, nested `<svg>`, transforms, markers, filters and
 * non-scaling strokes make the result unknown. A stroked shape is widened
 * by half its stroke width (from its own or inherited attributes and
 * `style`); a shape with corners by that times the largest
 * `stroke-miterlimit` (4 by default) unless no join can be a miter; and √2
 * times it if any cap is square. Style sheets are not matched to elements:
 * if one sets `stroke` or `stroke-width`, every shape is taken to have the
 * widest. With nothing drawn, the box is the viewBox.
 */
export function paintedBounds(svg: XmlElement, viewBox: Rect4): Rect4 | undefined {
  const stroke = strokeStyle(svg, viewBox);
  if (stroke === undefined) return undefined;
  const out: Rect4 = [Infinity, Infinity, -Infinity, -Infinity];
  const num = (e: XmlElement, a: string, d = 0) => {
    const v = attrValue(e, a);
    if (v === undefined) return d;
    const n = Number(v.trim());
    return Number.isFinite(n) ? n : NaN;
  };
  // False when the element's painting cannot be measured.
  const visit = (e: XmlElement, inherited: { stroked: boolean; width: number }): boolean => {
    const n = localName(e.name);
    if (notDrawn.has(n)) return true;
    // The element's own stroke and width (a `style` declaration wins over
    // the attribute), else its parent's.
    const own = ownDeclarations(e);
    const paint = own.get("stroke");
    const stroked = paint === undefined || paint === "inherit" ? inherited.stroked : paint !== "none";
    const ownWidth = own.get("stroke-width");
    const parsed = ownWidth === undefined ? null : stroke.width(ownWidth);
    if (parsed === undefined) return false;
    const width = parsed ?? inherited.width;
    if (attrValue(e, "transform") !== undefined || /transform/i.test(attrValue(e, "style") ?? "")) return false;
    let pts: number[] | undefined;
    // Whether the shape has corners, where a miter join can reach further.
    let corners = true;
    switch (n) {
      case "g":
      case "a":
      case "switch":
        break;
      case "svg":
        if (e !== svg) return false;
        break;
      case "rect": {
        const x = num(e, "x"), y = num(e, "y"), w = num(e, "width"), h = num(e, "height");
        pts = [x, y, x + w, y + h];
        break;
      }
      case "circle":
      case "ellipse": {
        const cx = num(e, "cx"), cy = num(e, "cy");
        const rx = n === "circle" ? num(e, "r") : num(e, "rx");
        const ry = n === "circle" ? num(e, "r") : num(e, "ry");
        pts = [cx - rx, cy - ry, cx + rx, cy + ry];
        corners = false;
        break;
      }
      case "line":
        pts = [num(e, "x1"), num(e, "y1"), num(e, "x2"), num(e, "y2")];
        corners = false;
        break;
      case "polyline":
      case "polygon":
        pts = (attrValue(e, "points") ?? "").trim().split(/[\s,]+/).filter(Boolean).map(Number);
        break;
      case "path":
        pts = pathPoints(attrValue(e, "d") ?? "");
        // One straight segment has no join (a closed one is a join).
        corners = pts.length > 4 || /z/i.test(attrValue(e, "d") ?? "");
        break;
      default:
        return false;
    }
    if (pts) {
      if (pts.some((p) => !Number.isFinite(p))) return false;
      // A style sheet may stroke anything (its selectors are not matched).
      const half = stroked || stroke.sheetStroked ? Math.max(width, stroke.sheetWidth) / 2 : 0;
      const reach = half * (corners ? Math.max(stroke.cap, stroke.join) : stroke.cap);
      for (let i = 0; i + 1 < pts.length; i += 2) {
        out[0] = Math.min(out[0], pts[i] - reach);
        out[1] = Math.min(out[1], pts[i + 1] - reach);
        out[2] = Math.max(out[2], pts[i] + reach);
        out[3] = Math.max(out[3], pts[i + 1] + reach);
      }
    }
    return e.children.every((c) => c.kind !== "element" || visit(c, { stroked, width }));
  };
  if (!visit(svg, { stroked: false, width: 1 })) return undefined;
  if (!(out[2] >= out[0] && out[3] >= out[1])) {
    const [vx, vy, vw, vh] = viewBox;
    return [vx, vy, vx + vw, vy + vh];
  }
  return out;
}

/** An element's own presentation attributes and `style` declarations (which win), lower-cased. */
function ownDeclarations(e: XmlElement): Map<string, string> {
  const out = new Map<string, string>();
  const put = (k: string, v: string) => out.set(k.trim().toLowerCase(), v.replace(/!\s*important\s*$/i, "").trim().toLowerCase());
  for (const [k, raw] of e.attrs) if (k !== "style") put(k, decodeEntities(raw));
  for (const d of splitDeclarations(attrValue(e, "style") ?? "")) {
    const i = d.indexOf(":");
    if (i > 0) put(d.slice(0, i), d.slice(i + 1));
  }
  return out;
}

/**
 * What decides how far strokes reach in an icon (see {@link
 * paintedBounds}): the factors for caps and joins, what its style sheets
 * set (they may apply to any element), and how to read a stroke width.
 * Undefined if that cannot be told (an unreadable width in a style sheet,
 * markers, filters, non-scaling strokes).
 */
function strokeStyle(
  svg: XmlElement,
  viewBox: Rect4,
): { cap: number; join: number; sheetStroked: boolean; sheetWidth: number; width: (v: string) => number | null | undefined } | undefined {
  const all = new Map<string, string[]>();
  const sheets = new Map<string, string[]>();
  const add = (into: Map<string, string[]>, k: string, v: string) => {
    const key = k.trim().toLowerCase();
    into.set(key, [...(into.get(key) ?? []), v.replace(/!\s*important\s*$/i, "").trim().toLowerCase()]);
  };
  const walkElement = (e: XmlElement) => {
    for (const [k, v] of ownDeclarations(e)) add(all, k, v);
    if (localName(e.name) === "style") {
      const css = e.children.map((c) => (c.kind === "text" ? cssText(c.text) : "")).join("");
      // Every rule's declarations, whatever its selector.
      for (const m of css.replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/\{([^{}]*)\}/g)) {
        for (const d of splitDeclarations(m[1])) {
          const i = d.indexOf(":");
          if (i <= 0) continue;
          add(all, d.slice(0, i), d.slice(i + 1));
          add(sheets, d.slice(0, i), d.slice(i + 1));
        }
      }
    }
    for (const c of e.children) if (c.kind === "element") walkElement(c);
  };
  walkElement(svg);

  const values = (k: string) => all.get(k) ?? [];
  if (["marker", "marker-start", "marker-mid", "marker-end", "filter"].some((k) => values(k).some((v) => v !== "none"))) return undefined;
  if (values("vector-effect").some((v) => v.includes("non-scaling-stroke"))) return undefined;

  const [, , vw, vh] = viewBox;
  const units: Record<string, number> = { "": 1, px: 1, pt: 4 / 3, pc: 16, in: 96, cm: 96 / 2.54, mm: 96 / 25.4, "%": Math.hypot(vw, vh) / Math.SQRT2 / 100 };
  // A width in user units; null for one that is inherited; undefined if unreadable.
  const width = (v: string): number | null | undefined => {
    if (v === "inherit" || v === "initial" || v === "unset") return null;
    const m = /^\+?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?(px|pt|pc|in|cm|mm|%)?$/.exec(v);
    if (!m) return undefined;
    const w = Number(m[1] + (m[2] ?? "")) * units[m[3] ?? ""];
    return Number.isFinite(w) ? w : undefined;
  };
  let sheetWidth = 0;
  for (const v of sheets.get("stroke-width") ?? []) {
    const w = width(v);
    if (w === undefined) return undefined;
    sheetWidth = Math.max(sheetWidth, w ?? 0);
  }
  const sheetStroked = (sheets.get("stroke") ?? []).some((v) => v !== "none");
  // A square cap reaches half the width diagonally past the end; butt and
  // round caps (the default is butt) half the width.
  const cap = values("stroke-linecap").some((v) => v !== "butt" && v !== "round") ? Math.SQRT2 : 1;
  // A miter join (the default) reaches up to half the width times the miter
  // limit (4 by default). None can be a miter when the root sets a round or
  // bevel join, which everything inherits, and nothing sets another.
  let miter = 4;
  for (const v of values("stroke-miterlimit")) {
    const n = Number(v);
    if (Number.isFinite(n) && n >= 1) miter = Math.max(miter, n);
  }
  const rootJoin = ownDeclarations(svg).get("stroke-linejoin");
  const noMiter = (rootJoin === "round" || rootJoin === "bevel") && values("stroke-linejoin").every((v) => v === "round" || v === "bevel");
  return { cap, join: noMiter ? 1 : miter, sheetStroked, sheetWidth, width };
}

/**
 * The end and control points of a path, absolute, as `[x0, y0, x1, y1,
 * ...]`; for arcs, the corners of a box their ellipse stays in.
 *
 * Path data is read as SVG specifies, with its implicit commands (pairs
 * after a moveto are linetos; a command's parameters may repeat), and, as
 * browsers do, only up to the first error: what follows is not drawn, so
 * it is not measured. Every step reads at least one character, so no input
 * can make it loop.
 */
export function pathPoints(d: string): number[] {
  const out: number[] = [];
  const n = d.length;
  let pos = 0;
  const skip = () => {
    while (pos < n && /[\s,]/.test(d[pos])) pos++;
  };
  const numberAt = /[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/y;
  const number = (): number | undefined => {
    skip();
    numberAt.lastIndex = pos;
    const m = numberAt.exec(d);
    if (!m) return undefined;
    pos = numberAt.lastIndex;
    return Number(m[0]);
  };
  const flag = (): number | undefined => {
    skip();
    const c = d[pos];
    if (c !== "0" && c !== "1") return undefined;
    pos++;
    return Number(c);
  };
  const arity: Record<string, number> = { m: 2, l: 2, h: 1, v: 1, c: 6, s: 4, q: 4, t: 2, a: 7 };
  let cmd = "";
  let x = 0, y = 0, sx = 0, sy = 0;
  skip();
  while (pos < n) {
    const start = pos;
    if (/[MmLlHhVvCcSsQqTtAaZz]/.test(d[pos])) {
      cmd = d[pos++];
      // Path data must start with a moveto.
      if (out.length === 0 && cmd !== "M" && cmd !== "m") break;
    } else if (cmd === "" || cmd === "Z" || cmd === "z") {
      // Numbers with no command to repeat: an error.
      break;
    }
    const lower = cmd.toLowerCase();
    const rel = cmd === lower;
    if (lower === "z") {
      x = sx;
      y = sy;
      skip();
      continue;
    }
    const a: number[] = [];
    for (let j = 0; j < arity[lower]; j++) {
      const v = lower === "a" && (j === 3 || j === 4) ? flag() : number();
      if (v === undefined) break;
      a.push(v);
    }
    if (a.length < arity[lower] || a.some((v) => !Number.isFinite(v))) break;
    const ox = rel ? x : 0;
    const oy = rel ? y : 0;
    switch (lower) {
      case "h":
        x = ox + a[0];
        out.push(x, y);
        break;
      case "v":
        y = oy + a[0];
        out.push(x, y);
        break;
      case "a": {
        const ex = ox + a[5], ey = oy + a[6];
        const r = arcReach(x, y, ex, ey, a[0], a[1], a[2]);
        out.push(ex, ey);
        // The ellipse's centre is within r of both ends, the arc within r of the centre.
        if (r > 0) out.push(Math.max(x, ex) - 2 * r, Math.max(y, ey) - 2 * r, Math.min(x, ex) + 2 * r, Math.min(y, ey) + 2 * r);
        x = ex;
        y = ey;
        break;
      }
      default:
        for (let j = 0; j < a.length; j += 2) out.push(ox + a[j], oy + a[j + 1]);
        x = ox + a[a.length - 2];
        y = oy + a[a.length - 1];
    }
    if (lower === "m") {
      sx = x;
      sy = y;
      // Further pairs after a moveto are linetos.
      cmd = rel ? "l" : "L";
    }
    skip();
    // Never reached (every step above reads something); a guard all the same.
    if (pos === start) break;
  }
  return out;
}

/**
 * The larger radius of an arc's ellipse, after SVG scales radii too small
 * to join the ends; 0 for a straight line.
 */
function arcReach(x0: number, y0: number, x1: number, y1: number, rx: number, ry: number, angle: number): number {
  rx = Math.abs(rx);
  ry = Math.abs(ry);
  if (rx === 0 || ry === 0) return 0;
  const phi = (angle * Math.PI) / 180;
  const dx = (x0 - x1) / 2;
  const dy = (y0 - y1) / 2;
  const px = Math.cos(phi) * dx + Math.sin(phi) * dy;
  const py = -Math.sin(phi) * dx + Math.cos(phi) * dy;
  const lambda = (px * px) / (rx * rx) + (py * py) / (ry * ry);
  return Math.max(rx, ry) * Math.max(1, Math.sqrt(lambda));
}

/**
 * Limit a style sheet to one icon: every selector is prefixed with the scope
 * class and its class and id names are renamed the way the markup's are.
 * At-rules (`@import`, `@font-face`, `@media`) are dropped, and so are
 * declarations whose URLs are not allowed; each is reported in `diagnostics`.
 */
export function scopeCss(
  css: string,
  scope: string,
  renameId: (id: string) => string = (id) => `${scope}-${id}`,
  ctx: { diagnostics: string[]; depth?: number } = { diagnostics: [] },
): string {
  const full: SanitizeContext = { scope, renameId, diagnostics: ctx.diagnostics, depth: ctx.depth ?? 0 };
  return eachRule(css, full, (prelude) =>
    prelude
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean)
      .map((s) => {
        const renamed = s
          .replace(/\.(-?[_a-zA-Z][\w-]*)/g, (_m, c: string) => `.${scope}-${c}`)
          .replace(/#(-?[_a-zA-Z][\w-]*)/g, (_m, id: string) => `#${renameId(id)}`);
        return `.${scope} ${renamed}`;
      })
      .join(","),
  );
}

/** {@link scopeCss} without scoping, for an SVG data: image (its own document). */
function filterCss(css: string, ctx: SanitizeContext): string {
  return eachRule(css, ctx, (prelude) => prelude);
}

function eachRule(css: string, ctx: SanitizeContext, selectors: (prelude: string) => string): string {
  const src = css.replace(/\/\*[\s\S]*?\*\//g, "");
  let out = "";
  let i = 0;
  while (i < src.length) {
    const open = src.indexOf("{", i);
    const semi = src.indexOf(";", i);
    // A statement at-rule (`@import url(x);`) has no block.
    if (semi !== -1 && (open === -1 || semi < open) && src.slice(i, semi).trim().startsWith("@")) {
      ctx.diagnostics.push(`dropped "${clip(src.slice(i, semi).trim())}" from a style sheet`);
      i = semi + 1;
      continue;
    }
    if (open === -1) break;
    const prelude = src.slice(i, open).trim();
    // Find the matching close brace (blocks of at-rules may nest).
    let depth = 1;
    let j = open + 1;
    for (; j < src.length && depth > 0; j++) {
      if (src[j] === "{") depth++;
      else if (src[j] === "}") depth--;
    }
    // An unclosed block runs to the end of the sheet.
    const body = src.slice(open + 1, depth === 0 ? j - 1 : j);
    i = j;
    if (prelude.startsWith("@")) {
      ctx.diagnostics.push(`dropped "${clip(prelude)}" block from a style sheet`);
      continue;
    }
    if (prelude === "" || prelude.includes("\\")) continue;
    const value = sanitizeDeclarations(body, ctx, "a style sheet");
    out += `${selectors(prelude)}{${value}}\n`;
  }
  return out;
}
