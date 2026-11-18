#!/usr/bin/env python3
"""HL20Vehicle re-layout v6.

Keeps HL20Aero's committed icon pins (shared with TestAeroPoint and
TestHarnesses) and repins only VehicleDynamics' icon — its sole consumer
is this diagram.

vd    (400-1000, 200-2600): right edge holds 8 aero-facing output pins at
      the exact y of aero's left-edge pins, then 8 boundary-output pins;
      top edge holds the 6 C* inputs; bottom edge the 4 vout feeds.
aero  (2900-3500, 400-1600)  unchanged
vout  (200-800, 3000-3800)   unchanged

Routing:
- vd->aero: 8 horizontal runs at aero's pin rows. alpha/beta/mach/v_fps
  tap boundary ports via upward risers at x2550-2800; ALPHA_DEG's run
  exits at y145 and ends at x4560, left of the C* riser fence (4600+).
- DBF commands: ports sit in a single 120-pitch row below aero; each
  wire rises in a free column and jogs onto the bottom-edge pin.  The
  vd->boundary outputs terminate at x2770, left of aero's glyph wall, so
  the whole region below aero stays clear for the rises.
- aero.C* feedback: right-edge pin -> riser (4600+30i) -> channel
  (110-4i) -> drop at vd top pin x. riser inc / channel dec / drop dec
  gives zero crossings.
- vd bottom -> vout top: staggered lanes 2650+15i, zero crossings.
- vout right-edge -> boundary ports: straight runs.
"""
import sys
import laygen as lg
from gen_aero import (f, box, icon_top, icon_bottom, E, mk_conn, finish)

LIB = "HL20Demo/dyad"

VD = {"x1": 400, "x2": 1000, "y1": 200, "y2": 2600}
AERO = {"x1": 2900, "x2": 3500, "y1": 400, "y2": 1600}
VOUT = {"x1": 200, "x2": 800, "y1": 3000, "y2": 3800}

# vd right-edge pins aligned to aero left-edge pin rows (fracs 50+100i ->
# dyad y 460..1300 step 120); then 8 boundary outputs at y1660..2500.
VD_AERO = ["alpha_deg", "beta_deg", "mach", "v_fps", "hob", "pb", "qb",
           "rb"]
AERO_LEFT = ["alpha_deg", "beta_deg", "mach", "vrw_fps", "hob", "pb",
             "qb", "rb"]
VD_OUTS = ["sin_phi", "cos_phi", "cos_theta", "bdot", "eas_kts",
           "alt_ft", "qbar_psf", "pos_3"]
CS = ["CX", "CY", "CZ", "Cl", "Cm", "Cn"]
DBFS = ["DBFUL", "DBFUR", "DBFLL", "DBFLR", "DWFL", "DWFR", "DRUD"]
VD2OUT = {"sin_phi": "SINPHI", "cos_phi": "COSPHI", "cos_theta": "COSTHE",
          "bdot": "BETADOT", "eas_kts": "EAS", "alt_ft": "ALT_FT",
          "qbar_psf": "QBAR", "pos_3": "POS_3"}
VOUT_OUTS = {"pdeg": "PDEG", "qdeg": "QDEG", "rdeg": "RDEG", "nz_g": "NZ"}

BND_YS = [1660 + 120 * i for i in range(8)]          # 1660..2500
VD_TOP_X = [850 - 80 * i for i in range(6)]           # 850..450
VD_BOT_F = [100 + 200 * i for i in range(4)]          # 100..700

# tap geometry: net -> (junction col, port wire y, port box center)
# port-wire lanes must sit below the C* channels (y90-110) and be spaced
# >=60 so no wire crosses another port's glyph box.
TAPS = {"alpha_deg": (2550, 150, 4530, "ALPHA_DEG"),
        "beta_deg": (2600, 230, 4410, "BETADEG"),
        "mach": (2700, 300, 4530, "MACH_out"),
        "v_fps": (2800, 370, 4410, "V_FPS")}


def icon_right40(fc):
    return {"x1": 970, "x2": 1030, "y1": f(fc - 20), "y2": f(fc + 20)}


def vd_frac_y(y):
    return (y - VD["y1"]) / (VD["y2"] - VD["y1"]) * 1000


def vd_frac_x(x):
    return (x - VD["x1"]) / (VD["x2"] - VD["x1"]) * 1000


def repin_vd():
    src = lg.load_file(f"{LIB}/HL20Vehicle.dyad")
    comp = [x for x in src
            if isinstance(x, lg.Component) and x.name == "VehicleDynamics"][0]
    pins = lg.library_pins(LIB)
    for i, nm in enumerate(VD_AERO):
        _, ay = lg.pin_xy(AERO, pins["HL20Aero"][AERO_LEFT[i]][0])
        comp.set_icon(nm, icon_right40(vd_frac_y(ay)))
    for nm, y in zip(VD_OUTS, BND_YS):
        comp.set_icon(nm, icon_right40(vd_frac_y(y)))
    for nm, px in zip(CS, VD_TOP_X):
        comp.set_icon(nm, icon_top(vd_frac_x(px)))
    for nm, f in zip(["p_rad", "q_rad", "r_rad", "Fz_body"], VD_BOT_F):
        comp.set_icon(nm, icon_bottom(f))
    lg.save_file(f"{LIB}/HL20Vehicle.dyad", src)


