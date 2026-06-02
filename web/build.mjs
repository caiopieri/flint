import * as esbuild from "esbuild";
import { cpSync, mkdirSync, rmSync } from "node:fs";

const watch = process.argv.includes("--watch");
const outdir = "dist";

rmSync(outdir, { recursive: true, force: true });
mkdirSync(outdir, { recursive: true });
cpSync("src/index.html", `${outdir}/index.html`);

const options = {
  entryPoints: ["src/index.ts"],
  bundle: true,
  format: "esm",
  outfile: `${outdir}/app.js`,
  sourcemap: true,
  // WKWebView on iOS 26 — modern Safari engine.
  target: ["safari18"],
};

if (watch) {
  const ctx = await esbuild.context(options);
  await ctx.watch();
  console.log("[flint-web] watching…");
} else {
  await esbuild.build(options);
  console.log("[flint-web] bundle built → dist/");
}
