#!/bin/bash
# reproduce.sh OUTROOT [BEFOREDIR]
# Re-create the committed SatelliteGNC layout from the pre-relayout sources.
# Run from SatelliteGNC/ with DYAD, TOOLS (scout layout tools) and CHROME set,
# with the edited/new icons in assets/ already in place (they are hand-drawn).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export REFDIR=$1/orig-dyad
mkdir -p "$REFDIR" && cp dyad/*.dyad "$REFDIR"/   # the sources as they were
for f in dyad/*.dyad; do $DYAD format "$f" > /dev/null; done   # tag style for dyadmeta.py
# 1. child components: square icons, a port box for every connector, label size
python3 -I "$HERE/set_ports.py" .
# 2. instances in the four harnesses: the children's canonical square sizes
J="jet1=400 jet2=400 jet3=400 jet4=400 jet5=400 jet6=400 jet7=400 jet8=400"
T="traj_phi=200 traj_theta=200 traj_psi=200"
python3 -I "$HERE/set_boxes.py" dyad/attitude_controller.dyad TestSatelliteClosedLoop sat=400 ctrl=800
python3 -I "$HERE/set_boxes.py" dyad/thruster_allocator.dyad TestAllocatorJets alloc=500 $J
python3 -I "$HERE/set_boxes.py" dyad/full_gnc.dyad TestFullGNC sat=400 $T obs=400 ctrl=800
python3 -I "$HERE/set_boxes.py" dyad/full_gnc_6dof.dyad TestFullGNC6DOF sat=700 $T obs=400 ctrl=800 alloc=500 $J
for f in dyad/*.dyad; do $DYAD format "$f" > /dev/null; done
# 3. place and route the four harnesses
"$HERE/relayout_all.sh" "$@"
python3 -I "$HERE/drop_empty_relations.py" "$REFDIR" dyad/*.dyad
