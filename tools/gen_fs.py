#!/usr/bin/env python3
"""HL20FullSystem re-layout: closed-loop trunk routing.

Structure (all x/y in diagram units):
- Controller command outputs rise into "north lanes" (y~90-250) that run
  east to right-edge drops and down to mixer input taps.  Lane order and
  drop order are chosen by subset-DP solvers that minimize pairwise
  column-vs-lane crossings.
- Vehicle feedback returns through the "FAB": vehicle pin -> drop column
  (x2020-2110) -> horizontal lane (y1250-1520) -> riser up into the
  controller bottom pins.  Lane depth order, drop x order and riser
  positions are all DP-optimized.
- NZ/QDEG also feed output ports: NZ escapes north on a column at x1190
  and QDEG escapes at x685 (left of every shallower lane start).
- DLEDEG returns on its own lane ending at x1530, then drops to pitch's
  left-edge pin via the x695 corridor.
- DLE taps at x1850: the port leg rises to y430 (above every FAB drop's
  pin level) and runs straight east; the vehicle leg goes straight to
  DWFL.
- ALPHA_DEG is a straight eastbound horizontal at its pin y (above every
  drop's start).  ALT_FT jogs to y440 inside x2005 before the forest.
- The seven surface wires are near-straight after repinning the vehicle
  inputs to the mixer output order (DLE, DRE, DUL, DUR, DLL, DLR, DR ->
  DWFL, DWFR, DBFUL, DBFUR, DBFLL, DBFLR, DRUD).  HL20Mixer's own icon
  is left untouched.
- DLEDEG, the bottom mixer output pin (y690), cannot escape south or
  west (the FAB lane band and riser forest block every such path), so
  it pays the comb toll: a column at x1530 rises through the seven
  surface-wire horizontals into a north lane, then drops onto pitch's
  left-edge pin.  ~7 crossings is the floor for this fixed pin order.
- Right-edge ports/drops are placed by the same DP machinery (ports get
  solver-assigned y slots).
- The vehicle input repin reorders the pins TestHL20Subsonic's constant
  wall lands on, so that diagram's constants are re-rowed to the new
  pin order and its seven feeds re-routed crossing-free.
"""
import itertools
import os
import sys
import laygen as lg
from gen_aero import (f, box, icon_left, icon_right, E, mk_conn, finish)

LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "HL20Demo", "dyad")

TARGETS = ("HL20Vehicle.dyad", "Controllers.dyad",
           "TestHarnesses.dyad", "HL20FullSystem.dyad")


def _p(*parts):
    return os.path.join(LIB, *parts)

# ---------------------------------------------------------------- repins

# vehicle: right-edge output pins in this top->bottom icon order.
VEH_OUT = ["ALT_FT", "ALPHA_DEG", "BETADEG", "BETADOT", "PDEG", "MACH_out",
           "RDEG", "QDEG", "SINPHI", "COSPHI", "COSTHE", "QBAR", "EAS",
           "NZ", "V_FPS", "POS_3"]
# vehicle: left-edge surface input pins, repinned to the base mixer
# output order so the surface wires stay order-matched.
VEH_IN = ["DWFL", "DWFR", "DBFUL", "DBFUR", "DBFLL", "DBFLR", "DRUD"]
# mixer: left-edge input pins (icon order fixed, taps only).
MIX_IN = ["DECMD", "DACMD", "DRCMD", "DSBCMD"]


def _ic_right(c):
    return {"x1": 970, "x2": 1030, "y1": f(c - 25), "y2": f(c + 25)}


def _ic_left(c):
    return {"x1": -30, "x2": 30, "y1": f(c - 25), "y2": f(c + 25)}


def repin_vehicle(src):
    comp = [x for x in src
            if isinstance(x, lg.Component) and x.name == "HL20Vehicle"][0]
    for i, nm in enumerate(VEH_OUT):
        comp.set_icon(nm, _ic_right(25 + 50 * i))
    for i, nm in enumerate(VEH_IN):
        comp.set_icon(nm, _ic_left(150 + 100 * i))


