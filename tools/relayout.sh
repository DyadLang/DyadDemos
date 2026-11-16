#!/bin/bash
# relayout.sh COMPONENT OUTDIR [edit ops...]
#
# Run from a demo's root (the directory with Project.toml and dyad/). Does the
# whole Dyad 3.5 layout loop for one component definition:
#   extract -> edit_problem.py ops -> solve (+ schematic SVG) -> fix multi-way
#   route order -> apply -> verify every connect() got routes (re-apply if not)
#   -> dyad render -> PNG.
# COMPONENT is the name inside the library, module-qualified for definitions in
# dyad/ subdirectories (e.g. Models.TNNModel). Edit ops are edit_problem.py's,
# e.g.  lock-orientation unpin-ports port-edges opt:routingRefinement=1
#
# Env: DYAD (default: dyad, must be >= 3.5.0), CHROME (chrome-headless-shell),
#      JULIA_EXECUTABLE as for any dyad command.
set -euo pipefail
COMP=$1 OUT=$2; shift 2
DYAD=${DYAD:-dyad}
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=$(sed -n 's/^name = "\(.*\)"/\1/p' Project.toml | head -1)
NAME=${COMP##*.}
Q=$COMP; case $COMP in *.*) Q=$LIB.$COMP;; esac
mkdir -p "$OUT"
FILE=$(grep -rlE "^\s*(test |example |partial )*component $NAME\b" dyad | head -1)

$DYAD render "$LIB.$COMP" --dir . > "$OUT/$NAME.before.svg" 2>/dev/null || true
$DYAD layout extract "$Q" --dir . -o "$OUT/$NAME.raw.json" > /dev/null
python3 "$HERE/edit_problem.py" "$OUT/$NAME.raw.json" "$OUT/$NAME.prob.json" "$@"
if ! $DYAD layout solve -i "$OUT/$NAME.prob.json" -o "$OUT/$NAME.sol0.json" --render "$OUT/$NAME.schematic.svg" > /dev/null; then
  echo "solve left illegal routes or unsatisfiable constraints (see above); not applying." >&2
  echo "Try: opt:routingRefinement=1 (or 2), bigger instance boxes, or fewer constraints." >&2
  exit 1
fi
python3 "$HERE/fix_junction_order.py" "$OUT/$NAME.prob.json" "$OUT/$NAME.sol0.json" "$FILE" "$NAME" "$OUT/$NAME.sol.json"
$DYAD layout apply "$Q" --dir . -i "$OUT/$NAME.sol.json" 2>/dev/null
for i in 1 2 3; do
  python3 "$HERE/verify_edges.py" "$FILE" "$NAME" && break
  echo "routes missing after apply #$i; applying the same solution again" >&2
  $DYAD layout apply "$Q" --dir . -i "$OUT/$NAME.sol.json" > /dev/null 2>&1
done
$DYAD render "$LIB.$COMP" --dir . > "$OUT/$NAME.after.svg"
"$HERE/svg2png.sh" "$OUT/$NAME.before.svg" "$OUT/$NAME.before.png" || true
"$HERE/svg2png.sh" "$OUT/$NAME.after.svg" "$OUT/$NAME.after.png"
