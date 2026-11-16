import { test } from "node:test";
import assert from "node:assert/strict";
import { contentMayOverflow, fitViewBox, paintedBounds, parseAspectRatio, pathPoints, prepareIcon, scopeCss } from "../src/icon.ts";
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

// Re-check finding 1: attributes are allowlisted; any that can hold a URL is
// checked or dropped, with a diagnostic.
test("drops ping, src and other URL-bearing attributes, and unknown ones", () => {
  const p = prepareIcon(
    `<svg viewBox="0 0 10 10" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:x="urn:x" xml:base="https://evil.example/">
      <a href="#local" ping="https://evil.example/ping" target="_blank"><rect x="1" y="1" width="5" height="5" rx="1" fill="red" data-name="r" x:label="r"/></a>
      <image src="https://evil.example/s.png" action="https://evil.example/a" formaction="https://evil.example/f" width="2" height="2"/>
      <g background="https://evil.example/b.png" cite="https://evil.example/c" longdesc="https://evil.example/l"/>
      <g poster="https://evil.example/p.png" data="https://evil.example/d" xlink:arcrole="https://evil.example/r"/>
      <use x:href="https://evil.example/u.svg#a" xlink:role="https://evil.example/role"/>
      <set attributeName="ping" to="https://evil.example/set"/>
    </svg>`,
    "s",
  )!;
  assert.doesNotMatch(p.markup, /evil\.example|target=|data-name|x:label/);
  // Geometry, presentation and namespace declarations stay; the fragment link is renamed.
  assert.match(p.markup, /<a href="#local">/);
  assert.match(p.markup, /<rect x="1" y="1" width="5" height="5" rx="1" fill="red"\/>/);
  assert.match(p.markup, /xmlns:xlink="http:\/\/www\.w3\.org\/1999\/xlink"/);
  // One diagnostic for each URL-bearing attribute and the animation; none for target, data-name, x:label.
  const urlDrops = p.diagnostics.filter((d) => /it may hold a URL/.test(d));
  assert.deepEqual(
    urlDrops.map((d) => /dropped ([\w:-]+)=/.exec(d)![1]).sort(),
    ["action", "background", "cite", "data", "formaction", "longdesc", "ping", "poster", "src", "xlink:arcrole", "xlink:role", "xml:base"],
  );
  assert.ok(p.diagnostics.some((d) => /dropped x:href=/.test(d)));
  assert.ok(p.diagnostics.some((d) => /dropped <set> animating ping/.test(d)));
  assert.equal(p.diagnostics.length, urlDrops.length + 2);
});

// Re-check finding 2: malformed path data cannot hang the parser.
test("reads path data as SVG does and stops at the first error", () => {
  // Numbers after a closepath are an error: drawn (and measured) up to it.
  assert.deepEqual(pathPoints("M0 0Z1 1"), [0, 0]);
  assert.deepEqual(pathPoints("M0 0 L 5 5 z 7"), [0, 0, 5, 5]);
  // Implicit commands: pairs after a moveto are linetos, parameters repeat.
  assert.deepEqual(pathPoints("m1 1 2 2l1 0 1 0"), [1, 1, 3, 3, 4, 3, 5, 3]);
  assert.deepEqual(pathPoints("M0,0h1-2v.5.5"), [0, 0, 1, 0, -1, 0, -1, 0.5, -1, 1]);
  // Compact arc flags ("00") are two flags.
  assert.deepEqual(pathPoints("M0 0a1 1 0 00 2 0").slice(0, 4), [0, 0, 2, 0]);
  // Path data must start with a moveto; junk ends it.
  assert.deepEqual(pathPoints("L 5 5"), []);
  assert.deepEqual(pathPoints("M1 1 L2 2 # L 9 9"), [1, 1, 2, 2]);
  assert.deepEqual(pathPoints("M1 1 L2"), [1, 1]);
  assert.deepEqual(pathPoints(""), []);
});

test("an arc's bounds take in the ellipse SVG scales its radii up to", () => {
  // Radii 1 and 100 cannot join ends 10 apart: SVG scales them by 5, so the
  // arc bulges 500 units up or down.
  const pts = pathPoints("M0 0 A 1 100 0 0 1 10 0");
  const ys = pts.filter((_, i) => i % 2 === 1);
  assert.ok(Math.min(...ys) <= -500 && Math.max(...ys) >= 500);
  // A near-full circle between two close points reaches two radii away.
  const near = pathPoints("M0 0 A 10 10 0 1 1 0.001 0").filter((_, i) => i % 2 === 1);
  assert.ok(Math.min(...near) <= -20 && Math.max(...near) >= 20);
});

// Re-check finding 3: strokes count in what an icon paints.
test("an icon's painted bounds include its strokes", () => {
  const painted = (body: string, vb = "0 0 100 100") => {
    const svg = rootElement(parseXml(`<svg viewBox="${vb}">${body}</svg>`))!;
    return paintedBounds(svg, vb.split(" ").map(Number) as [number, number, number, number]);
  };
  // No stroke: the geometry.
  assert.deepEqual(painted(`<rect x="10" y="10" width="80" height="80"/>`), [10, 10, 90, 90]);
  // A straight line has no joins and butt caps: half the width.
  assert.deepEqual(painted(`<path d="M98 10 L98 90" stroke="red" stroke-width="40"/>`), [78, -10, 118, 110]);
  // Corners can take a miter join: up to 4 (the default limit) times half the width.
  assert.deepEqual(painted(`<rect x="10" y="10" width="80" height="80" style="stroke:#000;stroke-width:10"/>`), [-10, -10, 110, 110]);
  // Round joins at the root, and nothing else: no miter.
  assert.deepEqual(painted(`<g stroke-linejoin="round"><polygon points="10,10 90,10 50,90" stroke="#000" stroke-width="10"/></g>`, "0 0 100 100"), [-10, -10, 110, 110]);
  const root = rootElement(parseXml(`<svg viewBox="0 0 100 100" stroke-linejoin="round"><polygon points="10,10 90,10 50,90" stroke="#000" stroke-width="10"/></svg>`))!;
  assert.deepEqual(paintedBounds(root, [0, 0, 100, 100]), [5, 5, 95, 95]);
  // From a style sheet, whatever the selector; units are converted.
  assert.deepEqual(painted(`<style>.a{stroke:#000;stroke-width:3pt}</style><line class="a" x1="10" y1="50" x2="90" y2="50"/>`), [8, 48, 92, 52]);
  // A stroke width that cannot be read, markers and filters: unknown.
  assert.equal(painted(`<line x1="0" y1="0" x2="1" y2="1" stroke="red" stroke-width="2em"/>`), undefined);
  assert.equal(painted(`<line x1="0" y1="0" x2="1" y2="1" marker-end="url(#m)"/>`), undefined);
  assert.equal(painted(`<rect width="1" height="1" style="filter:url(#f)"/>`), undefined);
  assert.equal(painted(`<rect width="1" height="1" stroke="red" vector-effect="non-scaling-stroke"/>`), undefined);
  assert.equal(contentMayOverflow(rootElement(parseXml(`<svg viewBox="0 0 100 100"><path d="M98 10 L98 90" stroke="red" stroke-width="40"/></svg>`))!, [0, 0, 100, 100]), true);
});

// The sweep: an unclosed style-sheet block keeps its last character.
test("an unclosed style-sheet block runs to the end of the sheet", () => {
  assert.equal(scopeCss(".a{fill:red", "z"), ".z .z-a{fill:red}\n");
});
