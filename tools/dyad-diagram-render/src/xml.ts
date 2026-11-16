/**
 * A small, dependency-free XML reader and writer, enough for SVG icons and the
 * SVG that `dyad render` prints.
 *
 * Text and attribute values are kept exactly as written (still escaped), so a
 * document that is parsed and written back is unchanged apart from
 * whitespace inside tags. Comments, processing instructions and doctypes are
 * dropped: nothing an icon needs lives in them.
 */

export interface XmlElement {
  kind: "element";
  name: string;
  /** Attributes in document order; values are raw (still escaped). */
  attrs: Array<[string, string]>;
  children: XmlNode[];
}

export interface XmlText {
  kind: "text";
  /** Raw text, still escaped; CDATA sections are kept with their markers. */
  text: string;
}

export type XmlNode = XmlElement | XmlText;

export class XmlError extends Error {}

const nameChar = /[A-Za-z0-9_:.\-]/;

/**
 * Parse an XML document or fragment.
 *
 * @param source The markup
 * @returns The top-level nodes (a fragment may have several)
 */
export function parseXml(source: string): XmlNode[] {
  let i = 0;
  const n = source.length;
  const root: XmlElement = { kind: "element", name: "#root", attrs: [], children: [] };
  const stack: XmlElement[] = [root];

  const top = () => stack[stack.length - 1];

  while (i < n) {
    const lt = source.indexOf("<", i);
    if (lt === -1) {
      pushText(top(), source.slice(i));
      break;
    }
    if (lt > i) {
      pushText(top(), source.slice(i, lt));
    }
    i = lt;
    if (source.startsWith("<!--", i)) {
      const end = source.indexOf("-->", i + 4);
      if (end === -1) throw new XmlError("unterminated comment");
      i = end + 3;
    } else if (source.startsWith("<![CDATA[", i)) {
      const end = source.indexOf("]]>", i + 9);
      if (end === -1) throw new XmlError("unterminated CDATA section");
      pushText(top(), source.slice(i, end + 3));
      i = end + 3;
    } else if (source.startsWith("<?", i)) {
      const end = source.indexOf("?>", i + 2);
      if (end === -1) throw new XmlError("unterminated processing instruction");
      i = end + 2;
    } else if (source.startsWith("<!", i)) {
      // A doctype, possibly with an internal subset in brackets.
      let depth = 0;
      let j = i + 2;
      for (; j < n; j++) {
        const c = source[j];
        if (c === "[") depth++;
        else if (c === "]") depth--;
        else if (c === ">" && depth <= 0) break;
      }
      i = j + 1;
    } else if (source[i + 1] === "/") {
      const end = source.indexOf(">", i);
      if (end === -1) throw new XmlError("unterminated end tag");
      const name = source.slice(i + 2, end).trim();
      const open = top();
      if (open === root || open.name !== name) {
        throw new XmlError(`unexpected </${name}>`);
      }
      stack.pop();
      i = end + 1;
    } else {
      // Start tag.
      let j = i + 1;
      while (j < n && nameChar.test(source[j])) j++;
      const name = source.slice(i + 1, j);
      if (name === "") throw new XmlError(`bad tag at offset ${i}`);
      const el: XmlElement = { kind: "element", name, attrs: [], children: [] };
      let selfClosing = false;
      for (;;) {
        while (j < n && /\s/.test(source[j])) j++;
        if (j >= n) throw new XmlError(`unterminated <${name}>`);
        if (source[j] === ">") {
          j++;
          break;
        }
        if (source[j] === "/" && source[j + 1] === ">") {
          selfClosing = true;
          j += 2;
          break;
        }
        const a0 = j;
        while (j < n && nameChar.test(source[j])) j++;
        const an = source.slice(a0, j);
        if (an === "") throw new XmlError(`bad attribute in <${name}>`);
        while (j < n && /\s/.test(source[j])) j++;
        if (source[j] !== "=") {
          // HTML-style bare attribute; keep it with an empty value.
          el.attrs.push([an, ""]);
          continue;
        }
        j++;
        while (j < n && /\s/.test(source[j])) j++;
        const q = source[j];
        if (q !== '"' && q !== "'") throw new XmlError(`unquoted attribute ${an}`);
        const close = source.indexOf(q, j + 1);
        if (close === -1) throw new XmlError(`unterminated attribute ${an}`);
        el.attrs.push([an, source.slice(j + 1, close)]);
        j = close + 1;
      }
      top().children.push(el);
      if (!selfClosing) stack.push(el);
      i = j;
    }
  }
  if (stack.length !== 1) {
    throw new XmlError(`unclosed <${top().name}>`);
  }
  return root.children;
}

function pushText(parent: XmlElement, text: string) {
  if (text === "") return;
  const last = parent.children[parent.children.length - 1];
  if (last && last.kind === "text") last.text += text;
  else parent.children.push({ kind: "text", text });
}

/** Write nodes back out as markup. */
export function serializeXml(nodes: XmlNode | XmlNode[]): string {
  const list = Array.isArray(nodes) ? nodes : [nodes];
  let out = "";
  for (const node of list) {
    if (node.kind === "text") {
      out += node.text;
      continue;
    }
    out += `<${node.name}`;
    for (const [k, v] of node.attrs) {
      out += ` ${k}="${v.replaceAll('"', "&quot;")}"`;
    }
    if (node.children.length === 0) {
      out += "/>";
    } else {
      out += ">" + serializeXml(node.children) + `</${node.name}>`;
    }
  }
  return out;
}

/** The first top-level element of a parsed document. */
export function rootElement(nodes: XmlNode[]): XmlElement | undefined {
  return nodes.find((x): x is XmlElement => x.kind === "element");
}

export function getAttr(el: XmlElement, name: string): string | undefined {
  for (const [k, v] of el.attrs) if (k === name) return v;
  return undefined;
}

export function setAttr(el: XmlElement, name: string, value: string): void {
  for (const pair of el.attrs) {
    if (pair[0] === name) {
      pair[1] = value;
      return;
    }
  }
  el.attrs.push([name, value]);
}

export function removeAttr(el: XmlElement, name: string): void {
  el.attrs = el.attrs.filter(([k]) => k !== name);
}

export function elementChildren(el: XmlElement): XmlElement[] {
  return el.children.filter((c): c is XmlElement => c.kind === "element");
}

/** Visit every element below (and including) `el`, depth first. */
export function walk(el: XmlElement, visit: (e: XmlElement, parent: XmlElement | null) => void, parent: XmlElement | null = null): void {
  visit(el, parent);
  for (const c of el.children) {
    if (c.kind === "element") walk(c, visit, el);
  }
}

/** The text content of an element, entities decoded. */
export function textContent(el: XmlElement): string {
  let s = "";
  for (const c of el.children) {
    if (c.kind === "text") s += c.text.startsWith("<![CDATA[") ? c.text.slice(9, -3) : decodeEntities(c.text);
    else s += textContent(c);
  }
  return s;
}

export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);/g, (_, e: string) => {
    switch (e) {
      case "amp":
        return "&";
      case "lt":
        return "<";
      case "gt":
        return ">";
      case "quot":
        return '"';
      case "apos":
        return "'";
    }
    const code = e[1] === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
    // Not a character (out of range, a surrogate, NUL): the replacement character.
    if (!(code > 0 && code <= 0x10ffff) || (code >= 0xd800 && code <= 0xdfff)) return "\ufffd";
    return String.fromCodePoint(code);
  });
}

export function escapeText(s: string): string {
  return s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

export function escapeAttr(s: string): string {
  return escapeText(s).replaceAll('"', "&quot;");
}
