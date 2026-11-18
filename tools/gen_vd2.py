#!/usr/bin/env python3
"""VehicleDynamics re-layout v7 (right-om scheme).

body->flight down-up lanes unchanged. Quaternion taps ride their lane level
rightward to descent cols at x2065-2080 (right of the omega ascent columns,
left of the omega port legs), under-run at y2486-2498, then drop onto the
top-edge forces pins; a junction at each descent corner keeps every edge
near its Manhattan bound. Omega nets ride lanes at y2290-2390 rightward to
ascents at x2028/2056 into bottom-edge AirData pins; boundary ports branch
off the ascent columns, with om2's qb leg heading straight left to its port.
qbar rides the top lane at y940, drops at x2290 and under-runs at y2480
(clear of the quat drops) into the top-edge qbar_psf pin, with a direct leg
to the boundary port. F1/F2 keep the right-side detour via ccols x990/920,
lanes y3355/3345, lcols x360/364 — a junction at each lane corner keeps
each edge near its Manhattan bound; F3/T* ride ccols x860-905, lanes
y3305-3335, lcols x368-380. C* ports use right-edge pins so their stubs
stay right of x540, clear of the lcols. Fz_body rides out at y2772 and
descends at x940, right of the ccol tops.

The component's parameter declarations are read from the committed file,
not hard-coded here: generation only ever rewrites layout metadata, so any
hand edit to a parameter default survives regeneration (and the semantic
guard in main() would refuse if it did not).
"""
import json
import os
import sys
import laygen as lg

LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "HL20Demo", "dyad")
V = os.path.join(LIB, "HL20Vehicle.dyad")

BODY = {"x1": 600, "x2": 800, "y1": 1500, "y2": 2300}
FLI = {"x1": 1300, "x2": 1500, "y1": 1400, "y2": 2130}
AIR = {"x1": 1700, "x2": 2100, "y1": 1100, "y2": 1690}
FOR = {"x1": 550, "x2": 850, "y1": 2500, "y2": 3300}


def pbox(x, y): return {"x1": x - 30, "x2": x + 30, "y1": y - 30, "y2": y + 30}
def pinR(y): return {"x1": 970, "y1": y - 30, "x2": 1030, "y2": y + 30}
def pinL(y): return {"x1": -30, "y1": y - 30, "x2": 30, "y2": y + 30}
def pinB(x): return {"x1": x - 30, "y1": 970, "x2": x + 30, "y2": 1030}
def pinT(x): return {"x1": x - 30, "y1": -30, "x2": x + 30, "y2": 30}


