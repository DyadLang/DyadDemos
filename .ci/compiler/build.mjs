import { build } from "esbuild";
import path from "node:path";
const root = path.resolve(".source");
const alias = Object.fromEntries(["common", "ast", "parser", "kernel", "units"].map(p => [`@juliacomputing/dyad-${p}`, `${root}/pkgs/${p}/src/index.ts`]));
alias["@juliacomputing/dyad-kernel/node"] = `${root}/pkgs/kernel/src/node.ts`;
await build({entryPoints:["entry.ts"],bundle:true,platform:"node",format:"esm",target:"node22",outfile:"compiler.mjs",alias,nodePaths:[path.resolve("node_modules")],banner:{js:'import { createRequire } from "node:module"; const require = createRequire(import.meta.url);'}});
