// End to end, standalone mode, on the fixture library with a fake Julia (no
// real Julia needed): findings 1 (nothing listens), 2 (remote icons are not
// fetched), 4 (deadlines, cleanup, batch failures) and the --guides flag.
import { test, afterEach } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import {
  FAKE_JULIA,
  needSetup,
  tmpDir,
  fixtureLib,
  runCli,
  alive,
  processTable,
  descendants,
  listeningSockets,
  isLoopback,
  settleAndReap,
} from "./helpers.mjs";

// The tool must clean up after itself: any process it left behind fails the
// test that left it (and is killed, so it cannot outlive the test run).
afterEach(async () => {
  const left = await settleAndReap();
  assert.deepEqual(left, [], `the CLI left processes behind: ${left.join(" ")}`);
});

const isPng = (f) => fs.existsSync(f) && fs.readFileSync(f).subarray(1, 4).toString() === "PNG";

test("a shot: PNG written, the language server listens on nothing, remote icons are not fetched", needSetup, async () => {
  const hits = [];
  const icons = http.createServer((req, res) => {
    hits.push(req.url);
    res.writeHead(200, { "content-type": "image/svg+xml" }).end("<svg/>");
  });
  await new Promise((r) => icons.listen(0, "127.0.0.1", r));
  const port = icons.address().port;
  const lib = fixtureLib("TinyLib", (dir) => {
    const f = path.join(dir, "dyad", "tiny.dyad");
    fs.writeFileSync(f, fs.readFileSync(f, "utf8").replace("http://127.0.0.1:9/", `http://127.0.0.1:${port}/`));
  });
  const out = path.join(tmpDir("out"), "chain.png");

  // `ss -ltnp` every 100 ms while the CLI runs, for all of its descendants.
  const seen = { serverPids: new Set(), sockets: [] };
  let timer;
  const r = await runCli([lib, "TinyLib.Chain", out, "--julia", FAKE_JULIA, "--timeout", "60"], {
    onSpawn(child) {
      timer = setInterval(() => {
        const table = processTable();
        const desc = descendants(child.pid, table);
        const server = [...desc].filter((p) => /server\.js --stdio/.test(table.get(p).cmd));
        const serverGroup = new Set(server.flatMap((p) => [p, ...descendants(p, table)]));
        server.forEach((p) => seen.serverPids.add(p));
        for (const s of listeningSockets()) {
          if (s.pids.some((p) => desc.has(p))) {
            seen.sockets.push({ ...s, fromServer: s.pids.some((p) => serverGroup.has(p)) });
          }
        }
      }, 100);
    },
  });
  clearInterval(timer);
  await new Promise((r) => icons.close(r));

  assert.equal(r.code, 0, r.stderr);
  assert.ok(isPng(out));
  assert.ok(seen.serverPids.size > 0, "the probe never saw the language server running");
  assert.deepEqual(seen.sockets.filter((s) => s.fromServer), [], "the language server listened");
  assert.deepEqual(seen.sockets.filter((s) => !isLoopback(s.local)), [], "something listened beyond loopback");
  // Positive control: the probe does see Chrome's loopback DevTools socket.
  assert.ok(seen.sockets.some((s) => isLoopback(s.local)), "the probe saw no socket at all");
  assert.deepEqual(hits, []);
  assert.match(r.stderr, new RegExp(`icon http://127.0.0.1:${port}/remote-icon.svg not loaded`));
});

// A fake Julia that never returns, in both places Julia runs: Pkg.instantiate()
// (library without Manifest.toml) and the language server's dependency
// listing (library with one).
function sleepingSetup() {
  const dir = tmpDir("sleep");
  const pids = path.join(dir, "pids");
  const noManifest = fixtureLib("TinyLib", (d) => fs.rmSync(path.join(d, "Manifest.toml")));
  const withManifest = fixtureLib("TinyLib");
  const batch = path.join(dir, "batch.txt");
  fs.writeFileSync(
    batch,
    `${noManifest} TinyLib.Chain ${dir}/a.png\n${withManifest} TinyLib.Chain ${dir}/b.png\n${withManifest} TinyLib.Box ${dir}/c.png\n`,
  );
  const recorded = () =>
    fs.existsSync(pids) ? fs.readFileSync(pids, "utf8").split(/\s+/).filter(Boolean).map(Number) : [];
  return { dir, pids, batch, recorded, env: { FAKE_JULIA_MODE: "sleep", FAKE_JULIA_PIDS: pids } };
}

