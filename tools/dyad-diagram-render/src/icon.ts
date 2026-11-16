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
 * - every URL (`href`, `xlink:href`, `url(...)` in attributes and in style
 *   sheets) must be a fragment of the icon itself (`#id`) or, on an
 *   `<image>`, a `data:` image of a raster type or of SVG; SVG data is
 *   sanitised the same way, recursively. Anything else is dropped;
 * - style-sheet at-rules (`@import`, `@font-face`, `@media`, ...) and
 *   declarations with CSS escapes are dropped.
 *
 * Every removal is reported in {@link PreparedIcon.diagnostics}.
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
   * lies inside.
   */
  mayOverflow: boolean;
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
  const mayOverflow = contentMayOverflow(svg, viewBox);

  const wrapper: XmlElement = { kind: "element", name: "g", attrs: [["class", scope]], children: [svg] };
  return { markup: serializeXml(wrapper), viewBox, aspect, mayOverflow, diagnostics };
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
      if (/(^|:)href$/i.test(target) || /^on/i.test(target)) {
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
    if (k === "xml:base") {
      ctx.diagnostics.push(`dropped xml:base on <${e.name}>`);
      continue;
    }
    let out: string | undefined = v;
    if (k === "id") out = ctx.renameId(v);
    else if (k === "class" && ctx.scope !== undefined) {
      const scope = ctx.scope;
      out = v.split(/\s+/).filter(Boolean).map((c) => `${scope}-${c}`).join(" ");
    } else if (key === "href") {
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

/**
 * Whether anything in an icon may be drawn outside its viewBox. Only simple
 * shapes without transforms are measured (paths by their control points,
 * which bound the curve); anything else (text, `<use>`, images, nested
 * `<svg>`, transforms) counts as possibly outside. A margin of 2 % of the
 * viewBox allows for strokes on the edge.
 */
export function contentMayOverflow(svg: XmlElement, viewBox: [number, number, number, number]): boolean {
  const [vx, vy, vw, vh] = viewBox;
  const pad = 0.02 * Math.max(vw, vh);
  const inside = (x: number, y: number) => x >= vx - pad && x <= vx + vw + pad && y >= vy - pad && y <= vy + vh + pad;
  const num = (e: XmlElement, a: string, d = 0) => {
    const v = attrValue(e, a);
    if (v === undefined) return d;
    const n = Number(v.trim());
    return Number.isFinite(n) ? n : NaN;
  };
  const check = (e: XmlElement): boolean => {
    const n = localName(e.name);
    if (notDrawn.has(n)) return false;
    if (attrValue(e, "transform") !== undefined || /transform/i.test(attrValue(e, "style") ?? "")) return true;
    let pts: number[] | undefined;
    switch (n) {
      case "g":
      case "a":
      case "switch":
        break;
      case "svg":
        if (e !== svg) return true;
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
        break;
      }
      case "line":
        pts = [num(e, "x1"), num(e, "y1"), num(e, "x2"), num(e, "y2")];
        break;
      case "polyline":
      case "polygon":
        pts = (attrValue(e, "points") ?? "").trim().split(/[\s,]+/).filter(Boolean).map(Number);
        break;
      case "path":
        pts = pathPoints(attrValue(e, "d") ?? "");
        if (pts === undefined) return true;
        break;
      default:
        return true;
    }
    if (pts) {
      if (pts.some((p) => !Number.isFinite(p))) return true;
      for (let i = 0; i + 1 < pts.length; i += 2) if (!inside(pts[i], pts[i + 1])) return true;
    }
    return e.children.some((c) => c.kind === "element" && check(c));
  };
  return check(svg);
}

/**
 * The end and control points of a path, absolute, as `[x0, y0, x1, y1,
 * ...]`; for arcs, the corners of the box the arc's ellipse could reach.
 * Undefined if the path data cannot be read.
 */
export function pathPoints(d: string): number[] | undefined {
  const tokens = d.match(/[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/g);
  if (!tokens) return [];
  const out: number[] = [];
  let i = 0;
  let cmd = "";
  let x = 0, y = 0, sx = 0, sy = 0;
  const arity: Record<string, number> = { m: 2, l: 2, h: 1, v: 1, c: 6, s: 4, q: 4, t: 2, a: 7, z: 0 };
  while (i < tokens.length) {
    if (/[A-Za-z]/.test(tokens[i])) cmd = tokens[i++];
    else if (cmd === "") return undefined;
    const lower = cmd.toLowerCase();
    const rel = cmd === lower;
    if (lower === "z") {
      x = sx;
      y = sy;
      continue;
    }
    const k = arity[lower];
    if (i + k > tokens.length) return undefined;
    const a = tokens.slice(i, i + k).map(Number);
    if (a.some((v) => !Number.isFinite(v))) return undefined;
    i += k;
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
        const rx = Math.abs(a[0]), ry = Math.abs(a[1]);
        const r = Math.max(rx, ry);
        out.push(Math.min(x, ex) - r, Math.min(y, ey) - r, Math.max(x, ex) + r, Math.max(y, ey) + r);
        x = ex;
        y = ey;
        break;
      }
      default:
        for (let j = 0; j < k; j += 2) out.push(ox + a[j], oy + a[j + 1]);
        x = ox + a[k - 2];
        y = oy + a[k - 1];
    }
    if (lower === "m") {
      sx = x;
      sy = y;
      // Further pairs after a moveto are linetos.
      cmd = rel ? "l" : "L";
    }
  }
  return out;
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
    const body = src.slice(open + 1, j - 1);
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