def repin_yaw(src):
    """Move yaw.RDEG's bottom-edge icon pin east so its riser column in
    FullSystem clears the label drawn under the yaw block (~x517-553)."""
    comp = [x for x in src
            if isinstance(x, lg.Component) and x.name == "YawControl"][0]
    comp.set_icon("RDEG", {"x1": 700, "x2": 760, "y1": 970, "y2": 1030})


def fix_subsonic(src):
    """Re-row TestHL20Subsonic's constant wall to the repinned vehicle
    input order and re-route the seven feeds crossing-free.

    Constants keep their x column and rows (200-300 .. 1700-1800);
    only which block sits on which row changes.  Down-feeds (constant
    above its pin) take columns right-to-left, up-feeds left-to-right —
    zero crossings either way.
    """
    comp = [x for x in src
            if isinstance(x, lg.Component) and x.name == "TestHL20Subsonic"][0]
    ROWS = [(200, 300), (450, 550), (700, 800), (950, 1050),
            (1200, 1300), (1450, 1550), (1700, 1800)]
    # vehicle input pin order top->bottom after repin_vehicle:
    #   DWFL@995, DWFR@1025, DBFUL@1055, DBFUR@1085, DBFLL@1115,
    #   DBFLR@1145, DRUD@1175  (vehicle box y950-1250)
    ORDER = ["c_dwfl", "c_dwfr", "c_dbful", "c_dbfur",
             "c_dbfll", "c_dbflr", "c_drud"]
    PIN = {"c_dwfl": 995, "c_dwfr": 1025, "c_dbful": 1055,
           "c_dbfur": 1085, "c_dbfll": 1115, "c_dbflr": 1145,
           "c_drud": 1175}
    COL = {"c_dwfl": 430, "c_dwfr": 410, "c_dbful": 390, "c_dbfur": 370,
           "c_dbfll": 320, "c_dbflr": 335, "c_drud": 350}
    for nm, (y1, y2) in zip(ORDER, ROWS):
        comp.set_diagram(nm, {"x1": 200, "x2": 300, "y1": y1, "y2": y2})
    new_conns = []
    for c in comp.connects:
        if c["kind"] != "connect":
            new_conns.append(c)
            continue
        src_arg = c["args"][0].split(".")[0]
        if src_arg in PIN:
            cx = COL[src_arg]
            cy = (comp.decl(src_arg)["placement"]["diagram"]["y1"]
                  + comp.decl(src_arg)["placement"]["diagram"]["y2"]) / 2
            c["emitted"] = comp.emit_connect(
                c["args"], [(1, [(cx, cy), (cx, PIN[src_arg])], 2)])
        new_conns.append(c)
    comp.connects = new_conns


# ------------------------------------------------------- generic solver
#
# Model: each wire has a horizontal "lane" occupying rank positions
# (smaller rank = smaller y).  A wire owns vertical "columns"
# (x, y_far) that connect its lane to a pin/junction at the other end.
# A column of wire w at (x, ye) crosses lane l (at y_l) iff y_l lies
# strictly between y_w and ye and x is inside lane l's x-span.
# For drops the far end is the vehicle pin y; for risers it is the
# controller pin y (300); for escapes it is a north-lane y.

def _inside(v, a, b):
    return min(a, b) < v < max(a, b)


def lane_dp(wires, y_of, allowed=None):
    """wires: name -> dict(start, end, cols=[(x, y_far)]).

    Returns optimal top->bottom order (list of names) minimizing the
    total column-vs-lane crossing count.  y_of(rank) maps rank -> y.
    allowed(wire, rank), if given, restricts which ranks a wire may take.
    """
    names = list(wires)
    n = len(names)

    def cross(i, ri, j, rj):
        """crossings between wire i (rank ri, shallower) and wire j
        (rank rj, deeper)."""
        yi, yj = y_of(ri), y_of(rj)
        wi, wj = wires[i], wires[j]
        c = 0
        # columns of j descending past lane i
        for (x, ye) in wj["cols"]:
            if _inside(yi, yj, ye) and wi["start"] <= x <= wi["end"]:
                c += 1
        # columns of i reaching down through lane j
        for (x, ye) in wi["cols"]:
            if _inside(yj, yi, ye) and wj["start"] <= x <= wj["end"]:
                c += 1
        return c

    INF = float("inf")
    dp = {0: (0, ())}
    for sz in range(1, n + 1):
        ndp = {}
        for mask in range(1 << n):
            if bin(mask).count("1") != sz:
                continue
            best = (INF, ())
            for k in range(n):
                if not (mask >> k) & 1:
                    continue
                if allowed is not None and not allowed(names[k], sz - 1):
                    continue
                prev = mask & ~(1 << k)
                if prev not in dp:
                    continue
                c0, path = dp[prev]
                # appending names[k] at rank sz-1 (deepest so far)
                add = sum(cross(w, p, names[k], sz - 1)
                          for p, w in enumerate(path))
                if c0 + add < best[0]:
                    best = (c0 + add, path + (names[k],))
            ndp[mask] = best
        dp = ndp
    return dp[(1 << n) - 1]


