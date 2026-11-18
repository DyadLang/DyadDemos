"""Restructure the aero family pair-fan diagrams to zero/low crossings.

Applies the proven AeroCLCD staircase recipe:
- top block input pins on left edge (arms from junction columns)
- bottom block input pins on top edge (drops from runs)
- boundary ports in a descending staircase in the gap
- air/internal sources feed through a free far-left channel
"""

import sys
import laygen as lg

LIB = "HL20Demo/dyad"

# unary math blocks share the Gain/Integrator pin shape
for _t in ("Sin", "Cos", "Abs", "Sqrt", "Exp", "Log"):
    lg.STDLIB_PINS.setdefault(
        "BlockComponents.Math." + _t,
        dict(lg.STDLIB_PINS["BlockComponents.Math.Gain"]))


def f(v):
    return int(v) if float(v) == int(float(v)) else float(v)


def box(x, y):
    return {"x1": f(x - 30), "x2": f(x + 30), "y1": f(y - 30), "y2": f(y + 30)}


def icon_left(y):
    return {"x1": -30, "x2": 30, "y1": f(y - 30), "y2": f(y + 30)}


def icon_right(y):
    return {"x1": 970, "x2": 1030, "y1": f(y - 30), "y2": f(y + 30)}


def icon_top(x):
    return {"x1": f(x - 30), "x2": f(x + 30), "y1": -30, "y2": 30}


def icon_bottom(x):
    return {"x1": f(x - 30), "x2": f(x + 30), "y1": 970, "y2": 1030}


def E(S, M, Eend):
    return (S, M, Eend)


def mk_conn(args, edges, junctions=()):
    return {"kind": "connect", "args": args, "edges": edges,
            "junctions": list(junctions), "emitted": None}


def finish(comp, conns):
    """Attach emitted text to generated connect records."""
    for c in conns:
        c["emitted"] = comp.emit_connect(
            c["args"], c["edges"], c["junctions"])
    comp.connects.clear()
    comp.connects.extend(conns)


# ----------------------------------------------------------------------
# icon re-pinning helpers
# ----------------------------------------------------------------------
def repin_inputs(comp, order, style):
    """Reposition the icon placements of input connectors.

    order: list of connector names in edge order (top->bottom for left,
           left->right for top).
    style: 'left' or 'top' with computed pitch to fit 0..1000.
    """
    n = len(order)
    pitch = 1000.0 / (n + 1)
    for i, name in enumerate(order):
        c = f(pitch * (i + 1))
        comp.set_icon(name, icon_left(c) if style == "left" else icon_top(c))


def pin(ctx, ep):
    return ctx.pin(ep)


# ----------------------------------------------------------------------
# AeroCYCN: cy top (11 left pins), cn bottom (14 top pins)
# ----------------------------------------------------------------------
SHARED_CYCN = ["alpha_deg", "beta_deg", "mach", "hob", "DBFLL", "DBFLR",
               "DBFUL", "DBFUR", "DWFL", "DWFR", "abs_drud"]
CN_ONLY = ["pb", "rb", "damp_b2v"]


def gen_cycn(src, pins):
    comp = [x for x in src if isinstance(x, lg.Component) and x.name == "AeroCYCN"][0]
    # block boxes
    comp.set_diagram("cy", {"x1": 1600, "x2": 2600, "y1": 100, "y2": 1100})
    comp.set_diagram("cn", {"x1": 1600, "x2": 2600, "y1": 2100, "y2": 3100})
    ctx = lg.Ctx(comp, pins)
    order = SHARED_CYCN + CN_ONLY          # 14 columns
    G0, DX, DG = 2040.0, 100.0, 40.0
    conns = []
    for i, name in enumerate(order):
        xc = 200 + DX * i
        g = G0 - DG * i
        comp.set_diagram(name, box(xc + 50, g))
        cn_xy = pin(ctx, "cn." + name)
        if name in SHARED_CYCN:
            cy_xy = pin(ctx, "cy." + name)
            conns.append(mk_conn(
                [name, "cy." + name, "cn." + name],
                [E(1, [], -1),
                 E(-1, [(xc, cy_xy[1])], 2),
                 E(-1, [(cn_xy[0], g)], 3)],
                [(xc, g)]))
        else:
            conns.append(mk_conn(
                [name, "cn." + name],
                [E(1, [(cn_xy[0], g)], 2)]))
    # outputs
    comp.set_diagram("cy_y", box(3050, pin(ctx, "cy.y")[1]))
    comp.set_diagram("cn_y", box(3050, pin(ctx, "cn.y")[1]))
    conns.append(mk_conn(["cy.y", "cy_y"], [E(1, [], 2)]))
    conns.append(mk_conn(["cn.y", "cn_y"], [E(1, [], 2)]))
    finish(comp, conns)


