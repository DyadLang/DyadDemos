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

// Run the CLI. `onSpawn(child)` runs right after it starts.
export function runCli(args, { env = {}, onSpawn } = {}) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const child = spawn(process.execPath, [CLI, ...args], {
      env: { ...process.env, ...env },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stderr = "";
    let stdout = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    onSpawn?.(child);
    child.on("exit", (code, signal) => resolve({ code, signal, stdout, stderr, seconds: (Date.now() - t0) / 1000 }));
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
