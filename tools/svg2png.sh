#!/bin/sh
# svg2png.sh in.svg out.png [maxpx]
# Rasterise a `dyad render` SVG with headless Chrome, refitting the viewBox to the
# drawn content (dyad render always writes viewBox="0 0 1000 1000" with overflow
# visible, so anything a layout puts outside 0..1000 would otherwise be cropped).
set -e
IN=$1; OUT=$2; MAX=${3:-1100}
CH=${CHROME:?set CHROME to a chrome-headless-shell binary}
HTML=$(mktemp "$TMPDIR/svgwrap.XXXXXX.html")
{
  printf '<!doctype html><html><head><style>html,body{margin:0;background:#fff}svg{display:block}</style></head><body>\n'
  cat "$IN"
  cat <<JS
<script>
// The renderer's transform-origin="center center" is resolved by Chrome against
// the OUTERMOST svg viewport, so no viewBox may change: the diagram stays at
// 1 px per unit in a 1000x1000 viewport, and cropping and scaling are done by
// an HTML wrapper (overflow:hidden + CSS transform) around it.
const s=document.querySelector('svg');
s.setAttribute('width',1000); s.setAttribute('height',1000);
s.style.overflow='visible'; s.style.position='absolute';
const crop=document.createElement('div'), zoom=document.createElement('div');
s.parentNode.insertBefore(zoom,s); zoom.appendChild(crop); crop.appendChild(s);
crop.style.position='relative'; crop.style.overflow='hidden';
const r0=s.getBoundingClientRect();
let x0=1e9,y0=1e9,x1=-1e9,y1=-1e9;
for (const e of s.querySelectorAll('path,rect,circle,ellipse,line,polyline,polygon,text,image,use')) {
  if (e.closest('defs,pattern,clipPath,mask,marker,symbol')) continue;
  if (getComputedStyle(e).visibility==='hidden' || getComputedStyle(e).display==='none') continue;
  const q=e.getBoundingClientRect();
  let l=q.left,t=q.top,rr=q.right,b=q.bottom;
  // Clip to every enclosing nested <svg> viewport that does not overflow.
  for (let a=e.parentElement; a && a!==s; a=a.parentElement) {
    if (a.tagName.toLowerCase()==='svg' && getComputedStyle(a).overflow!=='visible') {
      const v=a.getBoundingClientRect();
      l=Math.max(l,v.left); t=Math.max(t,v.top); rr=Math.min(rr,v.right); b=Math.min(b,v.bottom);
    }
  }
  if (rr<=l && b<=t) continue;
  if (rr<l || b<t) continue;
  x0=Math.min(x0,l); y0=Math.min(y0,t); x1=Math.max(x1,rr); y1=Math.max(y1,b);
}
const p=30;
const x=x0-r0.left-p, y=y0-r0.top-p, w=x1-x0+2*p, h=y1-y0+2*p;
s.style.left=(-x)+'px'; s.style.top=(-y)+'px';
crop.style.width=w+'px'; crop.style.height=h+'px';
const k=$MAX/Math.max(w,h);
zoom.style.transform='scale('+k+')'; zoom.style.transformOrigin='0 0';
document.title=Math.ceil(w*k)+'x'+Math.ceil(h*k)+' vb='+[x,y,w,h].map(Math.round).join(',');
</script></body></html>
JS
} > "$HTML"
# First pass learns the size, second pass screenshots at that size.
SIZE=$("$CH" --headless --no-sandbox --disable-gpu --dump-dom "file://$HTML" 2>/dev/null | grep -o "<title>[0-9]*x[0-9]*" | head -1 | sed "s/<title>//")
W=${SIZE%x*}; H=${SIZE#*x}
"$CH" --headless --no-sandbox --disable-gpu --hide-scrollbars --window-size="$W,$H" --screenshot="$OUT" "file://$HTML" >/dev/null 2>&1
[ -n "$KEEP" ] || rm -f "$HTML"
echo "$OUT ${W}x${H}"