# ----------------------------------------------------------------------
# AeroLateralCoeffs: pair=AeroCYCN top (14 left pins), cr=HL20CR bottom (14 top)
# ----------------------------------------------------------------------
LAT_ORDER = SHARED_CYCN + CN_ONLY         # identical 14 inputs


def gen_latcoeffs(src, pins):
    comp = [x for x in src if isinstance(x, lg.Component) and x.name == "AeroLateralCoeffs"][0]
    comp.set_diagram("pair", {"x1": 1600, "x2": 2700, "y1": 100, "y2": 1200})
    comp.set_diagram("cr", {"x1": 1600, "x2": 2600, "y1": 2100, "y2": 3100})
    ctx = lg.Ctx(comp, pins)
    G0, DX, DG = 2040.0, 100.0, 40.0
    conns = []
    for i, name in enumerate(LAT_ORDER):
        xc = 200 + DX * i
        g = G0 - DG * i
        comp.set_diagram(name, box(xc + 50, g))
        cr_xy = pin(ctx, "cr." + name)
        pr_xy = pin(ctx, "pair." + name)
        conns.append(mk_conn(
            [name, "pair." + name, "cr." + name],
            [E(1, [], -1),
             E(-1, [(xc, pr_xy[1])], 2),
             E(-1, [(cr_xy[0], g)], 3)],
            [(xc, g)]))
    # outputs CY<-pair.cy_y, Cn<-pair.cn_y, Cl<-cr.y
    comp.set_diagram("CY", box(3150, pin(ctx, "pair.cy_y")[1]))
    comp.set_diagram("Cn", box(3150, pin(ctx, "pair.cn_y")[1]))
    comp.set_diagram("Cl", box(3150, pin(ctx, "cr.y")[1]))
    conns.append(mk_conn(["pair.cy_y", "CY"], [E(1, [], 2)]))
    conns.append(mk_conn(["pair.cn_y", "Cn"], [E(1, [], 2)]))
    conns.append(mk_conn(["cr.y", "Cl"], [E(1, [], 2)]))
    finish(comp, conns)


# ----------------------------------------------------------------------
# AeroLongitudinal: pair=AeroCLCD top (10 left), cm=HL20CM bottom (12 top),
# alpha third leg -> deg2rad trig chain; CX/CZ/Cm compute cluster right.
# ----------------------------------------------------------------------
LON_SHARED = ["alpha_deg", "mach", "hob", "DBFLL", "DBFLR",
              "DBFUL", "DBFUR", "DWFL", "DWFR", "abs_drud"]
CM_ONLY = ["qb", "damp_c2v"]