def gen():
    pins = lg.library_pins(LIB)
    src = lg.load_file(f"{LIB}/HL20Vehicle.dyad")
    comp = [x for x in src
            if isinstance(x, lg.Component) and x.name == "HL20Vehicle"][0]
    comp.set_diagram("vd", VD)
    comp.set_diagram("aero", AERO)
    comp.set_diagram("vout", VOUT)
    ctx = lg.Ctx(comp, pins)
    conns = []

    # DBF commands: aero's pins are on its bottom edge; ports alternate
    # two rows directly under their pins (non-contiguous glyph boxes)
    # and rise straight up — the region is clear once the vd->boundary
    # outputs terminate at x2770.
    for i, nm in enumerate(DBFS):
        ax, ay = ctx.pin("aero." + nm)
        comp.set_diagram(nm, box(ax, 1880 if i % 2 == 0 else 1980))
        conns.append(mk_conn([nm, "aero." + nm], [E(1, [], 2)]))

    # vd -> aero: straight runs at aero pin rows; four nets tap ports via
    # upward risers.
    for vd_nm, a_nm in zip(VD_AERO, AERO_LEFT):
        vx, vy = ctx.pin("vd." + vd_nm)
        ax, ay = ctx.pin("aero." + a_nm)
        if vd_nm in TAPS:
            xc, py, pcx, port = TAPS[vd_nm]
            comp.set_diagram(port, box(pcx, py))
            conns.append(mk_conn(
                ["vd." + vd_nm, "aero." + a_nm, port],
                [E(1, [(xc, vy)], -1),
                 E(-1, [], 2),
                 E(-1, [(xc, py)], 3)],
                [(xc, vy)]))
        else:
            conns.append(mk_conn(["vd." + vd_nm, "aero." + a_nm],
                                 [E(1, [], 2)]))

    # vd right edge -> boundary output column at x2770 (left of aero's
    # glyph wall, so the region under aero stays clear for DBF rises)
    for nm, outp in VD2OUT.items():
        vx, vy = ctx.pin("vd." + nm)
        comp.set_diagram(outp, box(2770, vy))
        conns.append(mk_conn(["vd." + nm, outp], [E(1, [], 2)]))

    # aero.C* -> vd top pins via riser + top channel + drop
    for i, nm in enumerate(CS):
        ax, ay = ctx.pin("aero." + nm)
        vx, vy = ctx.pin("vd." + nm)
        xr, xc = 4600 + 30 * i, 110 - 4 * i
        conns.append(mk_conn(
            ["aero." + nm, "vd." + nm],
            [E(1, [(xr, ay), (xr, xc), (vx, xc)], 2)]))

    # vd bottom -> vout top via staggered lanes
    for i, vd_nm in enumerate(["p_rad", "q_rad", "r_rad", "Fz_body"]):
        vx, vy = ctx.pin("vd." + vd_nm)
        ox, oy = ctx.pin("vout." + ["p_rad", "q_rad", "r_rad",
                                  "fz_body"][i])
        h = 2650 + 15 * i
        conns.append(mk_conn(
            ["vd." + vd_nm, "vout." + ["p_rad", "q_rad", "r_rad",
                                       "fz_body"][i]],
            [E(1, [(vx, h), (ox, h)], 2)]))

    # vout -> boundary ports
    for nm, outp in VOUT_OUTS.items():
        ox, oy = ctx.pin("vout." + nm)
        comp.set_diagram(outp, box(4810, oy))
        conns.append(mk_conn(["vout." + nm, outp], [E(1, [], 2)]))

    finish(comp, conns)
    lg.save_file(f"{LIB}/HL20Vehicle.dyad", src)


def check():
    """--check: run the gen_vd2 -> gen_veh2 pipeline and exit non-zero
    if the committed file drifts."""
    import subprocess
    from pathlib import Path
    target = f"{LIB}/HL20Vehicle.dyad"
    orig = Path(target).read_bytes()
    try:
        subprocess.run([sys.executable, "tools/gen_vd2.py"], check=True)
        repin_vd()
        lg._LIB_CACHE.clear()
        gen()
    finally:
        drift = Path(target).read_bytes() != orig
        Path(target).write_bytes(orig)
    if drift:
        print(f"DRIFT: {target}")
        sys.exit(1)
    print(f"{target}: in sync")


if __name__ == "__main__":
    if "--check" in sys.argv[1:]:
        check()
    else:
        repin_vd()
        lg._LIB_CACHE.clear()
        gen()
