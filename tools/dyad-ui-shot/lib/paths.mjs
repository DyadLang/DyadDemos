// Where dyad-ui-shot keeps its pinned downloads, and how to load the Node
// dependencies that setup.sh installed there.
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

export const TOOL_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

// KEY=VALUE lines of versions.env, shared with setup.sh.
export const VERSIONS = Object.fromEntries(
  fs
    .readFileSync(path.join(TOOL_DIR, "versions.env"), "utf8")
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => {
      const i = l.indexOf("=");
      return [l.slice(0, i), l.slice(i + 1).replace(/^"(.*)"$/, "$1")];
    }),
);

// Default: <clone root>/.cache/dyad-ui-shot, git-excluded, next to the clone
// rather than in TMPDIR (the downloads are a few hundred MB).
export const CACHE_DIR = path.resolve(
  process.env.DYAD_UI_SHOT_CACHE || path.join(TOOL_DIR, "..", "..", ".cache", "dyad-ui-shot"),
);

export const paths = {
  studio: path.join(CACHE_DIR, `studio-${VERSIONS.DYAD_STUDIO_VERSION}`, "extension"),
  chrome: path.join(
    CACHE_DIR,
    `chrome-${VERSIONS.CHROME_VERSION}`,
    "chrome-headless-shell-linux64",
    "chrome-headless-shell",
  ),
  node: path.join(CACHE_DIR, "node"),
  openvscode: path.join(CACHE_DIR, `openvscode-server-${VERSIONS.OPENVSCODE_VERSION}`),
  dyadCli: path.join(CACHE_DIR, `dyad-cli-${VERSIONS.DYAD_CLI_VERSION}`, "dyad"),
  tmp: path.join(CACHE_DIR, "tmp"),
  depot: path.join(CACHE_DIR, "depot"),
};

export function requireSetup(...keys) {
  for (const k of keys) {
    if (!fs.existsSync(paths[k])) {
      throw new Error(
        `${paths[k]} is missing; run ${path.join(TOOL_DIR, "setup.sh")} first` +
          (k === "openvscode" || k === "dyadCli" ? " (with --studio / --dyad-cli)" : ""),
      );
    }
  }
}

// The Node packages live in the cache, not next to this script, so resolve
// them from there explicitly.
const nodeRequire = createRequire(path.join(paths.node, "package.json"));
export const requireDep = (name) => nodeRequire(name);
export async function importDep(name) {
  return import(pathToFileURL(nodeRequire.resolve(name)).href);
}

// Child processes (Chrome, the language server, Julia) get a TMPDIR inside the
// cache so large scratch files never land in the system TMPDIR.
export function childEnv(extra = {}) {
  fs.mkdirSync(paths.tmp, { recursive: true });
  return { ...process.env, TMPDIR: paths.tmp, XDG_CACHE_HOME: path.join(paths.tmp, "xdg-cache"), ...extra };
}