test("--timeout 1 with a Julia that hangs: prompt exit, every library reported, no children left", needSetup, async () => {
  const s = sleepingSetup();
  let cliPid;
  const r = await runCli(["--batch", s.batch, "--julia", FAKE_JULIA, "--timeout", "1"], {
    env: s.env,
    onSpawn: (c) => (cliPid = c.pid),
  });
  assert.equal(r.code, 1, r.stderr);
  assert.ok(r.seconds < 20, `took ${r.seconds}s`);
  // Both libraries were tried: the first failing did not stop the batch.
  assert.match(r.stderr, /Pkg\.instantiate\(\) in .* timed out after 1s/);
  assert.match(r.stderr, /language server request dyad\/tree timed out after 1s/);
  assert.match(r.stderr, /3 of 3 shot\(s\) failed:\n.*TinyLib\.Chain.*\n.*TinyLib\.Chain.*\n.*TinyLib\.Box/);
  // Julia ran twice (instantiate, dependency listing); all of it is gone.
  const pids = s.recorded();
  assert.equal(pids.length, 4, `recorded pids: ${pids}`);
  assert.deepEqual(pids.filter(alive), []);
  assert.deepEqual([...descendants(cliPid)], []);
  for (const f of ["a.png", "b.png", "c.png"]) assert.equal(fs.existsSync(path.join(s.dir, f)), false);
});

test("SIGINT while Julia hangs: prompt exit, no children left", needSetup, async () => {
  const s = sleepingSetup();
  let child;
  let tree = [];
  const r = await runCli(["--batch", s.batch, "--julia", FAKE_JULIA, "--timeout", "120"], {
    env: s.env,
    onSpawn(c) {
      child = c;
      const t = setInterval(() => {
        if (s.recorded().length >= 2) {
          clearInterval(t);
          tree = [...descendants(c.pid)];
          c.kill("SIGINT");
        }
      }, 100);
    },
  });
  assert.equal(r.code, 130, r.stderr);
  assert.ok(r.seconds < 30, `took ${r.seconds}s`);
  assert.ok(tree.length >= 3, `expected Chrome and Julia under the CLI, saw ${tree}`);
  await new Promise((res) => setTimeout(res, 200));
  assert.deepEqual(tree.filter(alive), [], `left behind: ${tree.filter(alive)}`);
  assert.deepEqual(s.recorded().filter(alive), []);
  assert.ok(child.exitCode !== null || child.signalCode !== null);
});

test("a broken library fails its own shots; the next library is still shot", needSetup, async () => {
  const dir = tmpDir("batch");
  const broken = fixtureLib("TinyLib", (d) => fs.rmSync(path.join(d, "dyad"), { recursive: true }));
  const good = fixtureLib("TinyLib");
  const batch = path.join(dir, "batch.txt");
  fs.writeFileSync(batch, `${broken} TinyLib.Chain ${dir}/broken.png\n${good} TinyLib.Box ${dir}/good.png\n`);
  const r = await runCli(["--batch", batch, "--julia", FAKE_JULIA, "--timeout", "60"]);
  assert.equal(r.code, 1, r.stderr);
  assert.match(r.stderr, /has no dyad\/ folder/);
  assert.match(r.stderr, /1 of 2 shot\(s\) failed/);
  assert.equal(fs.existsSync(path.join(dir, "broken.png")), false);
  assert.ok(isPng(path.join(dir, "good.png")));
});

test("canvas guides are hidden unless --guides", needSetup, async () => {
  const dir = tmpDir("guides");
  const lib = fixtureLib("TinyLib");
  const batch = path.join(dir, "batch.txt");
  fs.writeFileSync(batch, `${lib} TinyLib.Box ${dir}/plain.png\n`);
  const common = ["--julia", FAKE_JULIA, "--fit", "studio", "--width", "500", "--height", "400", "--scale", "1"];
  const a = await runCli(["--batch", batch, ...common]);
  assert.equal(a.code, 0, a.stderr);
  fs.writeFileSync(batch, `${lib} TinyLib.Box ${dir}/guides.png\n`);
  const b = await runCli(["--batch", batch, ...common, "--guides"]);
  assert.equal(b.code, 0, b.stderr);
  const { importDep } = await import("../lib/paths.mjs");
  const { paths } = await import("../lib/paths.mjs");
  const puppeteer = (await importDep("puppeteer-core")).default;
  const browser = await puppeteer.launch({ executablePath: paths.chrome, headless: "shell", args: ["--no-sandbox"] });
  try {
    // Count pixels in the guides' colour (Shoelace primary-200, a light blue)
    // along the canvas's centre lines.
    const count = async (file) => {
      const page = await browser.newPage();
      const data = fs.readFileSync(file).toString("base64");
      const n = await page.evaluate(async (src) => {
        const img = new Image();
        img.src = src;
        await img.decode();
        const c = new OffscreenCanvas(img.width, img.height);
        const g = c.getContext("2d");
        g.drawImage(img, 0, 0);
        const { data } = g.getImageData(0, 0, img.width, img.height);
        let n = 0;
        for (let i = 0; i < data.length; i += 4) {
          const [r, gg, b] = [data[i], data[i + 1], data[i + 2]];
          if (b > 200 && b - r > 15 && r > 150 && gg > 170) n++;
        }
        return n;
      }, `data:image/png;base64,${data}`);
      await page.close();
      return n;
    };
    const plain = await count(path.join(dir, "plain.png"));
    const guides = await count(path.join(dir, "guides.png"));
    assert.ok(guides > 500, `--guides drew only ${guides} guide pixels`);
    assert.ok(plain < guides / 20, `${plain} guide pixels without --guides, ${guides} with`);
  } finally {
    await browser.close();
  }
});
