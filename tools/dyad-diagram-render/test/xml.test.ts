import { test } from "node:test";
import assert from "node:assert/strict";
import { decodeEntities, getAttr, parseXml, rootElement, serializeXml, textContent, XmlError } from "../src/xml.ts";

test("parses and writes back elements, attributes and text", () => {
  const src = `<svg viewBox="0 0 10 10"><g class="a b"><path d="M0 0L1 1"/></g><text x="1">a &amp; b</text></svg>`;
  const nodes = parseXml(src);
  assert.equal(serializeXml(nodes), src);
  const svg = rootElement(nodes)!;
  assert.equal(getAttr(svg, "viewBox"), "0 0 10 10");
});

test("drops comments, doctypes and processing instructions; keeps CDATA", () => {
  const src = `<?xml version="1.0"?><!DOCTYPE svg [<!ENTITY x "y">]><!-- c --><svg><style><![CDATA[.a{fill:red}]]></style></svg>`;
  const svg = rootElement(parseXml(src))!;
  assert.equal(serializeXml(svg), `<svg><style><![CDATA[.a{fill:red}]]></style></svg>`);
  assert.equal(textContent(svg), ".a{fill:red}");
});

test("accepts single-quoted attributes and decodes entities in text", () => {
  const svg = rootElement(parseXml(`<svg a='1 "2"'><t>&lt;&#65;&#x42;&gt;</t></svg>`))!;
  assert.equal(getAttr(svg, "a"), '1 "2"');
  assert.equal(textContent(svg), "<AB>");
  assert.equal(decodeEntities("&quot;&apos;"), `"'`);
});

test("rejects malformed markup", () => {
  assert.throws(() => parseXml("<a><b></a>"), XmlError);
  assert.throws(() => parseXml("<a>"), XmlError);
  assert.throws(() => parseXml("<a b=c/>"), XmlError);
});
