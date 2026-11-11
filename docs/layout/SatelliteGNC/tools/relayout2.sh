#!/bin/bash
# relayout2.sh COMPONENT OUTDIR [edit ops...]
# Same loop as the scout's relayout.sh (extract -> edit_problem.py -> solve ->
# fix_junction_order -> apply -> verify/re-apply -> render), plus one step after
# solve: reroute.py replaces the solver's wire routes (placements are kept).
# Options for reroute.py come from $REROUTE (a single string, word-split).
# $REFDIR (optional): the original dyad/ sources, for drop_empty_relations.py.
# The solver's exit status is reported but not fatal: its routes are replaced.
set -euo pipefail
COMP=$1 OUT=$2; shift 2
DYAD=${DYAD:-dyad}
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLS=${TOOLS:?set TOOLS to the scout tools dir}
LIB=$(sed -n 's/^name = "\(.*\)"/\1/p' Project.toml | head -1)
NAME=${COMP##*.}
Q=$COMP; case $COMP in *.*) Q=$LIB.$COMP;; esac
mkdir -p "$OUT"
FILE=$(grep -rlE "^\s*(test |example |partial )*component $NAME\b" dyad | head -1)

[ -f "$OUT/$NAME.before.svg" ] || $DYAD render "$LIB.$COMP" --dir . > "$OUT/$NAME.before.svg" 2>/dev/null || true
$DYAD layout extract "$Q" --dir . -o "$OUT/$NAME.raw.json" > /dev/null
python3 -I "$TOOLS/edit_problem.py" "$OUT/$NAME.raw.json" "$OUT/$NAME.prob.json" "$@"
if ! $DYAD layout solve -i "$OUT/$NAME.prob.json" -o "$OUT/$NAME.sol0.json" --render "$OUT/$NAME.schematic.svg" > /dev/null; then
  echo "(solver routes rejected above; placements kept, routes replaced by reroute.py)" >&2
fi
python3 -c "import json,sys; s=json.load(open(sys.argv[1])); sys.exit('unsatisfiable: %s' % s['unsatisfiable'] if s.get('unsatisfiable') else 0)" "$OUT/$NAME.sol0.json"
# shellcheck disable=SC2086
python3 -I "$HERE/reroute.py" "$OUT/$NAME.prob.json" "$OUT/$NAME.sol0.json" "$OUT/$NAME.sol1.json" ${REROUTE:-}
python3 -I "$TOOLS/fix_junction_order.py" "$OUT/$NAME.prob.json" "$OUT/$NAME.sol1.json" "$FILE" "$NAME" "$OUT/$NAME.sol.json"
# apply, then insist the file really holds this solution: 3.5.0 apply sometimes
# prints `wrote` but leaves the previous placements/routes (or no routes) behind
ok=0
for i in 1 2 3 4 5; do
  $DYAD layout apply "$Q" --dir . -i "$OUT/$NAME.sol.json" > /dev/null 2>&1 || true
  if python3 -I "$TOOLS/verify_edges.py" "$FILE" "$NAME" > /dev/null &&
     python3 -I "$HERE/verify_applied.py" "$FILE" "$NAME" "$OUT/$NAME.prob.json" "$OUT/$NAME.sol.json" > /dev/null; then
    ok=1; echo "applied (attempt $i)"; break
  fi
  echo "apply #$i did not write this solution; applying again" >&2
done
[ $ok = 1 ] || { echo "apply never wrote the solution" >&2; exit 1; }
if [ -n "${JUNCTIONS:-}" ]; then
  python3 -I "$HERE/add_junctions.py" "$FILE" "$NAME" "$OUT/$NAME.prob.json" "$OUT/$NAME.sol.json"
  $DYAD format -i "$FILE" > /dev/null   # keep the inline style apply writes
fi
[ -z "${REFDIR:-}" ] || python3 -I "$HERE/drop_empty_relations.py" "$REFDIR" "$FILE"
python3 -I "$TOOLS/verify_edges.py" "$FILE" "$NAME"
python3 -I "$HERE/verify_applied.py" "$FILE" "$NAME" "$OUT/$NAME.prob.json" "$OUT/$NAME.sol.json"
$DYAD render "$LIB.$COMP" --dir . > "$OUT/$NAME.after.svg"
"$TOOLS/svg2png.sh" "$OUT/$NAME.before.svg" "$OUT/$NAME.before.png" || true
"$TOOLS/svg2png.sh" "$OUT/$NAME.after.svg" "$OUT/$NAME.after.png"
