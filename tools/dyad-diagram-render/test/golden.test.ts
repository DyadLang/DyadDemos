/**
 * Golden-image regression tests: render committed diagram data to PNG and
 * compare with committed images. Anti-aliasing may differ by a level or two
 * between resvg builds (native or WASI, CPU), so a few pixels may differ;
 * anything visible fails.
 *
 * Refresh the images after an intended change with `npm run golden:update`,
 * and look at them before committing.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { renderPng } from "../src/index.ts";
import { decodePng, diffFraction } from "./png-decode.ts";

const update = process.env.UPDATE_GOLDEN === "1";

for (const name of ["RigidBody6DOF", "DrivelineSystem"]) {
  test(`${name} matches its golden image`, async () => {
    const data = JSON.parse(readFileSync(new URL(`fixtures/${name}.diagram.json`, import.meta.url), "utf8"));
    const { png } = await renderPng(data, { fit: { width: 1600, height: 1000 }, margin: 24 });
    const golden = new URL(`golden/${name}.png`, import.meta.url);
    if (update || !existsSync(golden)) {
      writeFileSync(golden, png);
      if (!update) assert.fail(`wrote missing golden image ${golden.pathname}; check it and commit it`);
      return;
    }
    const got = decodePng(png);
    const want = decodePng(readFileSync(golden));
    assert.deepEqual([got.width, got.height], [want.width, want.height]);
    const frac = diffFraction(got, want);
    assert.ok(frac < 0.002, `${(frac * 100).toFixed(3)}% of pixels differ`);
  });
}