def gen_lon(src, pins):
    comp = [x for x in src if isinstance(x, lg.Component) and x.name == "AeroLongitudinal"][0]
    # block boxes
    comp.set_diagram("pair", {"x1": 1400, "x2": 2400, "y1": 100, "y2": 1200})
    comp.set_diagram("cm", {"x1": 1400, "x2": 2400, "y1": 2100, "y2": 3100})
    comp.set_diagram("deg2rad", {"x1": 2500, "x2": 2600, "y1": 270, "y2": 370})
    comp.set_diagram("sin_a", {"x1": 2500, "x2": 2600, "y1": 570, "y2": 670})
    comp.set_diagram("cos_a", {"x1": 2500, "x2": 2600, "y1": 870, "y2": 970})
    comp.set_diagram("cl_sin", {"x1": 2900, "x2": 3000, "y1": 470, "y2": 570}, rot=0)
    comp.set_diagram("cd_sin", {"x1": 2900, "x2": 3000, "y1": 770, "y2": 870}, rot=0)
    comp.set_diagram("cd_cos", {"x1": 2900, "x2": 3000, "y1": 1170, "y2": 1270}, rot=0)
    comp.set_diagram("cl_cos", {"x1": 2900, "x2": 3000, "y1": 1470, "y2": 1570}, rot=0)
    comp.set_diagram("cx_sum", {"x1": 3300, "x2": 3400, "y1": 620, "y2": 720})
    comp.set_diagram("cz_sum", {"x1": 3300, "x2": 3400, "y1": 1320, "y2": 1420})
    ctx = lg.Ctx(comp, pins)
    G0, DX, DG = 2040.0, 100.0, 40.0
    conns = []
    order = LON_SHARED + CM_ONLY            # 12 columns
    for i, name in enumerate(order):
        xc = 200 + DX * i
        g = G0 - DG * i
        comp.set_diagram(name, box(xc + 50, g))
        cm_xy = pin(ctx, "cm." + name)
        if name in LON_SHARED:
            pr_xy = pin(ctx, "pair." + name)
            edges = [E(1, [], -1), E(-1, [(xc, pr_xy[1])], 2)]
            sinks = [cm_xy]
            if name == "alpha_deg":
                # third leg: shares the staircase riser column (same net),
                # over the top of pair, down to the trig column.  The descent
                # column stays left of deg2rad's parameter label.
                du = pin(ctx, "deg2rad.u")
                edges.append(E(-1, [(200, g), (200, 80),
                                    (2440, 80), (2440, du[1])], 4))
                conns.append(mk_conn(
                    [name, "pair." + name, "cm." + name, "deg2rad.u"],
                    edges + [E(-1, [(cm_xy[0], g)], 3)],
                    [(xc, g)]))
                continue
            edges.append(E(-1, [(cm_xy[0], g)], 3))
            conns.append(mk_conn(
                [name, "pair." + name, "cm." + name], edges, [(xc, g)]))
        else:
            conns.append(mk_conn([name, "cm." + name],
                                 [E(1, [(cm_xy[0], g)], 2)]))
    # deg2rad -> sin/cos: wrap right of deg2rad, down the pair/trig gap,
    # fan to the two left-edge u pins
    dy = pin(ctx, "deg2rad.y")
    su = pin(ctx, "sin_a.u")
    cu = pin(ctx, "cos_a.u")
    J = (2450, 470)
    conns.append(mk_conn(
        ["deg2rad.y", "sin_a.u", "cos_a.u"],
        [E(1, [(2680, dy[1]), (2680, J[1]), (J[0], J[1])], -1),
         E(-1, [(J[0], su[1])], 2),
         E(-1, [(J[0], cu[1])], 3)],
        [J]))
    # pair/trig outputs to product u pins: one trunk column per net, ordered
    # cos, cl, cd, sin left->right so taps cross the fewest trunks.  The cl
    # source jogs up left of the trig blocks to a top lane.
    cly = pin(ctx, "pair.cl_y"); cdy = pin(ctx, "pair.cd_y")
    cs_u1 = pin(ctx, "cl_sin.u1"); cc_u1 = pin(ctx, "cl_cos.u1")
    dc_u1 = pin(ctx, "cd_cos.u1"); ds_u1 = pin(ctx, "cd_sin.u1")
    cs_u2 = pin(ctx, "cl_sin.u2"); cc_u2 = pin(ctx, "cl_cos.u2")
    dc_u2 = pin(ctx, "cd_cos.u2"); ds_u2 = pin(ctx, "cd_sin.u2")
    conns.append(mk_conn(
        ["cos_a.y", "cd_cos.u2", "cl_cos.u2"],
        [E(1, [], -1),
         E(-1, [(2820, dc_u2[1])], 2),
         E(-1, [(2820, cc_u2[1])], 3)],
        [(2820, pin(ctx, "cos_a.y")[1])]))
    conns.append(mk_conn(
        ["pair.cl_y", "cl_sin.u1", "cl_cos.u1"],
        [E(1, [(2410, cly[1]), (2410, 460), (2840, 460)], -1),
         E(-1, [(2840, cs_u1[1])], 2),
         E(-1, [(2840, cc_u1[1])], 3)],
        [(2840, 460)]))
    conns.append(mk_conn(
        ["pair.cd_y", "cd_cos.u1", "cd_sin.u1"],
        [E(1, [], -1),
         E(-1, [(2860, dc_u1[1])], 2),
         E(-1, [(2860, ds_u1[1])], 3)],
        [(2860, cdy[1])]))
    sy = pin(ctx, "sin_a.y")
    conns.append(mk_conn(
        ["sin_a.y", "cl_sin.u2", "cd_sin.u2"],
        [E(1, [], -1),
         E(-1, [(2880, cs_u2[1])], 2),
         E(-1, [(2880, ds_u2[1])], 3)],
        [(2880, sy[1])]))
    # products -> sums -> outputs
    comp.set_diagram("CX", box(4300, pin(ctx, "cx_sum.y")[1]))
    comp.set_diagram("CZ", box(4300, pin(ctx, "cz_sum.y")[1]))
    conns.append(mk_conn(["cl_sin.y", "cx_sum.u1"],
                         [E(1, [(3200, pin(ctx, "cl_sin.y")[1]),
                                 (3200, pin(ctx, "cx_sum.u1")[1])], 2)]))
    conns.append(mk_conn(["cd_cos.y", "cx_sum.u2"],
                         [E(1, [(3240, pin(ctx, "cd_cos.y")[1]),
                                 (3240, pin(ctx, "cx_sum.u2")[1])], 2)]))
    conns.append(mk_conn(["cl_cos.y", "cz_sum.u1"],
                         [E(1, [(3200, pin(ctx, "cl_cos.y")[1]),
                                 (3200, pin(ctx, "cz_sum.u1")[1])], 2)]))
    conns.append(mk_conn(["cd_sin.y", "cz_sum.u2"],
                         [E(1, [(3180, pin(ctx, "cd_sin.y")[1]),
                                 (3180, pin(ctx, "cz_sum.u2")[1])], 2)]))
    conns.append(mk_conn(["cx_sum.y", "CX"], [E(1, [], 2)]))
    conns.append(mk_conn(["cz_sum.y", "CZ"], [E(1, [], 2)]))
    # cm.y -> Cm: straight across; nothing occupies the row
    comp.set_diagram("Cm", box(4300, pin(ctx, "cm.y")[1]))
    conns.append(mk_conn(["cm.y", "Cm"], [E(1, [], 2)]))
    finish(comp, conns)


