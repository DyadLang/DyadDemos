# Architecture, and how this moves into the Dyad CLI

## The Dyad CLI today (3.5.0)

The facts below come from the `v3.5.0` tag of `JuliaComputing/dyad-lang`
(commit `483d92b`). The release binary `dyad-linux-x64` matches the release's
`SHA256SUMS.txt`, and `dyad --version` reports `3.5.0 (483d92b)`.

**Runtime.** The CLI is TypeScript (`apps/cli`, package
`@juliacomputing/dyad-cli`) on Node APIs. The command line is built with
`clipanion`. The release binary is compiled with `bun build --compile`
(`apps/cli/scripts/build-exe.ts`, Bun 1.3.14). That build already embeds one
native addon per target: DuckDB, through a Bun plugin. The compiler is the
`@juliacomputing/dyad-kernel` package (`pkgs/kernel`), used in-process
through a query/selector workspace (`withWorkspace`, `library.workspace.querySettled`).

**How `dyad render` works.** The call path is:

- `apps/cli/src/commands/render.ts`: the clipanion `RenderCommand` (`render <component> --dir`);
- `apps/cli/src/cli/render.ts`: `render(modelname, {dir})`;
- `apps/cli/src/support/diagram.ts`: the selector `componentDiagram(name)`:
  `queryType`, then `instantiateModel(definition, emptyModifications(), null)`,
  then the kernel's `generateDiagram("", instance)`;
- `pkgs/kernel/src/codegen/icons/diagram.ts`: `generateDiagram` calls
  `diagramLayout(instance, query)` and then the kernel's own string
  renderer (`render.ts`: `renderComponent`, `renderConnection`,
  `renderJunction`, `renderLabel`, `renderDiagram`).

`dyad view diagram` (`apps/cli/src/view/diagram.ts`) goes through the same
`componentDiagram`.

That kernel renderer is why `dyad render` looks poor. It is a different
drawing from Studio's:

- a drop shadow on every component;
- labels at `font-size: 200` icon units in the default serif font, so they
  scale with the component;
- boundary ports drawn at 21 % size in a corner of their box: the port icon's
  own `width="210"` is not removed for top-level connectors;
- no rounded wires;
- icons stretched to non-square boxes;
- every icon's `<style>` applied document-wide;
- in 3.5.0, an unplaced component drawn over the whole diagram box;
- no autolayout.

**The diagram data, in-process.** Everything a drawing needs is one selector
away:

