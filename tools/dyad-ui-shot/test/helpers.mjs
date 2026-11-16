// Shared by the tests. Tests that need the downloads from setup.sh skip
// themselves when those are missing.
import fs from "node:fs";
import path from "node:path";
import { spawn, execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { paths } from "../lib/paths.mjs";

export const TEST_DIR = path.dirname(fileURLToPath(import.meta.url));
export const TOOL_DIR = path.dirname(TEST_DIR);
export const CLI = path.join(TOOL_DIR, "dyad-ui-shot.mjs");
export const FIXTURES = path.join(TEST_DIR, "fixtures");
export const FAKE_JULIA = path.join(FIXTURES, "fake-julia.sh");

export const haveSetup = ["studio", "chrome", "node"].every((k) => fs.existsSync(paths[k]));
export const needSetup = haveSetup ? {} : { skip: "run setup.sh first" };

export const quietLog = { debug() {}, info() {}, warn() {} };

// Scratch dirs under the cache's tmp/, removed when the test file exits.
const scratch = [];
process.on("exit", () => scratch.forEach((d) => fs.rmSync(d, { recursive: true, force: true })));
export function tmpDir(name) {
  fs.mkdirSync(paths.tmp, { recursive: true });
  const dir = fs.mkdtempSync(path.join(paths.tmp, `test-${name}-`));
  scratch.push(dir);
  return dir;
}

// A copy of the fixture library; `edit(dir)` may change it.
export function fixtureLib(name = "TinyLib", edit) {
  const dir = path.join(tmpDir("lib"), name);
  fs.cpSync(path.join(FIXTURES, "TinyLib"), dir, { recursive: true });
  edit?.(dir);
  return dir;
}

// Every process seen under a CLI this file started, as "pid:starttime" (the
// kernel's start time makes a reused pid not count as ours). If one is still
// running when the test file exits, for instance because a test failed or
// timed out, it is killed; nothing else is touched.
const owned = new Map();

// The start time of a running (not zombie) process, or null.
function startTime(pid) {
  try {
    const stat = fs.readFileSync(`/proc/${pid}/stat`, "utf8");
    const fields = stat.slice(stat.lastIndexOf(")") + 2).split(" ");
    return fields[0] === "Z" ? null : fields[19];
  } catch {
    return null;
  }
}

const stillOwned = () => [...owned].filter(([key, pid]) => `${pid}:${startTime(pid)}` === key);

// Wait up to `ms` for the recorded processes to exit, then reap the rest.
export async function settleAndReap(ms = 1000) {
  for (const t0 = Date.now(); stillOwned().length && Date.now() - t0 < ms; ) {
    await new Promise((r) => setTimeout(r, 50));
  }
  return reapLeftovers();
}

function recordTree(root) {
  for (const pid of [root, ...descendants(root)]) {
    const st = startTime(pid);
    if (st) owned.set(`${pid}:${st}`, pid);
  }
}

// Kill whatever is left of the processes recorded under CLIs started here.
// Returns the pids that were still running.
export function reapLeftovers() {
  const left = [];
  for (const [, pid] of stillOwned()) {
    left.push(pid);
    try {
      process.kill(pid, "SIGKILL");
    } catch {
      // exited meanwhile
    }
  }
  owned.clear();
  return left;
}
process.on("exit", () => {
  const left = reapLeftovers();
  if (left.length) console.error(`test helpers: killed leftover processes ${left.join(" ")}`);
});

// Run the CLI in its own process group. `onSpawn(child)` runs right after it
// starts. Its process tree is sampled while it runs, for reapLeftovers().
export function runCli(args, { env = {}, onSpawn } = {}) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const child = spawn(process.execPath, [CLI, ...args], {
      env: { ...process.env, ...env },
      stdio: ["ignore", "pipe", "pipe"],
      detached: true,
    });
    const sampler = setInterval(() => recordTree(child.pid), 100);
    recordTree(child.pid);
    let stderr = "";
    let stdout = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    onSpawn?.(child);
    child.on("exit", (code, signal) => {
      clearInterval(sampler);
      resolve({ code, signal, stdout, stderr, seconds: (Date.now() - t0) / 1000 });
    });
  });
}

export function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

// pid -> { ppid, cmd } for every process visible in /proc.
export function processTable() {
  const table = new Map();
  for (const d of fs.readdirSync("/proc")) {
    if (!/^\d+$/.test(d)) continue;
    try {
      const stat = fs.readFileSync(`/proc/${d}/stat`, "utf8");
      const rest = stat.slice(stat.lastIndexOf(")") + 2).split(" ");
      const cmd = fs.readFileSync(`/proc/${d}/cmdline`, "utf8").split("\0").join(" ").trim();
      table.set(Number(d), { ppid: Number(rest[1]), cmd });
    } catch {
      // exited meanwhile
    }
  }
  return table;
}

export function descendants(root, table = processTable()) {
  const out = new Set();
  let grew = true;
  while (grew) {
    grew = false;
    for (const [pid, { ppid }] of table) {
      if (!out.has(pid) && (ppid === root || out.has(ppid))) {
        out.add(pid);
        grew = true;
      }
    }
  }
  return out;
}

// Listening TCP sockets, from `ss -ltnpH`: [{ local, pids }].
export function listeningSockets() {
  const text = execFileSync("ss", ["-ltnpH"], { encoding: "utf8" });
  return text
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const cols = line.trim().split(/\s+/);
      return { line, local: cols[3], pids: [...line.matchAll(/pid=(\d+)/g)].map((m) => Number(m[1])) };
    });
}

export const isLoopback = (local) => /^(127\.\d+\.\d+\.\d+|\[::1\]|\[::ffff:127\.\d+\.\d+\.\d+\]):\d+$/.test(local);