# ----------------------------------------------------------------------
# HL20Aero: lon=AeroLongitudinal top (12 left), lat=AeroLateralCoeffs bottom
# (14 top), air=AeroAirData bottom-left fed via far-left channel.
# ----------------------------------------------------------------------
AERO_SHARED = ["alpha_deg", "mach", "hob", "DBFLL", "DBFLR",
               "DBFUL", "DBFUR", "DWFL", "DWFR"]           # lon+lat
AERO_LON_ONLY = ["qb"]
AERO_LAT_ONLY = ["beta_deg", "pb", "rb"]
# lat top-pin order: air-fed first (leftmost), then staircase order
LAT_TOP_ORDER = (["abs_drud", "damp_b2v"] + AERO_SHARED + AERO_LAT_ONLY)
# lon left-pin order: air-fed topmost, then staircase, then qb
LON_LEFT_ORDER = (["abs_drud", "damp_c2v"] + AERO_SHARED + AERO_LON_ONLY)


def gen_hl20aero(src, pins):
    comp = [x for x in src if isinstance(x, lg.Component) and x.name == "HL20Aero"][0]
    comp.set_diagram("lon", {"x1": 1700, "x2": 2800, "y1": 100, "y2": 1250})
    comp.set_diagram("lat", {"x1": 1700, "x2": 2800, "y1": 2300, "y2": 3400})
    comp.set_diagram("air", {"x1": 450, "x2": 1150, "y1": 3450, "y2": 4150})
    ctx = lg.Ctx(comp, pins)
    G0, DX, DG = 2040.0, 100.0, 40.0
    conns = []
    cols = AERO_SHARED + AERO_LON_ONLY + AERO_LAT_ONLY   # 13 columns
    for i, name in enumerate(cols):
        xc = 200 + DX * i
        g = G0 - DG * i
        comp.set_diagram(name, box(xc + 50, g))
        to_lat = name in (AERO_SHARED + AERO_LAT_ONLY)
        to_lon = name in (AERO_SHARED + AERO_LON_ONLY)
        lat_xy = pin(ctx, "lat." + name) if to_lat else None
        if to_lon and to_lat:
            lon_xy = pin(ctx, "lon." + name)
            conns.append(mk_conn(
                [name, "lon." + name, "lat." + name],
                [E(1, [], -1),
                 E(-1, [(xc, lon_xy[1])], 2),
                 E(-1, [(lat_xy[0], g)], 3)],
                [(xc, g)]))
        elif to_lon:
            lon_xy = pin(ctx, "lon." + name)
            conns.append(mk_conn(
                [name, "lon." + name],
                [E(1, [(xc, g), (xc, lon_xy[1])], 2)]))
        else:
            conns.append(mk_conn(
                [name, "lat." + name],
                [E(1, [(lat_xy[0], g)], 2)]))
    # air inputs sit on the bottom edge; ports drop straight in from below
    for name in ["vrw_fps", "DRUD"]:
        axy = pin(ctx, "air." + name)
        comp.set_diagram(name, box(axy[0], 4260))
        conns.append(mk_conn([name, "air." + name], [E(1, [], 2)]))
    # air outputs leave the left edge.  damp_c2v (topmost pin) rises in the
    # narrow channel just inside the outer-wire tolerance, left of every
    # staircase column, straight to lon's lower air pin.  abs_drud runs under
    # the diagram: a descent column just right of the comb, a long under-run
    # to a riser right of the output ports for the lon leg, and a lat tap
    # that rises in the empty gap between the comb and lat.  damp_b2v
    # under-runs one lane higher and reaches its lat pin via the same gap.
    aabs = pin(ctx, "air.abs_drud")
    adb = pin(ctx, "air.damp_b2v")
    adc = pin(ctx, "air.damp_c2v")
    labs = pin(ctx, "lat.abs_drud")
    ldb = pin(ctx, "lat.damp_b2v")
    labs_lon = pin(ctx, "lon.abs_drud")
    ldc_lon = pin(ctx, "lon.damp_c2v")
    conns.append(mk_conn(
        ["air.damp_c2v", "lon.damp_c2v"],
        [E(1, [(195, adc[1]), (195, ldc_lon[1])], 2)]))
    conns.append(mk_conn(
        ["air.abs_drud", "lon.abs_drud", "lat.abs_drud"],
        [E(1, [(205, aabs[1]), (205, 4310)], -1),
         E(-1, [(191, labs_lon[1])], 2),
         E(-1, [(1650, 4310), (1650, 2280), (labs[0], 2280)], 3)],
        [(191, 4310)]))
    conns.append(mk_conn(
        ["air.damp_b2v", "lat.damp_b2v"],
        [E(1, [(215, adb[1]), (215, 4300), (1600, 4300), (1600, 2110),
               (ldb[0], 2110)], 2)]))
    # outputs
    for out, ep in [("CX", "lon.CX"), ("CZ", "lon.CZ"), ("Cm", "lon.Cm"),
                    ("CY", "lat.CY"), ("Cl", "lat.Cl"), ("Cn", "lat.Cn")]:
        comp.set_diagram(out, box(3350, pin(ctx, ep)[1]))
        conns.append(mk_conn([ep, out], [E(1, [], 2)]))
    finish(comp, conns)


