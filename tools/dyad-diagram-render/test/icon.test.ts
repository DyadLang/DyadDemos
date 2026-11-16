import { test } from "node:test";
import assert from "node:assert/strict";
import { prepareIcon, scopeCss } from "../src/icon.ts";

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

test("replaces the icon's own size with the box and keeps it from clipping", () => {
  const p = prepareIcon(icon, "s1", { x: -5, y: -5, width: 10, height: 10 })!;
  assert.match(p.markup, /x="-5" y="-5" width="10" height="10"/);
  assert.doesNotMatch(p.markup, /width="210"/);
  assert.match(p.markup, /overflow="visible"/);
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

test("drops at-rules from style sheets", () => {
  assert.equal(scopeCss("@import url(x.css); @media print { .a{} } .a, .b {fill:red}", "z"), ".z .z-a,.z .z-b{fill:red}\n");
});
