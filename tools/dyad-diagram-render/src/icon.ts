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
 * Scripts, `foreignObject` and event-handler attributes are removed, so an
 * icon cannot run anything when the SVG is opened in a browser.
 */

import {
  type XmlElement,
  type XmlNode,
  getAttr,
  parseXml,
  removeAttr,
  rootElement,
  serializeXml,
  setAttr,
  walk,
} from "./xml.ts";

export interface PreparedIcon {
  /** Markup for the icon: a `<g class=scope>` wrapping its `<svg>` element. */
  markup: string;
  /** The icon's viewBox, `[minX, minY, width, height]`. */
  viewBox: [number, number, number, number];
}

const dropElements = new Set(["script", "foreignObject", "iframe"]);

/**
 * Prepare an icon for inlining.
 *
 * The icon's own size is dropped, as the Dyad kernel's `iconLayer` does, and
 * the `<svg>` is given `box` instead: its own `viewBox` and
 * `preserveAspectRatio` (by default centred, aspect kept) decide how it fills
 * the box. `overflow` is visible, so parts drawn outside the viewBox are kept.
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
  let nodes: XmlNode[];
  try {
    nodes = parseXml(source);
  } catch {
    return undefined;
  }
  const svg = rootElement(nodes);
  if (!svg || localName(svg.name) !== "svg") return undefined;

  const viewBox = parseViewBox(getAttr(svg, "viewBox")) ?? intrinsicViewBox(svg);
  for (const a of ["width", "height", "x", "y"]) removeAttr(svg, a);
  setAttr(svg, "viewBox", viewBox.join(" "));
  setAttr(svg, "x", fmtNum(box.x));
  setAttr(svg, "y", fmtNum(box.y));
  setAttr(svg, "width", fmtNum(box.width));
  setAttr(svg, "height", fmtNum(box.height));
  setAttr(svg, "overflow", "visible");

  // Ids first, so references in style sheets can be renamed with them.
  const ids = new Set<string>();
  walk(svg, (e) => {
    const id = getAttr(e, "id");
    if (id !== undefined) ids.add(id);
  });
  const renameId = (id: string) => (ids.has(id) ? `${scope}-${id}` : id);
  const renameRefs = (value: string) =>
    value
      .replace(/url\(\s*(['"]?)#([^)'"\s]+)\1\s*\)/g, (_m, q: string, id: string) => `url(${q}#${renameId(id)}${q})`);

  walk(svg, (e) => {
    e.children = e.children.filter((c) => c.kind !== "element" || !dropElements.has(localName(c.name)));
    e.attrs = e.attrs.filter(([k]) => !/^on/i.test(k));
    for (const pair of e.attrs) {
      const [k, v] = pair;
      if (k === "id") pair[1] = renameId(v);
      else if (k === "class") pair[1] = v.split(/\s+/).filter(Boolean).map((c) => `${scope}-${c}`).join(" ");
      else if ((k === "href" || k === "xlink:href") && v.startsWith("#")) pair[1] = `#${renameId(v.slice(1))}`;
      else if (v.includes("url(")) pair[1] = renameRefs(v);
    }
    if (localName(e.name) === "style") {
      const css = e.children.map((c) => (c.kind === "text" ? unCdata(c.text) : "")).join("");
      e.children = [{ kind: "text", text: `<![CDATA[${scopeCss(css, scope, renameId)}]]>` }];
    }
  });

  const wrapper: XmlElement = { kind: "element", name: "g", attrs: [["class", scope]], children: [svg] };
  return { markup: serializeXml(wrapper), viewBox };
}

function fmtNum(v: number): string {
  const r = Math.round(v * 1000) / 1000;
  return Object.is(r, -0) ? "0" : String(r);
}

function localName(name: string): string {
  const i = name.indexOf(":");
  return i === -1 ? name : name.slice(i + 1);
}

function unCdata(text: string): string {
  return text.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1");
}

export function parseViewBox(v: string | undefined): [number, number, number, number] | undefined {
  if (v === undefined) return undefined;
  const parts = v.trim().split(/[\s,]+/).map(Number);
  if (parts.length !== 4 || parts.some((p) => !Number.isFinite(p)) || parts[2] <= 0 || parts[3] <= 0) {
    return undefined;
  }
  return parts as [number, number, number, number];
}

function intrinsicViewBox(svg: XmlElement): [number, number, number, number] {
  const w = parseFloat(getAttr(svg, "width") ?? "");
  const h = parseFloat(getAttr(svg, "height") ?? "");
  return [0, 0, Number.isFinite(w) && w > 0 ? w : 1000, Number.isFinite(h) && h > 0 ? h : 1000];
}

/**
 * Limit a style sheet to one icon: every selector is prefixed with the scope
 * class and its class and id names are renamed the way the markup's are.
 * At-rules (`@import`, `@font-face`, `@media`) are dropped.
 */
export function scopeCss(css: string, scope: string, renameId: (id: string) => string = (id) => `${scope}-${id}`): string {
  const src = css.replace(/\/\*[\s\S]*?\*\//g, "");
  let out = "";
  let i = 0;
  while (i < src.length) {
    const open = src.indexOf("{", i);
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
    if (prelude.startsWith("@") || prelude === "") continue;
    const selectors = prelude
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean)
      .map((s) => {
        const renamed = s
          .replace(/\.(-?[_a-zA-Z][\w-]*)/g, (_m, c: string) => `.${scope}-${c}`)
          .replace(/#(-?[_a-zA-Z][\w-]*)/g, (_m, id: string) => `#${renameId(id)}`);
        return `.${scope} ${renamed}`;
      });
    const value = body.replace(/url\(\s*(['"]?)#([^)'"\s]+)\1\s*\)/g, (_m, q: string, id: string) => `url(${q}#${renameId(id)}${q})`);
    out += `${selectors.join(",")}{${value.trim()}}\n`;
  }
  return out;
}
