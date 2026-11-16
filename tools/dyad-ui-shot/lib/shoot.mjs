// Fitting, settling and capturing a diagram that is open in a page running
// Dyad Studio's diagram view (either mode).

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Page-side helpers, installed once per document. dyad-ui is made of nested
// shadow roots, so plain querySelector does not reach the diagram.
function pageHelpers() {
  if (window.__dyadUiShot) return;
  const deepAll = (selector, root = document) => {
    const out = [];
    const walk = (node) => {
      if (node.querySelectorAll) out.push(...node.querySelectorAll(selector));
      for (const el of node.querySelectorAll ? node.querySelectorAll("*") : []) {
        if (el.shadowRoot) walk(el.shadowRoot);
      }
    };
    walk(root);
    return out;
  };
  window.__dyadUiShot = {
    deepAll,
    deep: (s) => deepAll(s)[0] ?? null,
    // The diagram is drawn once the layout has elements on its canvas.
    state() {
      const layout = deepAll("dyad-graphical-layout")[0];
      const canvas = layout?.canvasElement;
      // Problems are listed in notifications inside a closed dialog; only a
      // notification that is actually on screen (e.g. "Initialization
      // Failed") means the view could not draw the diagram.
      const notification = deepAll("dyad-notification").find((n) => n.getClientRects().length > 0 && n.checkVisibility?.() !== false);
      return {
        hasLayout: !!layout,
        hasGraphicalLayout: !!layout?.graphicalLayout,
        elements: canvas ? canvas.querySelectorAll("*").length : 0,
        notification: notification
          ? `${notification.getAttribute("title") ?? ""} ${notification.getAttribute("message") ?? ""}`.trim()
          : null,
        pendingImages: deepAll("img").filter((i) => !i.complete).length,
      };
    },
    // Resolves once web fonts and every <img> (in any shadow root) have
    // loaded or failed.
    async assetsLoaded() {
      await document.fonts.ready;
      await Promise.all(deepAll("img").map((i) => (i.complete ? null : i.decode().catch(() => {}))));
      return document.fonts.status === "loaded" && deepAll("img").every((i) => i.complete);
    },
    // Same as the toolbar's layer switch.
    setLayer(layer) {
      const view = deepAll("dyad-component-definition-graphical-layout-view")[0];
      if (!view?.viewState?.setLayer) return false;
      view.viewState.setLayer(layer);
      return true;
    },
    layer() {
      const view = deepAll("dyad-component-definition-graphical-layout-view")[0];
      return view?.viewState?.layer$?.getValue?.() ?? null;
    },
    fit() {
      // Same handler as the toolbar's "Fit to view" button.
      const view = deepAll("dyad-component-definition-graphical-layout-view")[0];
      if (view?.fitToView) view.fitToView();
      else deepAll("dyad-canvas")[0]?.dispatchEvent(new Event("js-zoom-to-fit"));
    },
    hideToolbar() {
      for (const el of deepAll("dyad-action-panel")) el.style.visibility = "hidden";
    },
    // The canvas axes and the outline of the 1000x1000 diagram box are
    // editing aids; their colors are CSS variables of dyad-canvas.
    hideGuides() {
      for (const el of deepAll("dyad-canvas")) {
        el.style.setProperty("--canvas-axis-color", "transparent");
        el.style.setProperty("--canvas-border-color", "transparent");
      }
    },
    // Bounding box (viewport px) of everything drawn on the canvas. Canvas
    // children do not bound their drawing (connections are 0x0 hosts whose
    // wires live in shadow-root SVGs, labels overhang components), so this
    // walks the shadow trees and measures drawn geometry and text.
    contentBox() {
      const canvas = deepAll("dyad-canvas")[0];
      if (!canvas) return null;
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      const add = (el) => {
        const r = el.getBoundingClientRect();
        if (r.width <= 0 && r.height <= 0) return;
        x0 = Math.min(x0, r.left); y0 = Math.min(y0, r.top);
        x1 = Math.max(x1, r.right); y1 = Math.max(y1, r.bottom);
      };
      const skip = "defs, marker, clipPath, mask, pattern, symbol, style, script";
      const visit = (root) => {
        for (const el of root.querySelectorAll("*")) {
          if (el.closest(skip)) continue;
          if (el.shadowRoot) visit(el.shadowRoot);
          if (!el.checkVisibility({ visibilityProperty: true })) continue;
          if (el instanceof SVGGeometryElement || el instanceof SVGUseElement || el instanceof SVGTextContentElement || el instanceof SVGImageElement) add(el);
          else if (el instanceof HTMLImageElement) add(el);
          else if ([...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim())) add(el);
        }
      };
      for (const child of canvas.children) {
        if (child.shadowRoot) visit(child.shadowRoot);
        visit(child);
      }
      if (!(x1 > x0 && y1 > y0)) return null;
      return { x: x0, y: y0, width: x1 - x0, height: y1 - y0 };
    },
    view() {
      const c = deepAll("dyad-canvas")[0];
      return c ? { x: c.x, y: c.y, zoom: c.zoom, minZoom: c.minZoom, maxZoom: c.maxZoom } : null;
    },
    setView(v) {
      const c = deepAll("dyad-canvas")[0];
      Object.assign(c, v);
      c.dispatchViewProperties?.();
    },
  };
}