# --------------------------------------------------------- north lanes
#
# North wires and their columns.  Column = (x, far end y).
#   DACMD: roll riser x520 (pin 550), yaw west arm x620 (pin 755),
#          mixer tap column (x~1270 -> pin 570)
#   DRCMD: yaw riser x630 (pin 750), tap -> 610
#   DSBCMD: speed riser x360 (pin 950), tap -> 650
#   DECMD: junction column x1200 (pin 250), tap -> 530
#   DLEDEG: west column x660 -> pitch pin 275, east column x1540 -> 685
#   QDEG: escape column x740 -> FAB lane ~1430
#   NZ:   escape column x2000 -> FAB lane ~1280
# Tap columns all sit in the x1240-1290 notch; assign each wire a
# nominal x1270 for DP purposes (the true per-wire x is chosen after).

NY0 = 90.0
DY = 15.0

NORTH = {
    "DACMD":  {"start": 340.0, "end": 2990.0,
               "cols": [(520.0, 550.0), (340.0, 755.0), (1270.0, 570.0)]},
    "DRCMD":  {"start": 630.0, "end": 2980.0,
               "cols": [(630.0, 750.0), (1260.0, 610.0)]},
    "DSBCMD": {"start": 650.0, "end": 2970.0,
               "cols": [(650.0, 950.0), (1250.0, 650.0)]},
    "DECMD":  {"start": 1165.0, "end": 2960.0,
               "cols": [(1165.0, 250.0), (1240.0, 530.0)]},
    "DLEDEG": {"start": 695.0, "end": 1530.0,
               "cols": [(695.0, 275.0), (1530.0, 690.0)]},
    "QDEG":   {"start": 685.0, "end": 2950.0,
               "cols": [(685.0, 1430.0)]},
    "NZ":     {"start": 1190.0, "end": 2940.0,
               "cols": [(1190.0, 1280.0)]},
}

# The pitch label sits above its box at ~(782-820, 156-180): any lane
# whose x-span includes that window must ride above y~153.  NZ and DECMD
# start east of the window (x1165/1190), so they may take the deep slots.
LABEL_WIN = (780.0, 822.0)
_N_CROSS = {w for w, d in NORTH.items()
            if d["start"] < LABEL_WIN[1] and d["end"] > LABEL_WIN[0]}
_N_LOW = len(NORTH) - (len(NORTH) - len(_N_CROSS))  # slots above 153


def _north_allowed(w, r):
    if w in _N_CROSS:
        return r < _N_LOW
    return r >= _N_LOW


N_COST, N_ORDER = lane_dp(NORTH, lambda r: NY0 + DY * r,
                          allowed=_north_allowed)
LY = {w: NY0 + DY * k for k, w in enumerate(N_ORDER)}


# ------------------------------------------------------------- FAB
#
# FAB wires: riser columns to controller bottom pins (far end 300),
# escape columns back up to the north lanes (far end = LY[wire]),
# and drop columns (x = 2020 + 10*rank, far end = vehicle pin y).
# start = west end of the lane (leftmost column x).

FY0 = 1250.0
FDY = 30.0