def generate(params, pins):
    """Build the VehicleDynamics component text.  `params` is the raw
    parameter-declaration text copied verbatim from the existing file;
    `pins` is the library pin map."""
    def bp(n): return lg.pin_xy(BODY, pins["RigidBody6DOF"][n][0])
    def fp(n): return lg.pin_xy(FLI, pins["FlightState"][n][0])
    def ap(n): return lg.pin_xy(AIR, pins["AirData"][n][0])
    def fop(n): return lg.pin_xy(FOR, pins["AeroForceBuilder"][n][0])

    DECLS, CONNS = [], []

    def pd(name, kind, icon, dg):
        DECLS.append('  %s = %s() {"Dyad": {"placement": {"icon": %s, "diagram": %s}}}\n'
                     % (name, kind, json.dumps(icon), json.dumps(dg)))

    def pd_args(name, args, dg):
        d = dict(dg); d["rot"] = 0
        DECLS.append('  %s = %s {"Dyad": {"placement": {"diagram": %s}}}\n'
                     % (name, args, json.dumps(d)))

    def conn(args, edges, junctions=()):
        CONNS.append(lg.Component.emit_connect(None, args, edges, junctions))

    # ------------------------------------------------------------ ports
    pd("alpha_deg", "RealOutput", pinL(500), pbox(1610, 1625))
    pd("beta_deg",  "RealOutput", pinL(500), pbox(1610, 1745))
    pd("mach",   "RealOutput", pinL(500), pbox(2180, 1070))
    pd("v_fps",  "RealOutput", pinL(500), pbox(2250, 1195.875))
    pd("hob",    "RealOutput", pinL(500), pbox(2180, 1254.875))
    pd("pb",     "RealOutput", pinB(500), pbox(1810, 2110))
    pd("p_rad",  "RealOutput", pinB(500), pbox(1880, 2090))
    pd("qb",     "RealOutput", pinB(500), pbox(865, 2330))
    pd("q_rad",  "RealOutput", pinB(500), pbox(1030, 2330))
    pd("rb",     "RealOutput", pinB(500), pbox(2220, 2240))
    pd("r_rad",  "RealOutput", pinB(500), pbox(2220, 2360))
    pd("Fz_body", "RealOutput", pinB(500), pbox(950, 3410))
    pd("pos_3",  "RealOutput", pinB(500), pbox(1100, 880))
    pd("sin_phi",   "RealOutput", pinL(500), pbox(1545, 1818))
    pd("cos_phi",   "RealOutput", pinT(500), pbox(1640, 2000))
    pd("cos_theta", "RealOutput", pinT(500), pbox(1560, 1950))
    pd("bdot",    "RealOutput", pinB(500), pbox(1830, 970))
    pd("eas_kts", "RealOutput", pinB(500), pbox(1920, 820))
    pd("alt_ft",  "RealOutput", pinL(500), pbox(2070, 1020))
    pd("qbar_psf", "RealOutput", pinB(500), pbox(2030, 860))
    for i, nm in enumerate(["CX", "CY", "CZ", "Cl", "Cm", "Cn"]):
        pd(nm, "RealInput", pinR(500), pbox(500 - 85 * (i % 2), 2540 + 80 * i))

    # child instances (kept fixed)
    pd_args("body", "RigidBody6DOF(mass=mass, g=g, p1_0=p1_0, p2_0=p2_0, "
            "p3_0=p3_0, v1_0=v1_0, v2_0=v2_0, v3_0=v3_0, q0_0=q0_0, "
            "q1_0=q1_0, q2_0=q2_0, q3_0=q3_0, w1_0=w1_0, w2_0=w2_0, "
            "w3_0=w3_0)", BODY)
    pd_args("flight", "FlightState()", FLI)
    pd_args("airdata", "AirData(ft_per_m=ft_per_m, BSPAN=BSPAN, "
            "rho_sl=rho_sl, knots_per_fps=knots_per_fps)", AIR)
    pd_args("forces", "AeroForceBuilder()", FOR)

    # ------------------------------------------------------------ wires
    # body -> flight down-up lanes
    BF = [("vel_1", 820, 1210, 1605), ("vel_2", 835, 1230, 1615),
          ("vel_3", 870, 1250, 1625),
          ("qw", 1060, 1255, 2230), ("qx", 1030, 1265, 2245),
          ("qy", 1000, 1275, 2260), ("qz", 970, 1285, 2275)]
    QTAP = {"qw": (2080, 2498), "qx": (2075, 2494), "qy": (2070, 2490),
            "qz": (2065, 2486)}
    for nm, d, u, L in BF:
        bx, by = bp(nm); fx, fy = fp(nm)
        if nm in QTAP:
            fpx, fpy = fop(nm)
            dc, ur = QTAP[nm]
            conn(["body." + nm, "flight." + nm, "forces." + nm],
                 [(1, [(d, by), (d, L)], -1),
                  (-1, [(u, L), (u, fy)], 2),
                  (-1, [], -2),
                  (-2, [(dc, ur), (fpx, ur)], 3)],
                 [(u, L), (dc, L)])
        else:
            conn(["body." + nm, "flight." + nm],
                 [(1, [(d, by), (d, L), (u, L), (u, fy)], 2)])

    # pos_3 (unchanged)
    bx, by = bp("pos_3")
    conn(["body.pos_3", "airdata.pos_m", "pos_3"],
         [(1, [(840, by), (840, 980)], -1),
          (-1, [(1800, 980)], 2),
          (-1, [(1180, 980), (1180, 880)], 3)],
         [(840, 980)])

    # om3: col 880 -> lane@2300 -> asc 2056 -> bottom-edge r_rad pin.
    bx, by = bp("omega_3")
    conn(["body.omega_3", "airdata.r_rad", "rb", "r_rad"],
         [(1, [(915, by), (915, 2300)], -1),
          (-1, [(2056, 2300), (2056, 1690)], 2),
          (-2, [(2220, 2170)], 3),
          (-3, [(2160, 2185), (2160, 2360)], 4)],
         [(915, 2300), (2056, 2170), (2056, 2185)])
    # om2: col 885 -> lane@2390 -> stubs drop to ports (captions stay below
    # the lane; a stub ascending into a box would cross its caption band)
    bx, by = bp("omega_2")
    conn(["body.omega_2", "qb", "q_rad"],
         [(1, [(885, by), (885, 2390), (1000, 2390)], -2),
          (-3, [(950, 2330)], 2),
          (-2, [(995, 2390), (995, 2330)], 3)],
         [(885, 2390), (1000, 2390), (950, 2390)])
    # om1: col 930 -> lane@2290 -> asc 2028 -> bottom-edge p_rad pin.
    bx, by = bp("omega_1")
    conn(["body.omega_1", "airdata.p_rad", "pb", "p_rad"],
         [(1, [(930, by), (930, 2290)], -1),
          (-1, [(2028, 2290), (2028, 1690)], 2),
          (-2, [(1760, 2200), (1760, 2110)], 3),
          (-3, [(1880, 2130)], 4)],
         [(930, 2290), (2028, 2200), (2028, 2130)])

    # flight -> airdata (cols clear of the airdata left-edge glyph band
    # x>1670 and of the port boxes below)
    for fs, asn, e in [("v_scalar", "v_mps", 1640),
                       ("sin_alpha", "sin_alpha", 1650),
                       ("cos_alpha", "cos_alpha", 1680)]:
        fx, fy = fp(fs); ax, ay = ap(asn)
        conn(["flight." + fs, "airdata." + asn],
             [(1, [(e, fy), (e, ay)], 2)])

    # flight -> ports
    for nm, mids in [
            ("alpha_deg", [(1505, "fy"), (1505, 1625)]),
            ("beta_deg",  [(1515, "fy"), (1515, 1745)]),
            ("sin_phi",   [(1525, "fy"), (1525, 1818)]),
            ("cos_phi",   [(1595, "fy"), (1595, 1970), (1640, 1970)]),
            ("cos_theta", [(1560, "fy"), (1560, 1920)])]:
        fx, fy = fp(nm)
        conn(["flight." + nm, nm],
             [(1, [(x, fy if y == "fy" else y) for x, y in mids], 2)])

    # airdata -> ports
    ax, ay = ap("mach")
    conn(["airdata.mach", "mach"], [(1, [(2130, ay), (2130, 1070)], 2)])
    for nm in ["v_fps", "hob"]:
        conn(["airdata." + nm, nm], [(1, [], 2)])
    ax, ay = ap("bdot")
    conn(["airdata.bdot", "bdot"], [(1, [(ax, 970)], 2)])
    ax, ay = ap("eas_kts")
    conn(["airdata.eas_kts", "eas_kts"],
         [(1, [(ax, 1040), (1870, 1040), (1870, 820)], 2)])
    ax, ay = ap("alt_ft")
    conn(["airdata.alt_ft", "alt_ft"], [(1, [(ax, 1020)], 2)])

    # qbar -> forces.qbar_psf top pin + port branch
    ax, ay = ap("qbar"); fpx, fpy = fop("qbar_psf")
    conn(["airdata.qbar", "forces.qbar_psf", "qbar_psf"],
         [(1, [], -1),
          (-1, [(2290, 940), (2290, 2480), (560, 2480), (560, 2500)], 2),
          (-3, [(2090, 860)], 3)],
         [(ax, 940), (2030, 940), (2090, 940)])

    for nm in ["CX", "CY", "CZ", "Cl", "Cm", "Cn"]:
        conn([nm, "forces." + nm], [(1, [], 2)])

    # forces outputs -> body inputs (right-side detour; a junction at the
    # lane corner keeps each edge near its Manhattan bound)
    FT = [("F1", 990, 360), ("F2", 920, 364), ("F3", 905, 368),
          ("T1", 890, 372), ("T2", 875, 376), ("T3", 860, 380)]
    for i, (nm, cc, lc) in enumerate(FT):
        fx, fy = fop(nm); bx, by = bp(nm)
        L = 3355 - 10 * i
        if nm in ("F1", "F2"):
            conn(["forces." + nm, "body." + nm],
                 [(1, [(cc, fy), (cc, L)], -1),
                  (-1, [(lc, L), (lc, by)], 2)],
                 [(cc, L)])
        else:
            conn(["forces." + nm, "body." + nm],
                 [(1, [(cc, fy), (cc, L), (lc, L), (lc, by)], 2)])

    # Fz_body -> port (jogs above the ccol tops, descends right of them)
    fx, fy = fop("Fz_body")
    conn(["forces.Fz_body", "Fz_body"],
         [(1, [(940, fy), (940, 3410)], 2)])

    return ('"""\n'
            'HL-20 vehicle dynamics: 6-DOF rigid body, flight-state '
            'resolver, air-data\n'
            'computer and aerodynamic force builder wired as one package.\n'
            '"""\n'
            'component VehicleDynamics\n'
            + "".join(DECLS) + params +
            'relations\n' + "".join(CONNS) +
            'metadata {"Dyad": {"icons": {"default": '
            '"dyad://HL20Demo/vehdyn.svg"}}}\nend')