// `frame` is the document running dyad-ui: the page itself in standalone
// mode, a (nested) webview iframe in studio mode.
export async function waitForDiagram(frame, { timeoutMs, isIdle, fatal = () => null }) {
  const until = Date.now() + timeoutMs;
  const ev = (fn) => beforeDeadline(until, "waiting for the diagram", () => frame.evaluate(fn)).catch(() => null);
  let last;
  while (Date.now() < until) {
    if (fatal()) throw new Error(fatal());
    await ev(pageHelpers);
    last = await ev(() => window.__dyadUiShot?.state());
    if (last?.notification) throw new Error(`diagram view reported: ${last.notification}`);
    if (last?.hasGraphicalLayout && last.elements > 0 && isIdle()) return last;
    await sleep(Math.min(200, Math.max(0, until - Date.now())));
  }
  throw new Error(`diagram did not render within ${timeoutMs / 1000}s (state: ${JSON.stringify(last)})`);
}

// Switch the view to the "icon" layer (the diagram layer is the default) and
// wait for it to be drawn.
export async function switchLayer(frame, layer, { timeoutMs, isIdle, fatal }) {
  if (layer === "diagram") return;
  const until = Date.now() + timeoutMs;
  const what = `switching to the ${layer} layer`;
  if (!(await beforeDeadline(until, what, () => frame.evaluate((l) => window.__dyadUiShot.setLayer(l), layer)))) {
    throw new Error(`could not switch to the ${layer} layer`);
  }
  while ((await beforeDeadline(until, what, () => frame.evaluate(() => window.__dyadUiShot.layer()))) !== layer) {
    if (Date.now() > until) throw new Error(`the view did not switch to the ${layer} layer`);
    await sleep(Math.min(200, Math.max(0, until - Date.now())));
  }
  await waitForDiagram(frame, { timeoutMs: Math.max(0, until - Date.now()), isIdle, fatal });
}

// Where `frame` sits in the page's viewport (CSS px).
async function frameRect(page, frame, until) {
  if (frame === page.mainFrame()) return { x: 0, y: 0, ...page.viewport() };
  const b = await beforeDeadline(until, "locating the diagram frame", async () => (await frame.frameElement()).boundingBox());
  return { x: b.x, y: b.y, width: b.width, height: b.height };
}