FABW = {
    "VTOTALI": {"start": 1127.5, "end": 2020.0,
                "cols": [(1127.5, 300.0)], "vy": 667.5},
    "NZ":      {"start": 1076.875, "end": 2030.0,
                "cols": [(1076.875, 300.0), (1190.0, LY["NZ"])],
                "vy": 652.5},
    "QBAR":    {"start": 1026.25, "end": 2040.0,
                "cols": [(1026.25, 300.0)], "vy": 622.5},
    "COSTHE":  {"start": 975.625, "end": 2050.0,
                "cols": [(975.625, 300.0)], "vy": 607.5},
    "COSPHI":  {"start": 925.0, "end": 2060.0,
                "cols": [(925.0, 300.0)], "vy": 592.5},
    "SINPHI":  {"start": 874.375, "end": 2070.0,
                "cols": [(874.375, 300.0)], "vy": 577.5},
    "QDEG":    {"start": 685.0, "end": 2080.0,
                "cols": [(773.125, 300.0), (685.0, LY["QDEG"])],
                "vy": 562.5},
    "RDEG":    {"start": 569.5, "end": 2090.0,
                "cols": [(823.75, 300.0), (569.5, 800.0)], "vy": 547.5},
    "MACH":    {"start": 490.0, "end": 2100.0,
                "cols": [(722.5, 300.0), (490.0, 800.0)], "vy": 532.5},
    "PDEG":    {"start": 399.95, "end": 2110.0,
                "cols": [(399.95, 600.0)], "vy": 517.5},
}


def fab_dp():
    """Same DP plus drop columns positioned by final depth rank."""
    names = list(FABW)
    n = len(names)

    def cols(w, rank):
        return FABW[w]["cols"] + [(DXW[w], FABW[w]["vy"])]

    def cross(i, ri, j, rj):
        yi, yj = FY0 + FDY * ri, FY0 + FDY * rj
        wi, wj = FABW[i], FABW[j]
        end_i = DXW[i]
        end_j = DXW[j]
        c = 0
        for (x, ye) in cols(j, rj):
            if _inside(yi, yj, ye) and wi["start"] <= x <= end_i:
                c += 1
        for (x, ye) in cols(i, ri):
            if _inside(yj, yi, ye) and wj["start"] <= x <= end_j:
                c += 1
        return c

    INF = float("inf")
    dp = {0: (0, ())}
    for sz in range(1, n + 1):
        ndp = {}
        for mask in range(1 << n):
            if bin(mask).count("1") != sz:
                continue
            best = (INF, ())
            for k in range(n):
                if not (mask >> k) & 1:
                    continue
                prev = mask & ~(1 << k)
                if prev not in dp:
                    continue
                c0, path = dp[prev]
                add = sum(cross(w, p, names[k], sz - 1)
                          for p, w in enumerate(path))
                if c0 + add < best[0]:
                    best = (c0 + add, path + (names[k],))
            ndp[mask] = best
        dp = ndp
    return dp[(1 << n) - 1]


DXW = {w: 2020.0 + 10.0 * k
       for k, w in enumerate(sorted(FABW, key=lambda w: -FABW[w]["vy"]))}

F_COST, F_ORDER = fab_dp()
FLY = {w: FY0 + FDY * k for k, w in enumerate(F_ORDER)}
FDX = DXW


# ------------------------------------------------------ east solver
#
# Right-edge wires: (lane_y, start_x).  Ports get y slots on the edge;
# drops take x = 2900 + 10*rank.  Crossing model identical to the DP:
# for drop_i left of drop_j, lane_j passes over drop_i iff lane_j's y is
# inside drop_i's arc and lane_j spans x_i; approach_i passes under
# drop_j iff port_i's y is inside drop_j's arc.  Since every lane starts
# left of 2900, lane_j always spans x_i; the conditions reduce to
# arc-containment tests.

SLOTS = [150.0 + 100.0 * i for i in range(18)]  # 150..1850