| need | kernel API (`@juliacomputing/dyad-kernel`) |
|---|---|
| the definition | `queryType(library, modulePath, component)`, `getDefinitionEntity(definition)` |
| the whole layout | `diagramLayoutSelector(entity, "diagram")` → `Result<GraphicalLayout>` (`codegen/icons/layout.ts`); this is what Studio's diagram editor renders from |
| instances | `GraphicalLayout.components: Record<name, ComponentGraphic>`: `transform` (placement `x1 x2 y1 y2 rot`), `explicitPlacement`, `iconUrl`, `labels`, `connectors`, `dimensions` (arrays) |
| connector placements | `ComponentGraphic.connectors: Record<name, ConnectorGraphic>` (placement in icon coordinates, `iconUrl`, `count`/`show` for fanned-out arrays); boundary ports in `GraphicalLayout.connectors` |
| routes | `GraphicalLayout.connections[]`: `routes[].path` (way points), `junctions[].location`, `pathAttrs` (from the connector type's `path` metadata), `connectors` (the ends), `renderStyle`, `analysisPoint` |
| labels, and parameters on icons | `ComponentGraphic.labels: LabelGraphic[]` (`text` already substituted, `$(instance)`, `$(k)` and so on, `location`, `rot`, `attrs`); free labels in `GraphicalLayout.labels` |
| icon markup | `getIcon(iconUrl, query)` (`codegen/icons/icon.ts`): resolves `dyad://`, `urn:definition:` and data URLs through the workspace's `fetch` |
| placement maths | `iconPointOnDiagram`, `transformAttr` (`codegen/icons/transform.ts`) |
| autolayout (Studio's) | `hasNoPositionalInformation(layout)`, `autolayout(layout)` in `@juliacomputing/dyad-autolayout` (`pkgs/autolayout`, ELK) |

## Design

```
                       ┌─────────────── moves into the CLI ───────────────┐
 dyad CLI binary ──► adapter/ ──► DiagramData ──► render() ──► SVG ──► png.ts ──► PNG
 (render + extract)   (stop-gap)   (model.ts)     (pure)               (resvg)
```

- **`DiagramData`** (`model.ts`) is the kernel's `GraphicalLayout` cut down
  to what drawing needs, as plain JSON, with each `iconUrl` replaced by the
  icon's markup. The renderer therefore never queries anything.
- **`render(data, options) -> string`** (`render.ts`) is pure. Labels are
  measured with metrics read from the bundled font's own tables (`text.ts`),
  so output size and layout do not depend on the machine.
- **Icons** are inlined, each copy scoped (`icon.ts`): classes and ids get a
  per-copy prefix, every style-sheet selector is limited to the copy.
  Icons are untrusted: scripts, `foreignObject` and other embedding elements,
  `on*` handlers and link animations are removed. Attributes are
  allowlisted per element (core, presentation, the element's own geometry);
  attributes that may hold a URL but are not links (`ping`, `src`,
  `action`, `formaction`, `background`, `cite`, `longdesc`, `poster`,
  `data`, `xml:base`, ...) are dropped with a diagnostic, other unknown
  ones (editor metadata) silently. Every link (any `*href`) and every
  `url(...)` must be a fragment of the icon (`#id`) or, on an `<image>`, a `data:` image of a
  raster type or of SVG (which is sanitised the same way, recursively).
  External `url()`, `@import` and other at-rules, and CSS escapes, are
  dropped. Attribute values are decoded before they are checked or renamed,
  so `url(&quot;#g&quot;)` is handled like `url(#g)`. Each removal is a
  diagnostic.
- **Escaping.** Everything from the data reaches the SVG escaped: text and
  attributes through `escapeText`/`escapeAttr`, numbers through `fmt`, a
  component's name as a `data-name` attribute (never a comment). `--data`
  input is type-checked first (`validateDiagramData`).
- **Diagnostics.** `renderDiagram` returns `diagnostics`: what was in the data
  but is not drawn. The command line prints them as warnings, with the
  adapter's (including `dyad`'s own standard error).
- **PNG** (`png.ts`) uses resvg through `resvg-napi`, with only the bundled
  Inter loaded; every family maps to it. A PNG is therefore the same
  everywhere.
- **Autolayout** (`autolayout.ts`) runs when nothing is placed, the kernel's
  `hasNoPositionalInformation` rule.

### Visual language (Studio 3.5.1, measured from screenshots)

The reference images come from `tools/dyad-ui-shot` (PR #53), used only as an
image generator. Nothing was taken from Studio's code. Besides the demo
libraries, a small reference library (`RenderRef`: rotated and mirrored
`Gain`s, icons with `preserveAspectRatio` `none`/`xMinYMin meet`/`xMaxYMid
slice` and content outside the viewBox, an analysis point, a `markers`
connection, array connectors with and without `show`, a boundary array port
(`ArrayBlock`), an icon with a 400-unit stroke past its viewBox in a
non-square box (`StrokeRef`)) was shot to settle the rows below; its
components are kept as `test/fixtures/RenderRef.*`.

| element | Studio | here |
|---|---|---|
| canvas | white, no grid (the axes and diagram-box outline are editor guides, off in screenshots) | `background: #ffffff` |
| component icon | the library's icon, fitted into the placement box following the icon's own `preserveAspectRatio` (by default aspect kept: a 1000 × 800 box shows a square icon; `none` stretches; `slice` covers), and cut to the box (content outside it is not drawn); no shadow, no frame of Studio's own (the light-blue frames are the BlockComponents icons) | the icon's `preserveAspectRatio`, `overflow="hidden"`; the bounds are the fitted viewBox together with what the content paints, strokes included (a 400-wide stroke past the viewBox's edge shows up to the box edge in Studio, `RenderRef.StrokeRef`), cut to the box; the whole box when the content cannot be measured (text, `<use>`, transforms, markers, filters) |
| connectors on a component | the connector type's icon at the kernel's stretched placement: RealInput a filled navy triangle, RealOutput a white triangle outlined in navy, rotational flanges grey `#aaa` circles, heat ports red squares | the same icons, same positions |
| stacking | bodies, then wires, then connectors (an output's white fill hides the wire end), then labels | same |
| boundary ports | the port's icon at full placement size, name below | same; name 22.5 units below the `(500, 1100)` anchor, which matches Studio within a pixel |
| boundary array ports | fanned out on the diagram by the same rule as a connector on an icon (`RenderRef.ArrayBlock`'s `u`, count 3, show 5, at y 450..550: three copies at y 250, 450, 650), the name under the first copy only | same |
| wires | connector type's `stroke` (`rgb(0,0,127)` signals, `#aaa` rotational), about 1.5 diagram units wide (scales with zoom), small rounded bends; overlapping runs of one net do not darken | 1.5 units, radius 4, one `<path>` per net, shared runs removed |
| junctions | small dot in the wire colour | r = 2.5 |
| labels | Inter, `#18181b`, about 16 diagram units whatever the component's size, centred on the label metadata's anchor (`$(instance)` at (500, 1100), so below; parameter labels where their metadata puts them, usually above). The anchor turns and mirrors with the component; the text turns with it but is never upside down: at 90° it reads top to bottom, at 270° bottom to top, at 180° upright; mirroring moves labels but does not mirror the text (checked against `RenderRef.RotMirror`, below) | same |
| analysis points | a crosshair in the wire's colour at the middle of the wire: white disc r 12 with a 2-unit ring, a dot r ≈ 3.75, four ticks from 9.5 to 15 units out; the name above, 20 units high, in the wire's colour, baseline 22.25 units above the wire | same |
| `renderStyle: "markers"` | drawn exactly like `standard` in 3.5.1 | same |
| array connectors | drawn once, unless the placement has a `show` and the array is no longer: then one copy per element along the edge (the kernel's fan-out) | same (`geometry.ts` `fanOut`) |
| clock partitions (`isClocked`) | not checked: no clocked library could be instantiated offline for a reference | not drawn; reported as a diagnostic |
| unplaced components (some placement elsewhere) | 100 × 100 at the diagram centre, straight wires | same |
| nothing placed | laid out automatically (ELK): a left-to-right chain, supports and grounds hanging below | a layered layout tuned to the same spacing |

## Moving it into the Dyad CLI

### Where it goes

1. **Copy `src/` (without `adapter/`) to `apps/cli/src/support/diagram-render/`.**
   Change the relative imports from `./x.ts` to `./x.js`, as the CLI's other
   modules use them (or turn on `rewriteRelativeImportExtensions`). The code
   uses only erasable TypeScript, so `tsc` and Bun take it as it is.
   - Convert `test/*.test.ts` from `node:test` to Jest (`describe`/`it`, same
     assertions), next to the module, as the CLI's tests are.
   - The golden images go to `src/support/diagram-render/__golden__/`.
2. **Add `apps/cli/src/support/diagram-data.ts`.** This replaces the adapter,
   as about 60 lines:

   ```ts
   export function componentDiagramData(name: ComponentName): Selector<Result<DiagramData>> {
     return ({ query }) => query(queryType(name.library, [...name.modulePath], name.component))
       // ...Nothing => missing, not a component => not-a-component, as componentDiagram does
       .chain((definition) => query(diagramLayoutSelector(query(getDefinitionEntity(definition)), "diagram")))
       .map((layout) => toDiagramData(layout, (url) => getIcon(url, query)));
   }
   ```

   `toDiagramData` maps each field directly:

   | DiagramData | from `GraphicalLayout` |
   |---|---|
   | `components[]` | `Object.entries(layout.components)`: `name` = key, `placement` = `transform`, `explicitPlacement`, `icon` = `getIcon(iconUrl)` (the base layer; not `generateIconFromComponentGraphics`, which bakes in connectors and labels), `labels` = `labels.map(l => ({text: l.text, x: l.location.x, y: l.location.y, rot: l.rot, attrs: l.attrs}))`, `connectors` from `connectors` likewise |
   | `components[].connectors[]` | `name` = key, `placement` = `transform` (the whole array's, not fanned out), `icon`, and `count`, `show` and `clockInfo` as they are (`ConnectorGraphic.count`/`.show`/`.clockInfo`). The renderer fans an array out itself when `show` is set, so do not expand it while mapping |
   | `ports[]` | `Object.entries(layout.connectors)`, with `explicitPlacement`, `labels`, `count`, `show` and `clockInfo` |
   | `connections[]` | `routes` = `routes.map(r => r.path)` (already ending at the fanned-out element), `junctions` = `junctions.map(j => j.location)`, `pathAttrs`, `ends` from `connectors` (`ComponentConnectorEnd` → `{component, connector}`), `analysisPoint` (`{name}` or null), `isClocked`, `renderStyle` |
   | `labels` | `layout.labels` |

   Every field the kernel gives that the renderer does not draw (today:
   `isClocked`, `clockInfo`) is reported in `RenderResult.diagnostics`, so
   nothing is dropped silently.
3. **Autolayout.** Decide between two options:
   - Use Studio's own: `if (hasNoPositionalInformation(layout)) layout = await autolayout(layout)`
     from `@juliacomputing/dyad-autolayout` before mapping, and pass
     `layout: "never"` to `render`. That gives Studio's exact positions, but
     it adds `elkjs` (EPL-2.0 OR GPL-3.0) to the CLI binary. The CLI's
     NOTICES list no copyleft package today.
   - Keep `autolayout.ts`, which is close to Studio's result and has no
     dependencies.
4. **`dyad render`.** In `apps/cli/src/cli/render.ts`, draw from
   `componentDiagramData` instead of `componentDiagram`. Add options to
   `RenderCommand`:
   - `--format svg|png` (default from `-o`'s extension, else SVG on stdout);
   - `-o/--output`, `--scale`, `--fit WxH`;
   - `--legacy` for the kernel's drawing for one release.

   The exit status and problem reporting stay as they are. The problems
   come from `diagramLayoutSelector`'s `Result`.

   `dyad view diagram` can serve the new SVG the same way.
5. **Fonts.** Embed `fonts/Inter-Regular.ttf` and `fonts/Inter-Bold.ttf`
   with `import inter from "./fonts/Inter-Regular.ttf" with { type: "file" }`
   (Bun embeds the file in the binary) and read them with `Bun.file`. In
   `fonts.ts` that replaces the `new URL(..., import.meta.url)` paths. Add
   Inter's OFL to the NOTICES (`scripts/notices.mjs`).

### Dependencies to add to `apps/cli/package.json`

- `resvg-napi` `0.12.0` (Apache-2.0 OR MIT), exact version, as the CLI pins
  its other dependencies.
- In `build-exe.ts`, give `resvg-napi` the treatment `@duckdb/node-bindings`
  gets: resolve it to a module generated per target that embeds that
  target's `resvg-napi-<target>.node` (Bun can load an embedded `.node`
  directly).
- Or bundle `resvg-napi-wasm32-wasi` (4.4 MB, every target, slower to
  start). It is not tested here.

Further choices:

- If the team would rather not depend on a young single-maintainer binding,
  build resvg (Apache-2.0 OR MIT) to WASM in the repo with a thin
  `wasm-bindgen` wrapper, as dyad-layout's WASM is built and pinned.
  `png.ts` is the only file that would change.
- SVG output alone needs no new dependency.

### What the adapter does that the CLI will not need

| adapter (stop-gap) | in-tree |
|---|---|
| runs `dyad render` and parses its SVG back into placements and icons | `diagramLayoutSelector` + `getIcon` |
| runs `dyad layout extract` for names, pins and connection ends | the `GraphicalLayout` keys, `explicitPlacement`, `connections[].connectors` |
| reads `missing-placement` warnings to know what is unplaced | `explicitPlacement` |
| moves unplaced components from the 3.5.0 SVG's 0..1000 box to the kernel default 450..550 | already the kernel's `DEFAULT_CENTER` |
| re-groups routed wires into nets by shared ends and junctions | `connections[]` |
| gives every port the `$(instance)` label at (500, 1100) | the port's own `labels` (which may differ for non-default connector types) |
| reads analysis points (`name: analysis_point(a, b)`) from the component's `.dyad` source and matches them to a connection by its ends; reports any it cannot match (routed connections have no ends) | `ConnectionGraphics.analysisPoint` |
| cannot know array lengths, `show`, clocks or render styles (neither command prints them); reports wires that end away from their connector (a fanned-out array the CLI draws once) | `count`, `show`, `clockInfo`, `isClocked`, `renderStyle` |
| resolves `--dir`, the `dyad` path and `JULIA_EXECUTABLE` to absolute paths (the commands run inside the library), fails on a non-zero exit status, and passes `dyad`'s standard error on as diagnostics | not needed |

## Known gaps

- Autolayout is not ELK. For DrivelineSystem the order, rows and wiring
  match Studio, but the spacing differs by a few units.
- Clock partitions (`isClocked`, `clockInfo`) are carried in the data but not
  drawn, and reported as a diagnostic: no Studio reference was possible
  (DiscreteComponents 0.6 cannot be instantiated offline here).
- Through the stop-gap adapter, array connector lengths, `show`, clocks and
  render styles are unknown (the 3.5.0 CLI does not print them), so a
  fanned-out array connector is drawn once, with a diagnostic. Analysis
  points on routed connections (with junctions) cannot be matched, also
  with a diagnostic. In-tree, the kernel's data carries all of these.
- Labels with a rotation of their own on a turned component, and text
  turned by angles other than multiples of 90°, follow the same rule (turn
  with the component, never upside down) but were not compared with Studio.
- Icon text is drawn in Inter. Studio's Chrome uses the system's
  `sans-serif` (Noto Sans on the reference machine), so glyph shapes in icon
  text differ slightly.
- dyad-ui-shot's `--fit content` measures icon content Studio cuts off at the
  placement box, so its crops can be a little larger than ours; and it does
  not measure strokes, so a stroke that reaches past an icon's content can
  be cut from its crop (`RenderRef.StrokeRef`'s right-hand copy) though
  Studio draws it.
- Icon strokes are measured conservatively: style sheets are not matched to
  elements, so a sheet's widest `stroke-width` counts for every shape, and
  any corner counts as a miter join at the largest miter limit. Bounds can
  therefore be a little larger than what is painted. Path geometry itself is
  measured exactly for lines and Bézier curves (their extrema, smooth curves
  reflecting the previous control point as SVG does) and conservatively for
  arcs (a box around their ellipse); a property test checks the bounds
  against resvg's raster for random paths and placements.
