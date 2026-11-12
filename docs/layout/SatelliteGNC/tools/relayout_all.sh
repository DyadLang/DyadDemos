#!/bin/bash
# relayout_all.sh OUTROOT [BEFOREDIR]
# Re-lay out the four SatelliteGNC test harnesses exactly as committed.
# Run from SatelliteGNC/ with DYAD, TOOLS (scout tools) and CHROME set, after
# set_ports.py / set_boxes.py have given the child components and instances
# their icon port boxes and sizes. BEFOREDIR holds <Name>.svg renders of the
# original diagrams (copied in as the "before" pictures).
set -euo pipefail
ROOT=$1 BEFORE=${2:-}
HERE=$(cd "$(dirname "$0")" && pwd)
COMMON="lock-orientation unpin-ports port-edges"

pin() {   # pin COMPONENT X Y  -> an edit_problem.py add: op (required pin)
  printf 'add:{"id":"pin:%s","kind":{"kind":"pin","componentId":"%s","at":{"x":%s,"y":%s}},"strength":{"tier":"required","weight":1}}' "$1" "$1" "$2" "$3"
}

run() {   # run NAME [env...] -- ops...
  local name=$1; shift
  mkdir -p "$ROOT/$name"
  if [ -n "$BEFORE" ] && [ -f "$BEFORE/$name.svg" ]; then cp "$BEFORE/$name.svg" "$ROOT/$name/$name.before.svg"; fi
  echo "== $name"
  env "$@"
}

# 1. TestSatelliteClosedLoop: controller -> plant, angle/rate feedback over the top
run TestSatelliteClosedLoop \
  REROUTE="--cross 12 --prefer top --box 0,0,52,27" \
  "$HERE/relayout2.sh" TestSatelliteClosedLoop "$ROOT/TestSatelliteClosedLoop" \
  $COMMON grid:26x16 "$(pin ctrl 16 18)" "$(pin sat 34 18)"

# 2. TestAllocatorJets: allocator fanning out to the 8 jets in a 2 x 4 grid
#    (reading order); even jets are reached through the gap between the columns
run TestAllocatorJets \
  REROUTE="--cross 12 --box 0,0,44,50 --via alloc.cmd2->jet2.cmd@29,12 --via alloc.cmd4->jet4.cmd@29,24 --via alloc.cmd6->jet6.cmd@29,36 --via alloc.cmd8->jet8.cmd@29,48" \
  "$HERE/relayout2.sh" TestAllocatorJets "$ROOT/TestAllocatorJets" \
  $COMMON grid:22x25 "$(pin alloc 6 24)" \
  "$(pin jet1 22 6)" "$(pin jet2 34 6)" "$(pin jet3 22 18)" "$(pin jet4 34 18)" \
  "$(pin jet5 22 30)" "$(pin jet6 34 30)" "$(pin jet7 22 42)" "$(pin jet8 34 42)"

# 3. TestFullGNC: trajectories -> controller -> plant -> observer, feedback over the top
run TestFullGNC JUNCTIONS=1 \
  REROUTE="--cross 12 --prefer top --box 1,1,64,31 --last ctrl.tau_x->obs.tau_x,ctrl.tau_y->obs.tau_y,ctrl.tau_z->obs.tau_z" \
  "$HERE/relayout2.sh" TestFullGNC "$ROOT/TestFullGNC" \
  $COMMON grid:32x20 "$(pin traj_phi 4 18)" "$(pin traj_theta 4 23)" "$(pin traj_psi 4 28)" \
  "$(pin ctrl 22 18)" "$(pin sat 40 18)" "$(pin obs 54 18)"

# 4. TestFullGNC6DOF: trajectories -> controller -> allocator -> jets on the
#    bottom row, plant -> observer on the top row, feedback over the top
run TestFullGNC6DOF JUNCTIONS=1 \
  REROUTE="--cross 12 --prefer top --box 1,1,80,72 \
--via alloc.cmd1->jet1.cmd@52,34@52,28 --via alloc.cmd2->jet2.cmd@64,34 --via alloc.cmd4->jet4.cmd@64,46 \
--via alloc.cmd6->jet6.cmd@64,58 --via alloc.cmd8->jet8.cmd@64,70 \
--via ctrl.tau_x->obs.tau_x@33,39@33,29@49,29@49,18 --via ctrl.tau_y->obs.tau_y@34,40@34,30@50,30@50,19 \
--via ctrl.tau_z->obs.tau_z@35,41@35,31@51,31@51,20 \
--first ctrl.tau_x->obs.tau_x,ctrl.tau_y->obs.tau_y,ctrl.tau_z->obs.tau_z" \
  "$HERE/relayout2.sh" TestFullGNC6DOF "$ROOT/TestFullGNC6DOF" \
  $COMMON grid:40x40 "$(pin traj_phi 4 40)" "$(pin traj_theta 4 45)" "$(pin traj_psi 4 50)" \
  "$(pin ctrl 22 40)" "$(pin alloc 41 38)" "$(pin sat 41 20)" "$(pin obs 58 17)" \
  "$(pin jet1 58 28)" "$(pin jet2 70 28)" "$(pin jet3 58 40)" "$(pin jet4 70 40)" \
  "$(pin jet5 58 52)" "$(pin jet6 70 52)" "$(pin jet7 58 64)" "$(pin jet8 70 64)"