def east_solve():
    WIRES = {
        "DECMD":  (LY["DECMD"], 1200.0),
        "DACMD":  (LY["DACMD"], 520.0),
        "DRCMD":  (LY["DRCMD"], 630.0),
        "DSBCMD": (LY["DSBCMD"], 360.0),
        "QDEG":   (LY["QDEG"], 740.0),
        "NZ":     (LY["NZ"], 1050.0),
        "DLE":    (430.0, 1560.0),
        "ALPHA":  (472.5, 2000.0),
        "ALTFT":  (457.5, 2000.0),
    }
    names = list(WIRES)
    n = len(names)

    def ports_y(order):
        return {w: SLOTS[round(i * (len(SLOTS) - 1) / (n - 1))]
                for i, w in enumerate(order)}

    def pair(i, j, py):
        """crossings contributed when drop_i is left of drop_j."""
        li, _ = WIRES[i]
        lj, _ = WIRES[j]
        c = 0
        if _inside(lj, li, py[i]):
            c += 1
        if _inside(py[i], lj, py[j]):
            c += 1
        return c

    def best_drops(py):
        C = [[pair(names[a], names[b], py) for b in range(n)]
             for a in range(n)]
        INF = float("inf")
        dp = {0: (0, ())}
        for sz in range(1, n + 1):
            ndp = {}
            for mask in range(1 << n):
                if bin(mask).count("1") != sz:
                    continue
                best = (INF, ())
                for k in range(n):
                    if not (mask >> k) & 1:
                        continue
                    prev = mask & ~(1 << k)
                    if prev not in dp:
                        continue
                    c0, path = dp[prev]
                    add = sum(C[names.index(w)][k] for w in path)
                    if c0 + add < best[0]:
                        best = (c0 + add, path + (names[k],))
                ndp[mask] = best
            dp = ndp
        return dp[(1 << n) - 1]

    ports = sorted(names, key=lambda w: WIRES[w][0])
    best_c, best_d = best_drops(ports_y(ports))
    improved = True
    while improved:
        improved = False
        for a in range(n):
            for b in range(n):
                if a == b:
                    continue
                cand = ports[:]
                w = cand.pop(a)
                cand.insert(b, w)
                c, d = best_drops(ports_y(cand))
                if c < best_c:
                    best_c, best_d, ports = c, d, cand
                    improved = True
    xs = {w: 2900.0 + 10.0 * k for k, w in enumerate(best_d)}
    return xs, ports_y(ports), best_c


EXS, EPY, ECOST = east_solve()

# mixer left-edge inputs keep their original icon order (MIX_IN) so
# TestMixerAssist wiring is untouched.  Tap columns are assigned by pin
# depth -- shallowest pin -> rightmost column -- which makes every
# column->pin jog crossing-free.  Pin ys are read back from the icon.
TAPS_SORTED = list(MIX_IN)
TX = {w: 1290.0 - 20.0 * k for k, w in enumerate(TAPS_SORTED)}
TPY = {w: 530.0 + 40.0 * k for k, w in enumerate(TAPS_SORTED)}


# ---------------------------------------------------------------- routes

