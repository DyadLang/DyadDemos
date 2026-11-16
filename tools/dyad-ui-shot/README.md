# dyad-ui-shot

Screenshots of Dyad component diagrams as Dyad Studio draws them, made
headlessly. `dyad render` writes an SVG with its own drawing code, and it
looks nothing like the diagram view in Studio. This tool runs Studio's own
diagram view instead and saves a PNG.

```sh
tools/dyad-ui-shot/setup.sh
tools/dyad-ui-shot/dyad-ui-shot.mjs HL20Demo HL20Demo.PitchControl pitch.png
```

## Setup

Requirements: Linux x64, Node ≥ 22, `curl`, `unzip`, `python3`, and the Dyad
3.5 Julia (`julia +dyad-3.5.0`, the `dyad-3.5.0` juliaup channel).

`setup.sh` downloads everything into `<clone root>/.cache/dyad-ui-shot/`
(change it with `DYAD_UI_SHOT_CACHE`) and adds that folder to
`.git/info/exclude`. It checks every download against `versions.env`:

| what | version | checked against |
|---|---|---|
| Dyad Studio (.vsix, Open VSX) | 3.5.1 | Open VSX's published sha256 |
| chrome-headless-shell (Chrome for Testing) | 157.0.8103.50 | sha256 pinned on first download (CfT publishes none) |
| puppeteer-core, vscode-jsonrpc | 25.17.0, 8.2.1 | `package-lock.json` (`npm ci`) |
| Dyad CLI, with `--dyad-cli` | 3.5.0 | the release's `SHA256SUMS.txt` (uses `gh`) |
| openvscode-server, with `--studio` | 1.109.5 | sha256 pinned on first download |
| Studio's extension dependencies, with `--studio` | see `versions.env` | Open VSX's published sha256 |

The standalone setup takes about 400 MB; `--all` takes about 850 MB. Archives
are deleted once unpacked. Child processes get a `TMPDIR` inside the cache.

## Usage

```
dyad-ui-shot <library-dir> <Lib.Component> <out.png> [options]
dyad-ui-shot --batch <list-file> [options]
```

Components are named `Library.Component`, or `Library.module.Component` for
components in sub-folders of `dyad/`, e.g. `HL20Demo.shared.HL20Aero`.

A batch list has one shot per line: `<library-dir> <Lib.Component> <out.png>
[<render.png>]`. Relative paths are relative to the list file. Shots of the same
library share one language server. Each shot takes about 3 s after a start-up
of about 5 s per library.

| option | |
|---|---|
| `--width N`, `--height N` | viewport in CSS px (default 1600×1000) |
| `--fit content` | default: zoom so the whole drawn diagram fills the viewport, crop the PNG to it |
| `--fit studio` | press Studio's own "Fit to view" (it fits the 1000×1000 diagram box, so anything placed outside it is cut off) and save the whole viewport |
| `--scale N` | device pixel ratio (default 2) |
| `--guides` | keep the canvas axes and the diagram-box outline Studio draws behind every diagram (hidden by default; Studio draws no other grid) |
| `--toolbar` | keep Studio's floating toolbar (hidden by default) |
| `--layer icon` | the icon layer instead of the diagram |
| `--render-png P` | also rasterise `dyad render`'s SVG to P with the same Chrome, for comparison (`setup.sh --dyad-cli`) |
| `--julia CMD` | Julia for the language server (default `$JULIA_EXECUTABLE`, else `julia +dyad-3.5.0`) |
| `--mode studio` | full Dyad Studio, see below |
| `--no-instantiate` | do not instantiate a library that has no `Manifest.toml` |
| `--allow-remote-assets H1,H2` | let diagrams load http(s) icons from these hosts, see below |
| `--timeout S` | deadline for each step, in seconds (default 120): instantiating, starting the language server, each request to it, rendering and capturing each diagram, `dyad render`; in studio mode also starting openvscode-server and loading the workbench (one step), activating Studio, opening each diagram |