# ----------------------------------------------------------------------
def main():
    pins = lg.library_pins(LIB)

    # ---- child icon re-pins --------------------------------------------
    # AeroLateral.dyad: HL20CY -> 11 left pins; HL20CN, HL20CR -> 14 top pins
    src = lg.load_file(f"{LIB}/shared/AeroLateral.dyad")
    for x in src:
        if isinstance(x, lg.Component) and x.name == "HL20CY":
            repin_inputs(x, SHARED_CYCN, "left")
        elif isinstance(x, lg.Component) and x.name == "HL20CN":
            repin_inputs(x, SHARED_CYCN + CN_ONLY, "top")
        elif isinstance(x, lg.Component) and x.name == "HL20CR":
            repin_inputs(x, SHARED_CYCN + CN_ONLY, "top")
    lg.save_file(f"{LIB}/shared/AeroLateral.dyad", src)

    # AeroCoefficients.dyad: HL20CM -> 12 top pins
    src = lg.load_file(f"{LIB}/shared/AeroCoefficients.dyad")
    for x in src:
        if isinstance(x, lg.Component) and x.name == "HL20CM":
            repin_inputs(x, LON_SHARED + CM_ONLY, "top")
    lg.save_file(f"{LIB}/shared/AeroCoefficients.dyad", src)

    # AeroGroups.dyad: AeroCYCN -> 14 left pins (icon for `pair`);
    # AeroLateralCoeffs -> 14 top pins (icon for `lat`);
    # AeroLongitudinal -> 12 left pins (icon for `lon`)
    src = lg.load_file(f"{LIB}/shared/AeroGroups.dyad")
    for x in src:
        if isinstance(x, lg.Component) and x.name == "AeroCYCN":
            repin_inputs(x, SHARED_CYCN + CN_ONLY, "left")
        elif isinstance(x, lg.Component) and x.name == "AeroLateralCoeffs":
            repin_inputs(x, LAT_TOP_ORDER, "top")
        elif isinstance(x, lg.Component) and x.name == "AeroLongitudinal":
            repin_inputs(x, LON_LEFT_ORDER, "left")
        elif isinstance(x, lg.Component) and x.name == "AeroAirData":
            # outputs leave the left edge ordered so each exit wire clears
            # the others' descent columns; inputs enter the bottom edge
            x.set_icon("damp_c2v", icon_left(50))
            x.set_icon("abs_drud", icon_left(200))
            x.set_icon("damp_b2v", icon_left(350))
            x.set_icon("vrw_fps", icon_bottom(250))
            x.set_icon("DRUD", icon_bottom(750))
    lg.save_file(f"{LIB}/shared/AeroGroups.dyad", src)

    # pins map must be rebuilt off the saved files before diagram gen
    # (library_pins caches in _LIB_CACHE; the repin above changed icons)
    lg._LIB_CACHE.clear()
    pins = lg.library_pins(LIB)
    src = lg.load_file(f"{LIB}/shared/AeroGroups.dyad")
    gen_cycn(src, pins)
    gen_latcoeffs(src, pins)
    gen_lon(src, pins)
    lg.save_file(f"{LIB}/shared/AeroGroups.dyad", src)

    # HL20Aero.dyad
    src = lg.load_file(f"{LIB}/shared/HL20Aero.dyad")
    pins = lg.library_pins(LIB)
    gen_hl20aero(src, pins)
    lg.save_file(f"{LIB}/shared/HL20Aero.dyad", src)


def check():
    """--check: regenerate and exit non-zero if committed files drift."""
    from pathlib import Path
    targets = [f"{LIB}/shared/{n}.dyad" for n in
               ("AeroLateral", "AeroCoefficients", "AeroGroups", "HL20Aero")]
    bak = {t: Path(t).read_bytes() for t in targets}
    try:
        main()
    finally:
        bad = [t for t, b in bak.items() if Path(t).read_bytes() != b]
        for t, b in bak.items():
            Path(t).write_bytes(b)
    for t in bad:
        print(f"DRIFT: {t}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    if "--check" in sys.argv[1:]:
        check()
    else:
        main()