def gen(src, pins):
    comp = [x for x in src
            if isinstance(x, lg.Component) and x.name == "HL20FullSystem"][0]
    ctx = lg.Ctx(comp, pins)
    conns = []

    # move boundary ports to solver-assigned positions
    P2W = {"DECMD": "DECMD", "DACMD": "DACMD", "DRCMD": "DRCMD",
           "DSBCMD": "DSBCMD", "ALPHA_DEG": "ALPHA", "ALT_FT": "ALTFT",
           "DLE": "DLE", "QDEG": "QDEG", "NZ": "NZ"}
    for port, w in P2W.items():
        comp.set_diagram(port, box(3000, EPY[w]))
    comp.set_diagram("DCPILOT", box(0, 2300))
    comp.set_diagram("DPPILOT", box(0, 2200))

    # ---- inputs
    conns.append(mk_conn(["DCPILOT", "pitch.DCPILOT"],
                         [E(1, [(696, 2300), (696, 205)], 2)]))
    conns.append(mk_conn(["DWPILOT", "roll.DWPILOT"],
                         [E(1, [(200, 1700), (200, 520)], 2)]))
    conns.append(mk_conn(["DPPILOT", "yaw.DPPILOT"],
                         [E(1, [(455, 2200), (455, 715)], 2)]))
    conns.append(mk_conn(["DLSBCOM", "speed.DLSBCOM"],
                         [E(1, [(230, 2100), (230, 950)], 2)]))

    # ---- command lanes (rank -> lane y; tap columns by depth)
    ly = LY["DECMD"]
    xd = EXS["DECMD"]
    conns.append(mk_conn(
        ["pitch.DECMD", "mixer.DECMD", "DECMD"],
        [E(1, [(1165, 250), (1165, ly)], -1),
         E(-1, [], -2),
         E(-2, [(xd, ly), (xd, EPY["DECMD"])], 3),
         E(-2, [(TX["DECMD"], TPY["DECMD"])], 2)],
        [(1165, ly), (TX["DECMD"], ly)]))

    ly = LY["DACMD"]
    xd = EXS["DACMD"]
    conns.append(mk_conn(
        ["roll.DACMD", "yaw.DACMD", "mixer.DACMD", "DACMD"],
        [E(1, [(520, 550), (520, ly)], -1),
         E(-1, [], -2),
         E(-2, [], -3),
         E(-3, [(xd, ly), (xd, EPY["DACMD"])], 4),
         E(2, [(340, 755), (340, ly)], -2),
         E(-3, [(TX["DACMD"], TPY["DACMD"])], 3)],
        [(520, ly), (340, ly), (TX["DACMD"], ly)]))

    ly = LY["DRCMD"]
    xd = EXS["DRCMD"]
    conns.append(mk_conn(
        ["yaw.DRCMD", "mixer.DRCMD", "DRCMD"],
        [E(1, [(630, 750), (630, ly)], -1),
         E(-1, [], -2),
         E(-2, [(xd, ly), (xd, EPY["DRCMD"])], 3),
         E(-2, [(TX["DRCMD"], TPY["DRCMD"])], 2)],
        [(630, ly), (TX["DRCMD"], ly)]))

    ly = LY["DSBCMD"]
    xd = EXS["DSBCMD"]
    conns.append(mk_conn(
        ["speed.DSBCMD", "mixer.DSBCMD", "DSBCMD"],
        [E(1, [(650, 950), (650, ly)], -1),
         E(-1, [], -2),
         E(-2, [(xd, ly), (xd, EPY["DSBCMD"])], 3),
         E(-2, [(TX["DSBCMD"], TPY["DSBCMD"])], 2)],
        [(650, ly), (TX["DSBCMD"], ly)]))

    # ---- mixer -> vehicle surface wires (near-straight with small jogs)
    SURF = [("DUL", "DBFUL", 1810), ("DUR", "DBFUR", 1820),
            ("DLL", "DBFLL", 1830), ("DLR", "DBFLR", 1840),
            ("DRE", "DWFR", 1860), ("DR", "DRUD", 1870)]
    for mx, vv, jx in SURF:
        sy = ctx.pin("mixer." + mx)[1]
        ty = ctx.pin("vehicle." + vv)[1]
        conns.append(mk_conn(["mixer." + mx, "vehicle." + vv],
                             [E(1, [(jx, sy), (jx, ty)], 2)]))

    # DLE: 3-way; DWFL leg drops at x1850, port leg rises to y430 east.
    xd = EXS["DLE"]
    dle_y = ctx.pin("mixer.DLE")[1]
    dwfl_y = ctx.pin("vehicle.DWFL")[1]
    conns.append(mk_conn(
        ["mixer.DLE", "vehicle.DWFL", "DLE"],
        [E(1, [(1850, dle_y)], -1),
         E(-1, [(1850, dwfl_y)], 2),
         E(-1, [(1850, 430), (xd, 430), (xd, EPY["DLE"])], 3)],
        [(1850, dle_y)]))

    # ---- DLEDEG return to pitch left-edge pin (700,275).  Base mixer
    # puts DLEDEG at the bottom of the comb (pin y690): the column at
    # x1530 pays ~7 crossings through the surface-wire horizontals.
    ly = LY["DLEDEG"]
    dledeg_y = ctx.pin("mixer.DLEDEG")[1]
    conns.append(mk_conn(
        ["mixer.DLEDEG", "pitch.DLEDEG"],
        [E(1, [(1530, dledeg_y), (1530, ly), (695, ly), (695, 275)], 2)]))

    # ---- vehicle feedback fabric (drop -> lane -> risers)
    RISERS = {
        "VTOTALI": [(1127.5, "pitch.VTOTALI")],
        "NZ":      [(1076.875, "pitch.NZ")],
        "QBAR":    [(1026.25, "pitch.QBAR")],
        "COSTHE":  [(975.625, "pitch.COSTHE")],
        "COSPHI":  [(925.0, "pitch.COSPHI")],
        "SINPHI":  [(874.375, "pitch.SINPHI")],
        "QDEG":    [(773.125, "pitch.QDEG")],
        "RDEG":    [(823.75, "pitch.RDEG"), (569.5, "yaw.RDEG")],
        "MACH":    [(722.5, "pitch.MACH"), (490.0, "yaw.MACH")],
        "PDEG":    [(399.95, "roll.PDEG")],
    }
    VPIN = {"VTOTALI": "V_FPS", "NZ": "NZ", "QBAR": "QBAR",
            "COSTHE": "COSTHE", "COSPHI": "COSPHI", "SINPHI": "SINPHI",
            "QDEG": "QDEG", "RDEG": "RDEG", "MACH": "MACH_out",
            "PDEG": "PDEG"}
    ESCAPE = {"NZ": (1190.0, "NZ"), "QDEG": (685.0, "QDEG")}

    for w in F_ORDER:
        vy = FABW[w]["vy"]
        dx = FDX[w]
        ly = FLY[w]
        taps_f = sorted(RISERS[w], key=lambda t: -t[0])
        args = ["vehicle." + VPIN[w]] + [t[1] for t in taps_f]
        esc = ESCAPE.get(w)
        if esc:
            args.append(esc[1])

        if not esc and len(taps_f) == 1:
            tx = taps_f[0][0]
            conns.append(mk_conn(
                args, [E(1, [(dx, vy), (dx, ly), (tx, ly)], 2)]))
            continue

        allj = sorted([t[0] for t in taps_f] + ([esc[0]] if esc else []))
        jnum = {x: k + 1 for k, x in enumerate(allj)}
        js = [(jx, ly) for jx in allj]
        # trunk enters from the east: ends at the rightmost junction,
        # then chain west along the lane through the others.
        edges = [E(1, [(dx, vy), (dx, ly), (allj[-1], ly)], -len(allj))]
        for k in range(len(allj) - 1, 0, -1):
            edges.append(E(-(k + 1), [], -k))
        for k, (tx, tep) in enumerate(taps_f):
            edges.append(E(-jnum[tx], [], 2 + k))
        if esc:
            ex = esc[0]
            edges.append(E(-jnum[ex],
                           [(ex, LY[w]), (EXS[w], LY[w]),
                            (EXS[w], EPY[w])],
                           len(args)))
        conns.append(mk_conn(args, edges, js))

    conns.append(mk_conn(
        ["vehicle.ALPHA_DEG", "ALPHA_DEG"],
        [E(1, [(EXS["ALPHA"], 472.5), (EXS["ALPHA"], EPY["ALPHA"])], 2)]))

    conns.append(mk_conn(
        ["vehicle.ALT_FT", "ALT_FT"],
        [E(1, [(EXS["ALTFT"], 457.5), (EXS["ALTFT"], EPY["ALTFT"])], 2)]))

    finish(comp, conns)


