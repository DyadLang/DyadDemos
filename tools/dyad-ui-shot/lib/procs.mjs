// Child processes and deadlines. Every process this tool starts leads its own
// process group, so it can be killed together with everything it started
// (Julia under the language server, the extension host under
// openvscode-server, Chrome's helpers). All groups still alive are killed on
// exit, and on SIGINT/SIGTERM/SIGHUP.
import { spawn } from "node:child_process";

const groups = new Set();

export function killGroup(pid, signal = "SIGKILL") {
  try {
    process.kill(-pid, signal);
  } catch {
    // already gone
  }
}

// Track a process that leads its own group (spawned with detached: true).
export function own(pid) {
  if (pid) groups.add(pid);
}

export function disown(pid) {
  groups.delete(pid);
}

export function killAll(signal = "SIGKILL") {
  for (const pid of groups) killGroup(pid, signal);
  groups.clear();
}

process.on("exit", () => killAll());

let signalsInstalled = false;
export function installSignalHandlers(log) {
  if (signalsInstalled) return;
  signalsInstalled = true;
  const codes = { SIGINT: 130, SIGTERM: 143, SIGHUP: 129 };
  for (const [sig, code] of Object.entries(codes)) {
    process.on(sig, () => {
      log?.warn(`${sig}: stopping`);
      killAll();
      process.exit(code);
    });
  }
}

// spawn() in a new process group that this module owns.
export function spawnOwned(cmd, args, opts = {}) {
  const proc = spawn(cmd, args, { ...opts, detached: true });
  own(proc.pid);
  proc.exited = new Promise((resolve) => {
    proc.once("exit", (code, signal) => resolve({ code, signal }));
    proc.once("error", (error) => resolve({ code: null, signal: null, error }));
  });
  return proc;
}

// SIGTERM the process group, SIGKILL it after `graceMs`. Resolves once the
// group leader has exited; the rest of the group is SIGKILLed in any case.
export async function terminate(proc, graceMs = 3000) {
  if (!proc?.pid) return;
  killGroup(proc.pid, "SIGTERM");
  let timer;
  await Promise.race([proc.exited, new Promise((r) => (timer = setTimeout(r, graceMs)))]);
  clearTimeout(timer);
  killGroup(proc.pid, "SIGKILL");
  await proc.exited;
  disown(proc.pid);
}

// Run a command to completion in its own process group, killing the whole
// group if it is still running after `timeoutMs`.
export async function run(cmd, args, { timeoutMs, what = cmd, maxBuffer = 256 << 20, ...opts }) {
  const proc = spawnOwned(cmd, args, { ...opts, stdio: ["ignore", "pipe", "pipe"] });
  const out = { stdout: [], stderr: [] };
  let size = 0;
  for (const k of ["stdout", "stderr"]) {
    proc[k].on("data", (d) => {
      size += d.length;
      if (size > maxBuffer) killGroup(proc.pid);
      else out[k].push(d);
    });
  }
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    killGroup(proc.pid);
  }, timeoutMs);
  const { code, signal, error } = await proc.exited;
  clearTimeout(timer);
  killGroup(proc.pid);
  disown(proc.pid);
  if (error) throw new Error(`${what}: ${error.message}`);
  if (timedOut) throw new Error(`${what} timed out after ${timeoutMs / 1000}s`);
  if (size > maxBuffer) throw new Error(`${what} wrote more than ${maxBuffer} bytes`);
  return {
    code,
    signal,
    stdout: Buffer.concat(out.stdout).toString("utf8"),
    stderr: Buffer.concat(out.stderr).toString("utf8"),
  };
}

// Reject if `promise` has not settled after `ms`.
export function deadline(promise, ms, what) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`${what} timed out after ${ms / 1000}s`)), ms);
    }),
  ]).finally(() => clearTimeout(timer));
}
