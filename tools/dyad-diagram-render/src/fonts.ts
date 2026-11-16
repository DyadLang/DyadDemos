/**
 * The bundled fonts: Inter 4.1 (SIL Open Font License 1.1, see
 * `fonts/OFL.txt`), the font Studio's diagram view uses.
 *
 * Labels are measured with Inter's own metrics and the PNG is drawn with it,
 * so the output is the same on every machine whatever fonts it has. Icons
 * that ask for `sans-serif`, Arial or Helvetica get Inter as well.
 */

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { type FontMetrics, parseFontMetrics } from "./text.ts";

export const FONT_FILES = {
  regular: fileURLToPath(new URL("../fonts/Inter-Regular.ttf", import.meta.url)),
  bold: fileURLToPath(new URL("../fonts/Inter-Bold.ttf", import.meta.url)),
};

let regular: Uint8Array | undefined;
let metrics: FontMetrics | undefined;

export function fontFiles(): string[] {
  return [FONT_FILES.regular, FONT_FILES.bold];
}

export function regularFontBytes(): Uint8Array {
  regular ??= readFileSync(FONT_FILES.regular);
  return regular;
}

/** Metrics of the label font (Inter Regular). */
export function labelFontMetrics(): FontMetrics {
  metrics ??= parseFontMetrics(regularFontBytes());
  return metrics;
}
