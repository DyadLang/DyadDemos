# Fit the four-parameter magic-formula factors (B, C, D, E) used by
# PacejkaWheelJoint to the full Pac02 tire property file shipped with the sedan
# model (assets/sedan/Sedan_Pac02Tire.tir).
#
# PacejkaWheelJoint evaluates `pacejka_magic(B, C, D, E, v_slip)` on slip
# *velocities* (m/s), while the Pac02 file is parameterized in slip ratio kappa
# and slip angle alpha. The two domains are related through a reference speed:
#   v_slip_long = kappa * V0,   v_slip_lat = tan(alpha) * V0,
# with V0 = LONGVL from the .tir file. The fit therefore reproduces the Pac02
# pure-slip curves exactly at forward speed V0 and approximates them at other
# speeds (the effective slip stiffness scales with speed).
#
# Pure-slip Pac02 curves are evaluated at the sedan's static corner load with
# the .tir scaling factor LFZO applied to the nominal load, and the horizontal/
# vertical offsets (S_h, S_v: plysteer/conicity) dropped, since the magic
# formula in PacejkaWheelJoint is strictly odd. The road friction coefficient
# scales the peak factor as mu_road/mu0 (Chrono convention), with mu0 the
# tire's own "Coefficient of Friction" (0.8 in Sedan_Pac02Tire.json).
#
# Run:  julia --project=scripts scripts/fit_tire.jl

using LinearAlgebra
using Printf

# ---------------------------------------------------------------------------
# Parse the .tir file
# ---------------------------------------------------------------------------
tirfile = normpath(joinpath(@__DIR__, "..", "assets", "sedan", "Sedan_Pac02Tire.tir"))
tir = Dict{String, Float64}()
for line in eachline(tirfile)
    line = strip(first(split(line, r"[!$]"))) # strip comments
    m = match(r"^([A-Z0-9_]+)\s*=\s*([-+0-9.eE]+)", line)
    m === nothing && continue
    tir[m.captures[1]] = parse(Float64, m.captures[2])
end

V0    = tir["LONGVL"]           # reference forward speed [m/s]
FNOMIN = tir["FNOMIN"]
LFZO  = tir["LFZO"]
Fz0p  = LFZO * FNOMIN           # scaled nominal load

# Static corner load of the sedan (all four corners equal: chassis COM is at
# mid-wheelbase). Chassis 1550 + rack 1.889 + 4 x (spindle 1.103 + upright
# 1.397 + UCA 1.032 + LCA 1.611 + wheel 13.2 + tire 11.5).
m_total = 1550.0 + 1.889 + 4 * (1.103 + 1.397 + 1.032 + 1.611 + 13.2 + 11.5)
Fz = m_total * 9.80665 / 4
@printf "Total vehicle mass %.1f kg, static corner load Fz = %.1f N\n" m_total Fz

mu0     = 0.8    # tire "Coefficient of Friction" from Sedan_Pac02Tire.json
mu_road = 0.9    # terrain friction of the validation runs (RigidPlane.json)
mu_scale = mu_road / mu0

dfz = (Fz - Fz0p) / Fz0p

# ---------------------------------------------------------------------------
# Pac02 pure-slip curves (no camber, offsets dropped)
# ---------------------------------------------------------------------------
function fx_pac02(kappa)
    Cx = tir["PCX1"]
    mux = (tir["PDX1"] + tir["PDX2"] * dfz) * mu_scale
    Dx = mux * Fz
    Ex = min((tir["PEX1"] + tir["PEX2"] * dfz + tir["PEX3"] * dfz^2) *
             (1 - tir["PEX4"] * sign(kappa)), 1.0)
    Kx = Fz * (tir["PKX1"] + tir["PKX2"] * dfz) * exp(tir["PKX3"] * dfz)
    Bx = Kx / (Cx * Dx)
    Bk = Bx * kappa
    Dx * sin(Cx * atan(Bk - Ex * (Bk - atan(Bk))))
end

function fy_pac02(alpha)
    Cy = tir["PCY1"]
    muy = (tir["PDY1"] + tir["PDY2"] * dfz) * mu_scale
    Dy = muy * Fz
    Ey = min((tir["PEY1"] + tir["PEY2"] * dfz) * (1 - tir["PEY3"] * sign(alpha)), 1.0)
    Ky = tir["PKY1"] * Fz0p * sin(2 * atan(Fz / (tir["PKY2"] * Fz0p)))
    By = Ky / (Cy * Dy)
    Ba = By * alpha
    Dy * sin(Cy * atan(Ba - Ey * (Ba - atan(Ba))))