// Run `fn` with whatever is left of `until` (a Date.now() deadline). Every
// page RPC goes through this: Puppeteer's own protocol timeout is far longer
// than a short --timeout.
export async function beforeDeadline(until, what, fn) {
  const left = until - Date.now();
  if (left <= 0) throw new Error(`${what}: timed out`);
  let timer;
  try {
    return await Promise.race([
      fn(),
      new Promise((_, reject) => (timer = setTimeout(() => reject(new Error(`${what}: timed out`)), left))),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

// Wait until `frames` consecutive screenshots are identical, with fonts and
// images loaded and no message in flight. Throws if that does not happen
// before `until`: a picture of a view that is still changing is not saved.
async function settle(page, frame, { isIdle, until, clip, frames = 3, what = "diagram" }) {
  let prev = null;
  let same = 0;
  let last = null;
  let stalled = null;
  while (Date.now() < until) {
    const loaded = await beforeDeadline(until, "loading fonts and images", () =>
      frame.evaluate(() => window.__dyadUiShot.assetsLoaded()),
    ).catch(() => false);
    let shot;
    try {
      await beforeDeadline(until, "waiting for an animation frame", () =>
        frame.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))),
      );
      shot = Buffer.from(await beforeDeadline(until, "taking a screenshot", () => page.screenshot({ type: "png", clip })));
    } catch (e) {
      if (Date.now() < until) throw e;
      stalled = e.message;
      break;
    }
    same = prev && shot.equals(prev) ? same + 1 : 1;
    prev = shot;
    last = { loaded, idle: isIdle(), identicalFrames: same };
    // A frame that only arrived after the deadline does not count.
    if (Date.now() > until) break;
    if (same >= frames && loaded && last.idle) return shot;
    await sleep(Math.min(300, Math.max(0, until - Date.now())));
  }
  throw new Error(`the ${what} did not settle in time (last check: ${JSON.stringify(last)}${stalled ? `; ${stalled}` : ""})`);
}

// fit: "studio" = Studio's own "Fit to view" (fits the diagram canvas box);
//      the PNG is the whole diagram view.
//      "content" = then zoom/pan so the drawn content fills the view and
//      crop the PNG to it.
// The whole capture must finish within timeoutMs, or it throws.
export async function captureDiagram(
  page,
  { frame = page.mainFrame(), fit, toolbar, guides = false, padding = 24, isIdle, timeoutMs = 30000, log },
) {
  const until = Date.now() + timeoutMs;
  const fr = await frameRect(page, frame, until);
  const whole = { x: fr.x, y: fr.y, width: fr.width, height: fr.height };
  const ev = (fn, arg, what = "capturing the diagram") => beforeDeadline(until, what, () => frame.evaluate(fn, arg));
  await ev(pageHelpers);
  if (!toolbar) await ev(() => window.__dyadUiShot.hideToolbar());
  if (!guides) await ev(() => window.__dyadUiShot.hideGuides());
  // Text must be measured in its final font before anything is fitted.
  await ev(() => window.__dyadUiShot.assetsLoaded(), undefined, "loading fonts and images");
  await ev(() => window.__dyadUiShot.fit());
  await settle(page, frame, { isIdle, until, clip: whole });

  let clip = whole;
  if (fit === "content") {
    const vp = { width: fr.width, height: fr.height };
    for (let pass = 0; pass < 3; pass++) {
      const box = await ev(() => window.__dyadUiShot.contentBox());
      const view = await ev(() => window.__dyadUiShot.view());
      if (!box || !view) break;
      // Scale so the content box (plus padding) fits, then center it.
      const k = Math.min((vp.width - 2 * padding) / box.width, (vp.height - 2 * padding) / box.height);
      // Studio's wheel zoom stops at minZoom (25%); the canvas itself draws
      // any zoom, so large diagrams may go further out.
      const zoom = Math.max(1, Math.min(view.maxZoom ?? 10000, view.zoom * k));
      const kk = zoom / view.zoom;
      const cx = box.x + box.width / 2 - vp.width / 2;
      const cy = box.y + box.height / 2 - vp.height / 2;
      const next = { zoom, x: (view.x - cx) * kk, y: (view.y - cy) * kk };
      log.debug(`content fit pass ${pass}: box=${JSON.stringify(box)} view=${JSON.stringify(view)} -> ${JSON.stringify(next)}`);
      if (Math.abs(kk - 1) < 0.01 && Math.abs(cx) < 1 && Math.abs(cy) < 1) break;
      await ev((v) => window.__dyadUiShot.setView(v), next);
      await settle(page, frame, { isIdle, until, clip: whole });
    }
    const box = await ev(() => window.__dyadUiShot.contentBox());
    if (box) {
      const x = Math.max(0, Math.floor(box.x - padding));
      const y = Math.max(0, Math.floor(box.y - padding));
      clip = {
        x: fr.x + x,
        y: fr.y + y,
        width: Math.min(vp.width, Math.ceil(box.x + box.width + padding)) - x,
        height: Math.min(vp.height, Math.ceil(box.y + box.height + padding)) - y,
      };
    }
  }
  const png = await settle(page, frame, { isIdle, until, clip });
  if (Date.now() > until) throw new Error(`capturing the diagram: timed out`);
  return png;
}
