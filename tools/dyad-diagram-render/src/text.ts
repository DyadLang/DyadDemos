/**
 * Text measurement from a TrueType/OpenType font's own tables, with no
 * dependencies: `cmap` for characters, `hmtx` for advance widths, `head`,
 * `hhea` and `OS/2` for the vertical metrics. Kerning is ignored, which is
 * within a percent or two for labels.
 */

export interface FontMetrics {
  unitsPerEm: number;
  ascender: number;
  descender: number;
  capHeight: number;
  xHeight: number;
  /** Advance width of a code point, in font units. */
  advance(codePoint: number): number;
}

export function parseFontMetrics(bytes: Uint8Array): FontMetrics {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const numTables = view.getUint16(4);
  const tables = new Map<string, number>();
  for (let i = 0; i < numTables; i++) {
    const rec = 12 + 16 * i;
    const tag = String.fromCharCode(bytes[rec], bytes[rec + 1], bytes[rec + 2], bytes[rec + 3]);
    tables.set(tag, view.getUint32(rec + 8));
  }
  const need = (tag: string) => {
    const off = tables.get(tag);
    if (off === undefined) throw new Error(`font has no ${tag} table`);
    return off;
  };

  const head = need("head");
  const unitsPerEm = view.getUint16(head + 18);
  const hhea = need("hhea");
  const ascender = view.getInt16(hhea + 4);
  const descender = view.getInt16(hhea + 6);
  const numberOfHMetrics = view.getUint16(hhea + 34);
  const hmtx = need("hmtx");
  let capHeight = Math.round(unitsPerEm * 0.7);
  let xHeight = Math.round(unitsPerEm * 0.5);
  const os2 = tables.get("OS/2");
  if (os2 !== undefined && view.getUint16(os2) >= 2) {
    xHeight = view.getInt16(os2 + 86);
    capHeight = view.getInt16(os2 + 88);
  }

  const glyphOf = readCmap(view, need("cmap"));
  const advances = new Map<number, number>();
  const advanceOfGlyph = (g: number) => {
    const idx = Math.min(g, numberOfHMetrics - 1);
    return view.getUint16(hmtx + 4 * idx);
  };

  return {
    unitsPerEm,
    ascender,
    descender,
    capHeight,
    xHeight,
    advance(cp: number) {
      let a = advances.get(cp);
      if (a === undefined) {
        a = advanceOfGlyph(glyphOf(cp));
        advances.set(cp, a);
      }
      return a;
    },
  };
}

function readCmap(view: DataView, cmap: number): (cp: number) => number {
  const n = view.getUint16(cmap + 2);
  let best: { format: number; offset: number } | undefined;
  for (let i = 0; i < n; i++) {
    const rec = cmap + 4 + 8 * i;
    const platform = view.getUint16(rec);
    const encoding = view.getUint16(rec + 2);
    const offset = cmap + view.getUint32(rec + 4);
    const format = view.getUint16(offset);
    const unicode = platform === 0 || (platform === 3 && (encoding === 1 || encoding === 10));
    if (!unicode) continue;
    if (format === 12 && (!best || best.format !== 12)) best = { format, offset };
    else if (format === 4 && !best) best = { format, offset };
  }
  if (!best) return () => 0;
  const { format, offset } = best;
  if (format === 12) {
    const groups = view.getUint32(offset + 12);
    return (cp) => {
      let lo = 0;
      let hi = groups - 1;
      while (lo <= hi) {
        const mid = (lo + hi) >> 1;
        const g = offset + 16 + 12 * mid;
        const start = view.getUint32(g);
        const end = view.getUint32(g + 4);
        if (cp < start) hi = mid - 1;
        else if (cp > end) lo = mid + 1;
        else return view.getUint32(g + 8) + (cp - start);
      }
      return 0;
    };
  }
  const segX2 = view.getUint16(offset + 6);
  const ends = offset + 14;
  const starts = ends + segX2 + 2;
  const deltas = starts + segX2;
  const rangeOffsets = deltas + segX2;
  return (cp) => {
    if (cp > 0xffff) return 0;
    for (let s = 0; s < segX2; s += 2) {
      const end = view.getUint16(ends + s);
      if (cp > end) continue;
      const start = view.getUint16(starts + s);
      if (cp < start) return 0;
      const delta = view.getInt16(deltas + s);
      const ro = view.getUint16(rangeOffsets + s);
      if (ro === 0) return (cp + delta) & 0xffff;
      const glyph = view.getUint16(rangeOffsets + s + ro + 2 * (cp - start));
      return glyph === 0 ? 0 : (glyph + delta) & 0xffff;
    }
    return 0;
  };
}

/** The advance width of a string, in the units of `fontSize`. */
export function measureText(font: FontMetrics, text: string, fontSize: number): number {
  let w = 0;
  for (const ch of text) w += font.advance(ch.codePointAt(0)!);
  return (w * fontSize) / font.unitsPerEm;
}
