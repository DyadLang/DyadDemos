/**
 * dyad-diagram-render: draw a Dyad component's diagram as SVG or PNG, the way
 * Dyad Studio's diagram view draws it, without a browser.
 *
 * - {@link render}: diagram data to an SVG string (pure, no I/O).
 * - {@link renderPng}: the same, rasterised with resvg and the bundled fonts.
 *
 * The data comes from the Dyad compiler; until this lives in the Dyad CLI,
 * `./adapter` gets it from the CLI binary.
 */

import type { DiagramData } from "./model.ts";
import { type RenderOptions, type RenderResult, renderDiagram } from "./render.ts";
import { labelFontMetrics } from "./fonts.ts";
import { svgToPng } from "./png.ts";

export * from "./model.ts";
export { render, renderDiagram, type RenderOptions, type RenderResult } from "./render.ts";
export { STUDIO_STYLE, type DiagramStyle } from "./style.ts";
export { autoLayout, needsAutoLayout } from "./autolayout.ts";
export { parseFontMetrics, measureText, type FontMetrics } from "./text.ts";
export { labelFontMetrics, fontFiles } from "./fonts.ts";
export { svgToPng, type RasterOptions } from "./png.ts";

/** Render with the bundled font's metrics. */
export function renderSvg(data: DiagramData, options: RenderOptions = {}): RenderResult {
  return renderDiagram(data, { font: labelFontMetrics(), ...options });
}

/** Render to PNG bytes (and the SVG they were drawn from). */
export async function renderPng(data: DiagramData, options: RenderOptions = {}): Promise<RenderResult & { png: Uint8Array }> {
  const result = renderSvg(data, options);
  const png = await svgToPng(result.svg);
  return { ...result, png };
}
