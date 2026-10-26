import { runSingleCompilerPass } from "./.source/apps/cli/src/cli/single.ts";
import { document } from "./.source/apps/cli/src/cli/docs.ts";
try {
  const [command, target] = process.argv.slice(2);
  if (command === "--version") console.log("3.5.0-rc2 (a24a224; compiler-only source build)");
  else if (command === "compile") process.exitCode = await runSingleCompilerPass(target ?? ".");
  else if (command === "document") process.exitCode = await document(target, {dir: "."});
  else throw new Error("Supported commands: --version, compile [directory], document [library]");
} catch (error) {
  console.error(error);
  process.exitCode = 1;
}