def _params_of(comp):
    """Verbatim parameter-declaration text of a parsed component."""
    return "".join(d["raw"] for d in comp.decls
                   if d.get("kind") == "param")


def produce(files):
    """Regenerate the VehicleDynamics component inside the in-memory
    {path: segs} store."""
    src = files[V]
    idx = next(i for i, s in enumerate(src)
               if isinstance(s, lg.Component) and s.name == "VehicleDynamics")
    src[idx] = generate(_params_of(src[idx]), lg.pins_from(files))


def check():
    """--check: run the gen_vd2 -> gen_veh2 pipeline in memory and exit
    non-zero if the committed file drifts.  Nothing is written."""
    import gen_veh2
    files = lg.load_dir(LIB)
    produce(files)
    gen_veh2.produce(files)
    if lg.drift_of(files, [V]):
        print(f"DRIFT: {V}")
        sys.exit(1)
    print(f"{V}: in sync")


def main():
    verbose = "--verbose" in sys.argv[1:] or "-v" in sys.argv[1:]
    files = lg.load_dir(LIB)
    produce(files)
    diffs = lg.apply_guarded(files, [V])
    if diffs:
        print("refusing to write: non-layout content would change")
        for d in diffs:
            print("  " + d)
        sys.exit(1)

    # informational lint only; layout-report is the authoritative gate
    import xcheck
    text = lg.render_segs(files[V])
    comp = next(s for s in lg.load_text(text)
                if isinstance(s, lg.Component) and s.name == "VehicleDynamics")
    cr, ov, di = xcheck.check(
        comp, lg.Ctx(comp, lg.pins_from(files)), verbose=verbose)
    if not verbose:
        print(f"VehicleDynamics: crossings={len(cr)} "
              f"overlaps={len(ov)} diagonals={len(di)}")


if __name__ == "__main__":
    if "--check" in sys.argv[1:]:
        check()
    else:
        main()