The exit status is non-zero if any shot failed; a summary of the failed shots
is printed at the end. In a batch, a library that fails (it cannot be
instantiated, its language server does not start in time) fails its own shots
and the run goes on with the next library. Page errors and error-level diagram
problems are printed as warnings.

Every process the tool starts (Julia, the language server, Chrome,
openvscode-server) runs in its own process group, and the whole group is
killed when the step times out, when the tool exits, and on Ctrl-C (SIGINT),
SIGTERM or SIGHUP.

## The two modes

### standalone (default)

Studio's diagram view is a web component bundle, `out/dyad-ui.js` in the
.vsix. Inside VS Code the extension puts it in a webview with
`<dyad-vscode-ui entity="…">` and answers its messages with data from Studio's
language server, `out/server/server.js`. This mode does the same thing without
VS Code:

- **Language server.** `lib/lsp.mjs` starts the bundled `server.js` with
  `node … --stdio`, with the library folder as the workspace, and talks LSP to
  it. The server resolves the library's Dyad dependencies the way it does in
  Studio, by running its `list-dyad-dependencies.jl` with Julia against the
  library's `Manifest.toml`. If the manifest is missing, the tool first runs
  `Pkg.instantiate()` in offline mode. The server's MCP endpoint (an HTTP
  server on all interfaces whose tools write files) is disabled: the server
  gets an invalid MCP port, and `lib/server-guard.cjs`, preloaded into the
  server process, refuses every `listen()`, every outgoing TCP connection and
  every `fetch()` other than `data:` URLs. The server only talks LSP over
  stdio. `test/cli.test.mjs` checks this with `ss -ltnp` while a shot runs.
- **Page.** `lib/webview.mjs` loads the HTML that Studio generates for its
  entity editor into chrome-headless-shell, with the same bundle, Inter font,
  CSP and `<dyad-theme theme="light">`. VS Code's default webview styles are
  added too. The files come from the unpacked .vsix through request
  interception, and the page fetches nothing from the network. The only
  listening socket in this mode is Chrome's DevTools endpoint, which puppeteer
  opens on 127.0.0.1.
- **Messages.** A shim installed before the bundle loads provides
  `acquireVsCodeApi()`. Messages from the webview go to Node, where the
  read-only part of Studio's `handleWebviewMessage` is reimplemented:
  `request-entity` → `dyad/ast-subscribe`, `tree-request` → `dyad/tree`,
  `fetch-icon` → `dyad/fetch-icon`, `list-parameter-types`. The replies go
  back as `window` message events, as they would in VS Code. Edit messages are
  ignored, so nothing is ever written to the library. Subscriptions are
  tracked per page as Studio does: switching layers unsubscribes the old
  layer, and closing a page unsubscribes everything it still holds.
- **Icons.** Only local icons reach the language server: entity icons
  (`urn:definition:…`), `dyad://` assets of the loaded libraries, and `data:`
  URLs. Any other URL gets Dyad's default icon and a warning. With
  `--allow-remote-assets host1,host2`, http(s) icons on those hosts (exact
  host, or `host:port`) are fetched by the tool itself, never by the server:
  at most 2 MiB, 10 s, `image/svg+xml` only, and redirects are followed only
  to listed hosts.
- **Capture.** `lib/shoot.mjs` waits until the layout has elements and no
  message is in flight, then until web fonts (`document.fonts.ready`) and
  images have loaded. It then fits the view and waits for three identical
  consecutive frames with nothing pending. Every request to the page,
  including each animation frame and screenshot, is cut off at the capture's
  deadline. If the view does not settle within `--timeout`, the shot fails
  and no PNG is written.

No VS Code, no Studio extension host and no JuliaHub login are involved. The
pixels come from the same bundle and CSS as Studio 3.5.1's diagram view.

### studio (optional): full Dyad Studio

