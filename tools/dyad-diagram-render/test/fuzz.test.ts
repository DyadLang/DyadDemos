import { test } from "node:test";
import assert from "node:assert/strict";
import { Worker } from "node:worker_threads";

/**
 * Random and truncated path data, transforms, style attributes and style
 * sheets, fed through the parsers and the renderer in a worker thread with
 * a time limit: none may hang (re-check finding 2 and the loop sweep).
 * `FUZZ_SEED` and `FUZZ_ITERATIONS` replay or lengthen a run.
 */
test("no path, transform or style input makes the parsers hang", { timeout: 60_000 }, async () => {
  const seed = Number(process.env.FUZZ_SEED ?? 20261116);
  const iterations = Number(process.env.FUZZ_ITERATIONS ?? 10000);
  const limitMs = Number(process.env.FUZZ_LIMIT_MS ?? 30_000);
  const worker = new Worker(new URL("./fuzz-worker.ts", import.meta.url), { workerData: { seed, iterations } });
  let last: unknown;
  const outcome = await new Promise<"done" | "timeout" | Error>((resolve) => {
    const timer = setTimeout(() => resolve("timeout"), limitMs);
    worker.on("message", (m: { done?: boolean }) => {
      if (m.done) {
        clearTimeout(timer);
        resolve("done");
      } else last = m;
    });
    worker.on("error", (e) => {
      clearTimeout(timer);
      resolve(e);
    });
  });
  await worker.terminate();
  if (outcome instanceof Error) throw new Error(`fuzz input ${JSON.stringify(last)} (seed ${seed}) threw: ${outcome.message}`);
  assert.equal(outcome, "done", `fuzzing did not finish in ${limitMs} ms (seed ${seed}); stuck on ${JSON.stringify(last)}`);
});
