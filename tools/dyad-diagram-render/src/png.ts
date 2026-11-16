/**
 * SVG to PNG, without a browser: resvg 0.50 (Apache-2.0 OR MIT), through the
 * `resvg-napi` binding (Apache-2.0 OR MIT), which ships a native addon per
 * platform and a WASI build for everywhere else.
 *
 * Only the bundled fonts are loaded, never the system's, so a PNG is the
 * same on every machine. Every generic family (`sans-serif`, `serif`, ...)
 * maps to Inter, and so does any family the bundle does not have.
 */

import { fontFiles } from "./fonts.ts";

export interface RasterOptions {
  /** Multiply the SVG's own size by this (default 1). */
  scale?: number;
  /** Background colour; transparent where the SVG draws nothing by default. */
  background?: string;
}

type Binding = typeof import("resvg-napi");
type Helpers = typeof import("resvg-napi/helpers");

let loaded: Promise<{ binding: Binding; helpers: Helpers; db: InstanceType<Binding["fontdb"]["Database"]> }> | undefined;

async function load() {
  loaded ??= (async () => {
    const binding = (await import("resvg-napi")) as Binding;
    const helpers = (await import("resvg-napi/helpers")) as Helpers;
    const db = new binding.fontdb.Database();
    for (const f of fontFiles()) db.loadFontFile(f);
    db.setSansSerifFamily("Inter");
    db.setSerifFamily("Inter");
    db.setMonospaceFamily("Inter");
    db.setCursiveFamily("Inter");
    db.setFantasyFamily("Inter");
    return { binding, helpers, db };
  })();
  return loaded;
}

/**
 * Point every `font-family` at Inter, keeping the weight and style. resvg
 * resolves families against the bundled fonts only, and a family it cannot
 * find would otherwise draw nothing.
 */
export function aliasFontFamilies(svg: string): string {
  return svg
    .replace(/font-family\s*=\s*("[^"]*"|'[^']*')/g, 'font-family="Inter"')
    .replace(/font-family\s*:\s*[^;"'}<]*/g, "font-family:Inter");
}

/**
 * Rasterise an SVG document.
 *
 * @returns PNG bytes
 */
export async function svgToPng(svg: string, options: RasterOptions = {}): Promise<Uint8Array> {
  const { helpers, db } = await load();
  const parsed = helpers.parse(aliasFontFamilies(svg), { fonts: db, fontFamily: "Inter" } as Parameters<Helpers["parse"]>[1]);
  return helpers.renderPng(parsed.tree, {
    scale: options.scale ?? 1,
    ...(options.background ? { background: options.background } : {}),
  } as Parameters<Helpers["renderPng"]>[1]);
}
