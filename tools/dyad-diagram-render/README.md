# dyad-diagram-render

Draws a Dyad component's diagram as SVG or PNG so that it looks like the
diagram view in Dyad Studio. It needs no browser, no Chrome, no Studio code
and no language server. It is written in TypeScript, like the Dyad CLI, and is
laid out so it can move into the CLI as a better `dyad render`; see
[ARCHITECTURE.md](ARCHITECTURE.md).

```sh
cd tools/dyad-diagram-render && npm ci
node bin/dyad-diagram-render.ts HL20Demo.PitchControl -d ../../HL20Demo -o pitch.png --scale 2
```

## Usage

```
dyad-diagram-render <Library.Component> [-d DIR] [-o OUT] [options]
dyad-diagram-render --data DIAGRAM.json [-o OUT] [options]
```

Components are named as `dyad render` names them: `Library.Component`, or
`Library.module.Component` for components in sub-folders of `dyad/`. An `OUT`
ending in `.png` gets a PNG; any other name, or no `-o` at all (stdout), gets
SVG.

| option | |
|---|---|
| `-d, --dir DIR` | the Dyad library (default `.`) |
| `-o, --output OUT` | where to write (default: SVG on stdout) |
| `--scale N` | output pixels per diagram unit (default 1) |
| `--fit WxH` | fit the drawing into W × H pixels instead, keeping its aspect ratio (like dyad-ui-shot's `--fit content`; e.g. `--fit 3200x2000`) |
| `--margin N` | margin around the drawing, in pixels (default 48); with `--fit`, W and H must be larger than twice the margin |
| `--no-layout` | never lay out a diagram with no placements, draw it as placed |
| `--dyad PATH` | the `dyad` executable (default `$DYAD`, else `dyad`) |
| `--julia PATH` | `JULIA_EXECUTABLE` for the `dyad` CLI, which needs Julia to find a library's Dyad dependencies |
| `--data FILE` | draw diagram data saved earlier instead of asking `dyad` |
| `--save-data FILE` | also save the diagram data the drawing was made from (JSON) |
| `--time` | print timings to stderr |

The library must be instantiated (have a `Manifest.toml`), as for any `dyad`
command.

### As a library

```ts
import { render, renderPng, labelFontMetrics } from "./src/index.ts";
import { diagramFromDyadCli } from "./src/adapter/dyad-cli.ts";

const data = await diagramFromDyadCli("HL20Demo", "HL20Demo.PitchControl");
const svg = render(data, { font: labelFontMetrics(), scale: 2 }); // pure, no I/O
const { png } = await renderPng(data, { fit: { width: 3200, height: 2000 } });
```

- `render(data, options) -> string`: diagram data to an SVG document. Pure:
  it reads only its arguments.
- `renderPng(data, options)`: the same drawing, rasterised with resvg and the
  bundled fonts.
- `DiagramData` (`src/model.ts`) is the input: the kernel's `GraphicalLayout`
  with every icon resolved to SVG markup.

## What it draws

It draws what Studio draws, measured from Studio 3.5.1 screenshots (the
details are in ARCHITECTURE.md):

- each component's icon, fitted into its placement box as its own
  `preserveAspectRatio` says (by default aspect kept and centred; `none`
  stretches), cut to the box, then flipped and rotated as the placement says;
- each connector's own icon at the connector's placement. Causal and acausal
  glyphs (the navy triangles, the grey flange circles, the red squares) come
  from the connector types' icons, as in Studio, so they are not hard-coded;
- boundary ports at full size, with their name below;
- wires in their connector type's colour, 1.5 units wide, with rounded
  bends, drawn over component bodies and under connectors, plus junction
  dots;
- labels in Inter, 16 diagram units high whatever the component's size,
  colour `#18181b`. Instance names go below and parameter labels above, where
  the label metadata puts them; they turn and mirror with their component
  but are never upside down;
- analysis points: a crosshair in the wire's colour mid-wire, with the name
  above;
- array connectors with a `show` in their placement, fanned out one copy per
  element;
- a white canvas with no grid.

Whatever is in the data but not drawn (clock partitions; icon content
removed because it could run code or load something) is reported: the
command line prints a warning for each, `renderDiagram` returns them as
`diagnostics`. Icons are sanitised (see ARCHITECTURE.md): only `#fragment`
references and `data:` images survive.

A diagram where nothing has a placement is laid out automatically, as Studio
does: a layered left-to-right layout (`src/autolayout.ts`). A diagram with any
placement is drawn as placed, and its unplaced components go in the kernel's
default box at the centre. Studio does the same.

## Layout

```
src/            the renderer, which moves into the Dyad CLI
  model.ts      DiagramData: the input
  render.ts     render(): DiagramData -> SVG
  icon.ts       scoping icon SVGs so many can share one document
  geometry.ts   placement maps (the kernel's iconPointOnDiagram)
  autolayout.ts layout for diagrams with no placements
  text.ts       font metrics read straight from the TTF
  fonts.ts      the bundled fonts
  png.ts        SVG -> PNG with resvg
  style.ts      Studio's look, as numbers
  xml.ts        a small XML parser/writer
  adapter/      stop-gap: DiagramData from the dyad CLI binary (deleted in-tree)
bin/            the command-line wrapper
fonts/          Inter 4.1, Regular and Bold, with its licence
scripts/        compare.ts: batch renders for comparison with Studio screenshots
test/           unit tests, golden-image tests and their fixtures
```

### The adapter

Until the renderer moves into the CLI, `src/adapter/` gets the diagram from
the Dyad 3.5 CLI without a language server. It runs two commands:

- `dyad render`, whose SVG is the kernel's layout with every icon already
  fetched and every `$(…)` substituted. The adapter reads placements, icons,
  wires, junctions and labels back out of it.
- `dyad layout extract`, which names the components, connectors and ports in
  the same order. It also says which ports are pinned and which connectors
  each connection joins.

Relative paths (`-d`, `--dyad`, `--julia`) are resolved before the commands
run inside the library. A non-zero exit status from either command is an
error, with the command's standard error; its warnings are passed on.
Analysis points are read from the component's `.dyad` source, as neither
command prints them; array connector lengths and clocks are not available
from the CLI (see ARCHITECTURE.md).

It corrects one thing the 3.5.0 SVG gets wrong. A component without a diagram
placement is drawn over the whole diagram box, while the kernel's default
(and Studio) is a 100 × 100 box at the centre.

## Tests

```sh
npm test            # unit tests and golden images (node:test)
npm run typecheck   # tsc
npm run golden:update   # after an intended change to the look; check the images
```

The tests need no `dyad`, Julia or network. The fixtures in `test/fixtures/`
were recorded from the Dyad 3.5.0 CLI:

- the `*.render.svg`, `*.render.log` and `*.problem.json` files are `dyad
  render` and `dyad layout extract` output;
- the `*.diagram.json` files are adapter output;
- `RenderRef/` is a small library made to compare details with Studio
  (rotated and mirrored labels, `preserveAspectRatio`, analysis points,
  `markers` connections, array connectors). Instantiate it offline
  (`JULIA_PKG_OFFLINE=true julia --project=. -e 'using Pkg; Pkg.instantiate()'`)
  to shoot it with dyad-ui-shot or render it with the adapter.

The adapter tests run a stand-in for `dyad` (a shell script) to check how
the commands are run and how failures are reported.

The golden test renders `RigidBody6DOF` (placed, with routes) and
`DrivelineSystem` (laid out automatically) to PNG. It fails if more than 0.2 %
of pixels differ, which allows for anti-aliasing differences between resvg
builds.

## Comparing with Studio

`scripts/compare.ts` renders a batch of diagrams at the pixel size of
reference screenshots (from `tools/dyad-ui-shot`, PR #53):

```sh
node scripts/compare.ts list.txt --dyad /path/to/dyad --julia /path/to/julia
# list.txt lines: <library-dir> <Lib.Component> <out.png> [<studio.png>]
```

## Requirements

- Node ≥ 22.18 (runs the TypeScript directly) or Bun.
- To get data from a library: the Dyad CLI (3.5.0 tested) and the Dyad Julia
  (`JULIA_EXECUTABLE`).

## Dependencies and licences

Only permissive licences:

| package | version | licence | why |
|---|---|---|---|
| [resvg-napi](https://github.com/p8nut/resvg-napi) | 0.12.0 | Apache-2.0 OR MIT | SVG → PNG: Node bindings for [resvg](https://github.com/linebender/resvg) 0.50 (Apache-2.0 OR MIT). It has a native addon per platform and a WASI build elsewhere. Its bundled Rust crates are all Apache-2.0 / MIT / Zlib / Unicode-3.0 (see its `THIRD-PARTY-NOTICES.md`). |
| resvg-napi-linux-x64-gnu (one per platform) | 0.12.0 | Apache-2.0 OR MIT | the native addon |
| @emnapi/core, @emnapi/runtime, @emnapi/wasi-threads | 2.0.0-beta.3, 2.2.0 | MIT | resvg-napi's WASI loader |
| @napi-rs/wasm-runtime, @tybys/wasm-util | 1.2.7, 0.10.5 | MIT | resvg-napi's WASI loader |
| tslib | 2.9.1 | 0BSD | helper for the above |
| Inter (fonts/) | 4.1 | SIL OFL 1.1 | the label font, bundled |
| typescript, @types/node (dev) | 5.9.3, 24.10.1 | Apache-2.0, MIT | type checking only |

The renderer itself (`src/`, excluding `png.ts`) has no dependencies.

Not used, on purpose:

- `@resvg/resvg-js` / `@resvg/resvg-wasm` and `svg2png-wasm` are MPL-2.0.
- `elkjs`, which Studio's autolayout uses, is EPL-2.0 OR GPL-3.0.
- Nothing from Dyad Studio is used or copied. The look was measured from
  screenshots.

Installed footprint on linux-x64: about 9 MB of `node_modules` (5.2 MB of
that is the native addon), plus 0.8 MB of fonts.
