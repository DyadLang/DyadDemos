/**
 * Dyad Studio's diagram look, as measured from Studio 3.5.1 screenshots (see
 * ARCHITECTURE.md, "Visual language"). Lengths are in diagram units unless
 * said otherwise; Studio scales everything with the zoom.
 */
export interface DiagramStyle {
  /** Canvas colour, or null for a transparent canvas. */
  background: string | null;
  /** Label font family, as the SVG names it. The bundled font is Inter. */
  fontFamily: string;
  /** Label size. Studio draws every label this size, whatever the size of the component. */
  labelFontSize: number;
  /** Label colour. Studio ignores the label metadata's `fill` and uses this. */
  labelColor: string;
  /**
   * How far below its anchor a boundary port's name is drawn. Studio draws a
   * port's name lower than the `(500, 1100)` its connector type puts it at.
   */
  portLabelOffset: number;
  /** Wire width. */
  wireWidth: number;
  /** Radius wires are rounded with at bends. */
  wireCornerRadius: number;
  /** Wire colour when the connector type gives none. */
  wireColor: string;
  /** Junction dot radius. */
  junctionRadius: number;
}

export const STUDIO_STYLE: DiagramStyle = {
  background: "#ffffff",
  fontFamily: "Inter",
  labelFontSize: 15,
  labelColor: "#18181b",
  portLabelOffset: 22.5,
  wireWidth: 1.5,
  wireCornerRadius: 4,
  wireColor: "#000000",
  junctionRadius: 2.5,
};