end

# ---------------------------------------------------------------------------
# Least-squares fit of pacejka_magic(B,C,D,E,v) to mu(v) samples
# ---------------------------------------------------------------------------
pacejka_magic(B, C, D, E, x) = D * sin(C * atan(B * x - E * (B * x - atan(B * x))))

function fit_magic(vs, mus, p0)
    p = collect(p0)
    resid(p) = [pacejka_magic(p..., v) - mu for (v, mu) in zip(vs, mus)]
    for _ in 1:200
        r = resid(p)
        J = zeros(length(r), 4)
        for j in 1:4
            dp = max(1e-6, 1e-6 * abs(p[j]))
            pj = copy(p); pj[j] += dp
            J[:, j] = (resid(pj) - r) / dp
        end
        step = -(J' * J + 1e-10I) \ (J' * r)
        # backtracking line search
        c0 = norm(r)
        t = 1.0
        while norm(resid(p + t * step)) > c0 && t > 1e-6
            t /= 2
        end
        p += t * step
        norm(t * step) < 1e-12 && break
    end
    rms = norm(resid(p)) / sqrt(length(vs))
    p, rms
end

# Longitudinal: kappa in (0, 0.6] -> v_slip_long = kappa * V0
kappas = range(0.002, 0.6, length = 300)
v_long = kappas .* V0
mu_long = fx_pac02.(kappas) ./ Fz
# slope-based initial guess: d(mu)/dv at 0 = B*C*D
Kx = Fz * (tir["PKX1"] + tir["PKX2"] * dfz) * exp(tir["PKX3"] * dfz)
Dx0 = (tir["PDX1"] + tir["PDX2"] * dfz) * mu_scale
Bx0 = (Kx / Fz / V0) / (tir["PCX1"] * Dx0)
(px, rms_x) = fit_magic(v_long, mu_long, (Bx0, tir["PCX1"], Dx0, 0.5))

# Lateral: alpha in (0, 15 deg] -> v_slip_lat = tan(alpha) * V0.
# fy_pac02 < 0 for alpha > 0 (ISO convention); PacejkaWheelJoint applies the
# force as -f_n*mu_y*e_lat (opposing slip), so fit the magnitude.
alphas = range(0.001, deg2rad(15), length = 300)
v_lat = tan.(alphas) .* V0
mu_lat = -fy_pac02.(alphas) ./ Fz
Ky = tir["PKY1"] * Fz0p * sin(2 * atan(Fz / (tir["PKY2"] * Fz0p)))
Dy0 = (tir["PDY1"] + tir["PDY2"] * dfz) * mu_scale
By0 = (-Ky / Fz / V0) / (tir["PCY1"] * Dy0)
(py, rms_y) = fit_magic(v_lat, mu_lat, (By0, tir["PCY1"], Dy0, 0.5))

@printf "\nLongitudinal fit (kappa <= 0.6, V0 = %.1f m/s):\n" V0
@printf "  Bx = %.6g\n  Cx = %.6g\n  Dx = %.6g\n  Ex = %.6g\n  RMS = %.2e (mu units)\n" px... rms_x
@printf "\nLateral fit (alpha <= 15 deg, V0 = %.1f m/s):\n" V0
@printf "  By = %.6g\n  Cy = %.6g\n  Dy = %.6g\n  Ey = %.6g\n  RMS = %.2e (mu units)\n" py... rms_y

# Peak-location sanity check
vpx = v_long[argmax(mu_long)]
vpy = v_lat[argmax(mu_lat)]
@printf "\nPac02 peaks: mu_x %.4f at v %.2f m/s (kappa %.3f); mu_y %.4f at v %.2f m/s (alpha %.1f deg)\n" maximum(mu_long) vpx vpx/V0 maximum(mu_lat) vpy rad2deg(atan(vpy/V0))
@printf "Fitted peaks: mu_x %.4f, mu_y %.4f\n" maximum(pacejka_magic.(px..., v_long)) maximum(pacejka_magic.(py..., v_lat))
