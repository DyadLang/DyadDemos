import { test } from "node:test";
import assert from "node:assert/strict";
import { labelFontMetrics } from "../src/fonts.ts";
import { measureText } from "../src/text.ts";

test("reads Inter's metrics", () => {
  const f = labelFontMetrics();
  assert.equal(f.unitsPerEm, 2048);
  assert.ok(f.capHeight > 1400 && f.capHeight < 1600, `capHeight ${f.capHeight}`);
  assert.ok(f.advance("W".codePointAt(0)!) > f.advance("i".codePointAt(0)!));
});

test("measures strings, including characters outside the BMP and missing glyphs", () => {
  const f = labelFontMetrics();
  const w = measureText(f, "J_eng", 15);
  assert.ok(w > 30 && w < 50, `width ${w}`);
  assert.equal(measureText(f, "", 15), 0);
  assert.ok(measureText(f, "α·β", 15) > 0);
  assert.ok(Number.isFinite(measureText(f, "\u{1F600}", 15)));
});