def produce(files):
    """Regenerate the full-system family inside the in-memory
    {path: segs} store."""
    repin_vehicle(files[_p("HL20Vehicle.dyad")])
    repin_yaw(files[_p("Controllers.dyad")])
    fix_subsonic(files[_p("TestHarnesses.dyad")])
    gen(files[_p("HL20FullSystem.dyad")], lg.pins_from(files))


def _targets():
    return [_p(t) for t in TARGETS]


def check():
    """--check: regenerate in memory and exit non-zero on drift.
    Nothing is written."""
    files = lg.load_dir(LIB)
    produce(files)
    bad = lg.drift_of(files, _targets())
    if bad:
        print("DRIFT:", ", ".join(bad))
        sys.exit(1)
    print("gen_fs: in sync")


def main():
    print("north:", N_ORDER, "cost", N_COST)
    print("fab:", F_ORDER, "cost", F_COST)
    print("east:", ECOST, {k: round(v) for k, v in EXS.items()})
    files = lg.load_dir(LIB)
    produce(files)
    diffs = lg.apply_guarded(files, _targets())
    if diffs:
        print("refusing to write: non-layout content would change")
        for d in diffs:
            print("  " + d)
        sys.exit(1)


if __name__ == "__main__":
    if "--check" in sys.argv[1:]:
        check()
    else:
        main()
