import { test } from "node:test";
import assert from "node:assert/strict";
import { contentMayOverflow, fitViewBox, parseAspectRatio, pathPoints, prepareIcon, scopeCss } from "../src/icon.ts";
import { parseXml, rootElement } from "../src/xml.ts";

const icon = `<svg xmlns="http://www.w3.org/2000/svg" width="210" height="210" viewBox="0 0 210 210">
<defs><style>.b{stroke:#000} #g1 {fill: url(#grad)} path{stroke-width:2}</style>
<linearGradient id="grad"/></defs>
<script>alert(1)</script>
<path class="b" fill="url(#grad)" onclick="x()" d="M0 0"/><use href="#grad"/></svg>`;

test("scopes classes, ids and selectors to one copy of an icon", () => {
  const p = prepareIcon(icon, "s1", { x: -5, y: -5, width: 10, height: 10 })!;
  assert.deepEqual(p.viewBox, [0, 0, 210, 210]);
  assert.match(p.markup, /^<g class="s1"><svg /);
  assert.match(p.markup, /class="s1-b"/);
  assert.match(p.markup, /id="s1-grad"/);
  assert.match(p.markup, /fill="url\(#s1-grad\)"/);
  assert.match(p.markup, /href="#s1-grad"/);
  assert.match(p.markup, /\.s1 \.s1-b\{stroke:#000\}/);
  // `#g1` names no element of this icon, so it is left alone.
  assert.match(p.markup, /\.s1 #g1\{fill: url\(#s1-grad\)\}/);
  assert.match(p.markup, /\.s1 path\{stroke-width:2\}/);
});

test("replaces the icon's own size with the box and cuts it to the box, as Studio does", () => {
  const p = prepareIcon(icon, "s1", { x: -5, y: -5, width: 10, height: 10 })!;
  assert.match(p.markup, /x="-5" y="-5" width="10" height="10"/);
  assert.doesNotMatch(p.markup, /width="210"/);
  assert.match(p.markup, /overflow="hidden"/);
  assert.doesNotMatch(p.markup, /overflow="visible"/);
});

test("removes scripts and event handlers", () => {
  const p = prepareIcon(icon, "s1")!;
  assert.doesNotMatch(p.markup, /script|alert|onclick/);
});

test("an icon without a viewBox takes its size as one", () => {
  const p = prepareIcon(`<svg width="40" height="20"><rect/></svg>`, "q")!;
  assert.deepEqual(p.viewBox, [0, 0, 40, 20]);
});

test("returns undefined for markup that is not SVG", () => {
  assert.equal(prepareIcon("<html/>", "q"), undefined);
  assert.equal(prepareIcon("<svg>", "q"), undefined);
});

test("drops at-rules from style sheets, and says so", () => {
  const ctx = { diagnostics: [] as string[] };
  assert.equal(scopeCss("@import url(x.css); @media print { .a{} } .a, .b {fill:red}", "z", undefined, ctx), ".z .z-a,.z .z-b{fill:red}\n");
  assert.equal(ctx.diagnostics.length, 2);
  assert.match(ctx.diagnostics[0], /@import/);
  assert.match(ctx.diagnostics[1], /@media/);
});

// Review finding 2: only fragment refs and data: images may stay; every drop is reported.
test("drops javascript:, remote and other non-fragment links, with a diagnostic each", () => {
  const p = prepareIcon(
    `<svg viewBox="0 0 10 10" xmlns:xlink="http://www.w3.org/1999/xlink">
      <a href="javascript:alert(1)"><rect width="5" height="5"/></a>
      <a xlink:href=" JaVaScRiPt:alert(2)"><rect width="5" height="5"/></a>
      <a href="java&#x73;cript:alert(3)"><rect width="5" height="5"/></a>
      <image href="https://evil.example/x.png" width="5" height="5"/>
      <image xlink:href="//evil.example/y.png" width="5" height="5"/>
      <use href="other.svg#a"/>
      <use href="#a"/><g id="a"/>
    </svg>`,
    "s",
  )!;
  assert.doesNotMatch(p.markup, /javascript|evil\.example|other\.svg|&#x73;/i);
  assert.match(p.markup, /<use href="#s-a"\/>/);
  assert.equal(p.diagnostics.filter((d) => /dropped (xlink:)?href/.test(d)).length, 6);
});

test("keeps data: images of safe raster types and drops other data: URLs", () => {
  const png = "data:image/png;base64,iVBORw0KGgo=";
  const p = prepareIcon(
    `<svg viewBox="0 0 10 10"><image href="${png}"/><image href="data:text/html;base64,PHNjcmlwdD4="/><a href="${png}"><rect/></a></svg>`,
    "s",
  )!;
  assert.match(p.markup, /<image href="data:image\/png;base64,iVBORw0KGgo="\/>/);
  assert.doesNotMatch(p.markup, /text\/html/);
  // A data: image is only allowed where an image goes, not as a link.
  assert.doesNotMatch(p.markup, /<a href=/);
  assert.equal(p.diagnostics.length, 2);
});

test("sanitises SVG data: images recursively", () => {
  const inner = `<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><script>alert(2)</script><image href="https://evil.example/z.png"/><rect fill="red" width="1" height="1"/></svg>`;
  const url = `data:image/svg+xml;base64,${Buffer.from(inner).toString("base64")}`;
  const p = prepareIcon(`<svg viewBox="0 0 10 10"><image href="${url}"/></svg>`, "s")!;
  const out = /href="data:image\/svg\+xml;base64,([^"]+)"/.exec(p.markup)!;
  const decoded = Buffer.from(out[1], "base64").toString("utf8");
  assert.doesNotMatch(decoded, /script|onload|alert|evil/);
  assert.match(decoded, /<rect fill="red"/);
  assert.equal(p.diagnostics.filter((d) => d.startsWith("in an SVG data: image")).length, 3);
});

test("strips scripts, handlers, foreignObject and link animations", () => {
  const p = prepareIcon(
    `<svg viewBox="0 0 10 10" onload="a()"><foreignObject><div xmlns="http://www.w3.org/1999/xhtml">x</div></foreignObject>
      <a><set attributeName="href" to="javascript:alert(1)"/><animate attributeName="xlink:href" values="javascript:alert(1)"/><rect onClick="b()"/></a>
      <svg:script xmlns:svg="http://www.w3.org/2000/svg">c()</svg:script></svg>`,
    "s",
  )!;
  assert.doesNotMatch(p.markup, /foreignObject|onload|onClick|javascript|script|<set|<animate/i);
  assert.equal(p.diagnostics.length, 6);
});

test("drops external url() and @import from style sheets and style attributes", () => {
  const p = prepareIcon(
    `<svg viewBox="0 0 10 10"><style>@import "https://evil.example/a.css";
      .a { fill: url(https://evil.example/p.svg#g); stroke: red }
      .b { fill: url( "#g" ); background: url(data:image/png;base64,AAAA) }
      .c { fill: u\\72l(https://evil.example/x) }</style>
      <linearGradient id="g"/>
      <rect class="a" style="fill:url('http://evil.example/q');stroke:blue" filter="url(https://evil.example/f.svg#x)"/></svg>`,
    "s",
  )!;
  assert.doesNotMatch(p.markup, /evil\.example|@import|\\72/);
  assert.match(p.markup, /\.s \.s-a\{stroke: red\}/);
  assert.match(p.markup, /\.s \.s-b\{fill: url\(#s-g\);background: url\("data:image\/png;base64,AAAA"\)\}/);
  assert.match(p.markup, /style="stroke:blue"/);
  assert.doesNotMatch(p.markup, /filter=/);
  assert.equal(p.diagnostics.length, 5);
});

test("a style sheet cannot close itself and inject markup", () => {
  const p = prepareIcon(`<svg viewBox="0 0 10 10"><style><![CDATA[ .a { fill: red } ]]> </style></svg>`, "s")!;
  const q = prepareIcon(`<svg viewBox="0 0 10 10"><style>.a{fill:red} /* ]]&gt;&lt;script&gt;alert(1)&lt;/script&gt; */ .b{x:"]]&gt;&lt;/style&gt;&lt;script&gt;alert(2)&lt;/script&gt;"}</style></svg>`, "s")!;
  for (const markup of [p.markup, q.markup]) {
    assert.doesNotMatch(markup, /<script|CDATA/);
    // The output parses, and its only elements are the wrapper, the svg and the style.
    const names: string[] = [];
    const visit = (e: { kind: string; name?: string; children?: unknown[] }) => {
      if (e.kind !== "element") return;
      names.push(e.name!);
      for (const c of (e.children ?? []) as Array<{ kind: string }>) visit(c);
    };
    visit(rootElement(parseXml(markup))!);
    assert.deepEqual(names, ["g", "svg", "style"]);
  }
});

// Review finding 7: references written with entities are renamed too.
test("decodes escaped fragment references before renaming them", () => {
  const p = prepareIcon(
    `<svg viewBox="0 0 10 10"><linearGradient id="grad"/><rect fill="url(&quot;#grad&quot;)" stroke="url(&apos;#grad&apos;)" style="fill:url(&quot;#grad&quot;)"/><use href="&#35;grad"/></svg>`,
    "s1",
  )!;
  assert.match(p.markup, /fill="url\(#s1-grad\)"/);
  assert.match(p.markup, /stroke="url\(#s1-grad\)"/);
  assert.match(p.markup, /style="fill:url\(#s1-grad\)"/);
  assert.match(p.markup, /href="#s1-grad"/);
  assert.equal(p.diagnostics.length, 0);
});

test("reads preserveAspectRatio and fits a viewBox the way SVG does", () => {
  assert.deepEqual(parseAspectRatio(undefined), { align: "xMidYMid", slice: false });
  assert.deepEqual(parseAspectRatio("none"), { align: "none", slice: false });
  assert.deepEqual(parseAspectRatio("defer xMaxYMin slice"), { align: "xMaxYMin", slice: true });
  const box = { x: -100, y: -50, width: 200, height: 100 };
  const vb: [number, number, number, number] = [0, 0, 1000, 1000];
  assert.deepEqual(fitViewBox(vb, { align: "none", slice: false }, box), { sx: 0.2, sy: 0.1, ...box });
  assert.deepEqual(fitViewBox(vb, { align: "xMidYMid", slice: false }, box), { sx: 0.1, sy: 0.1, x: -50, y: -50, width: 100, height: 100 });
  assert.deepEqual(fitViewBox(vb, { align: "xMinYMin", slice: false }, box), { sx: 0.1, sy: 0.1, x: -100, y: -50, width: 100, height: 100 });
  assert.deepEqual(fitViewBox(vb, { align: "xMaxYMid", slice: true }, box), { sx: 0.2, sy: 0.2, x: -100, y: -100, width: 200, height: 200 });
});

test("tells whether an icon may draw outside its viewBox", () => {
  const over = (body: string) => contentMayOverflow(rootElement(parseXml(`<svg viewBox="0 0 100 100">${body}</svg>`))!, [0, 0, 100, 100]);
  assert.equal(over(`<rect x="10" y="10" width="80" height="80"/><circle cx="50" cy="50" r="40"/><path d="M10 10 l 80 0 c 0 10 -10 10 -10 0z"/>`), false);
  assert.equal(over(`<rect x="105" y="40" width="20" height="20"/>`), true);
  assert.equal(over(`<path d="M10 10 h 100"/>`), true);
  assert.equal(over(`<g transform="scale(2)"><rect width="10" height="10"/></g>`), true);
  assert.equal(over(`<text x="50" y="50">t</text>`), true);
  assert.equal(over(`<defs><rect x="500" width="10" height="10"/></defs>`), false);
  assert.deepEqual(pathPoints("M1 2 3 4 h 5 v -1 z"), [1, 2, 3, 4, 8, 4, 8, 3]);
});
