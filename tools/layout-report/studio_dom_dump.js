// Dump the geometry Dyad Studio's diagram view drew, for studio_geometry.py.
//
// Evaluate this function in the page that runs Studio's diagram view (dyad-ui-shot's page, after
// captureDiagram has settled it), e.g. `JSON.stringify(await page.evaluate(`(${src})()`))` where
// `src` is this file's text, and save the result as <diagram>.dom.json. It walks every element on the
// canvas, through the shadow roots, and records its tag, attributes, text, visibility, client
// rectangle and screen CTM. Nothing on the page is changed.
() => {
  const deepAll = (selector, root = document) => {
    const out = [];
    const walk = (node) => {
      if (node.querySelectorAll) out.push(...node.querySelectorAll(selector));
      for (const el of node.querySelectorAll ? node.querySelectorAll("*") : []) if (el.shadowRoot) walk(el.shadowRoot);
    };
    walk(root);
    return out;
  };
  const canvas = deepAll("dyad-canvas")[0];
  const cr = canvas.getBoundingClientRect();
  const out = { view: { x: canvas.x, y: canvas.y, zoom: canvas.zoom }, canvasRect: [cr.left, cr.top, cr.width, cr.height], nodes: [] };
  const rec = (el, depth, parent) => {
    const r = el.getBoundingClientRect();
    const attrs = {};
    for (const a of el.attributes || []) if (a.value.length < 20000) attrs[a.name] = a.value;
    const txt = [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join("").trim();
    const vis = el.checkVisibility ? el.checkVisibility({ visibilityProperty: true, opacityProperty: true }) : true;
    let ctm = null;
    if (el instanceof SVGGraphicsElement && el.getScreenCTM) {
      const m = el.getScreenCTM();
      if (m) ctm = [m.a, m.b, m.c, m.d, m.e, m.f];
    }
    const id = out.nodes.length;
    out.nodes.push({ id, parent, depth, tag: el.tagName.toLowerCase(), attrs, txt, vis, r: [r.left, r.top, r.width, r.height], ctm });
    if (el.shadowRoot) for (const c of el.shadowRoot.children) rec(c, depth + 1, id);
    for (const c of el.children) rec(c, depth + 1, id);
  };
  for (const c of canvas.children) rec(c, 0, -1);
  return out;
}