`--mode studio` runs openvscode-server 1.109.5 with Dyad Studio 3.5.1, its
extension dependencies, and `driver-extension/`. openvscode-server listens on
127.0.0.1 with a connection token generated for each run (passed in a 0600
file). The driver is a small local extension that listens on 127.0.0.1 and
lets the script check its status, activate Studio and run
`dyad-studio.entity.openEditor`; it has no other routes, and it answers only
requests carrying a second random per-run token. Chrome loads the workbench, the script opens
the diagram, finds Studio's webview iframe and captures it with the same fit
and settle logic. Each run gets a fresh server data dir under the cache, which
is kept, with its logs, if a shot fails.

**This mode needs a valid JuliaHub login on the runner.** Studio's activation
waits for `juliahub-vscode-auth` to authenticate. The auth extension reads
`<first JULIA_DEPOT_PATH entry>/servers/<pkg server>/auth.toml`, and without a
valid login it starts an interactive device-code flow and waits. Studio also
needs its `dyad-3.5.0` juliaup channel to work, because it sets
`julia.executablePath` to `julia +dyad-3.5.0` itself. This tool does not
provide, fake or refresh a login. Without one, the run fails after `--timeout`
with a message saying so. Install with `setup.sh --studio`.

Note that Studio's activation rewrites the library's `.vscode/settings.json`.

## Known limits

- **Only tested end to end in standalone mode.** On the runner where it was
  built, studio mode got as far as the Studio extension activating (workspace
  trust, extension install, the driver channel all work). It then stopped at
  the two blockers above: no JuliaHub login, and the juliaup launcher could not
  run inside that runner's sandbox.
- **Light theme only.** Studio's webview hardcodes `<dyad-theme theme="light">`.
  The VS Code CSS variables are those of the default Light Modern theme at
  13 px. If you change the UI font size in Studio, its diagrams will differ.
- **Linux x64 only.** The pinned Chrome and Dyad CLI downloads are linux64.
- **Library folders need `Project.toml` and `dyad/`.** Dyad dependencies must
  resolve from the Manifest. The dyad-3.5.0 Julia ships the Dyad standard
  libraries, so instantiating offline usually works. Other private
  dependencies have to be instantiated beforehand (e.g.
  `JULIA_PKG_USE_CLI_GIT=true` with `gh auth git-credential`).
- **Files written next to the library.** The language server writes
  `.dyadcache` (gitignored in this repo), and instantiation writes
  `Manifest.toml`.
- **`--fit content` can zoom out further than Studio's mouse-wheel minimum
  (25 %).** The canvas draws any zoom; very large diagrams get small text, so
  raise `--scale` or the viewport.
- **Updating Studio.** The page HTML mirrors Studio 3.5.1's `gtt()` in
  `out/extension.js`, and the message handling mirrors its `handleWebviewMessage`.
  Check both against the new `extension.js` when you change
  `DYAD_STUDIO_VERSION`.
- **juliaup in sandboxes.** `julia +dyad-3.5.0` goes through the juliaup
  launcher, which needs to read `~/.juliaup/juliaupself.json`. Where it
  cannot (some sandboxed runners), pass the channel's binary directly, e.g.
  `--julia ~/.julia/juliaup/julia-1.13.2+dyad-3x5x0.x64.linux.musl/bin/julia`.
- **Pinned checksums.** The Chrome and openvscode-server checksums were
  recorded on first download, since neither project publishes checksums.

## Tests

```sh
tools/dyad-ui-shot/setup.sh          # add --studio for the studio-mode test
cd tools/dyad-ui-shot && npm test
```

The tests use `test/fixtures/TinyLib` and a fake Julia
(`test/fixtures/fake-julia.sh`), so they need no Julia installation and no
network. Tests that need the downloads skip themselves when `setup.sh` has not
been run.

## Licensing

Dyad Studio's .vsix is distributed under JuliaHub's EULA. This tool downloads
your own copy of Dyad Studio's assets and runs them locally. Nothing
proprietary is committed to this repository or redistributed by it: the files
stay in the git-excluded cache, together with the copyright notices and
license files that ship in the .vsix. Your use of them is subject to the
JuliaHub EULA.
