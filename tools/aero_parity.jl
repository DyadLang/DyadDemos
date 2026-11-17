# aero_parity.jl — compare the graphical HL20Aero outputs against the spec
# equations (transcribed from the equation-level component at fbed9dc).
#
# usage: julia aero_parity.jl LIBDIR inputs.csv report.txt
#   Evaluates HL20Demo.shared.HL20Aero via eval_component.jl machinery and
#   prints max |model - reference| per output over all input rows.

using Pkg
Pkg.activate(ARGS[1])
using HL20Demo
using CSV, DataFrames, Printf

inputs_csv = ARGS[2]
report = ARGS[3]
eval_csv = joinpath(dirname(inputs_csv), "aero_parity_eval.csv")

# reuse the evaluator
include(joinpath(@__DIR__, "eval_component_run.jl"))

run_eval("HL20Demo.shared.HL20Aero", inputs_csv, eval_csv)

df = CSV.read(eval_csv, DataFrame)
indf = CSV.read(inputs_csv, DataFrame)

function aero_ref(alpha_deg, beta_deg, mach, vrw_fps, hob, pb, qb, rb,
                  DBFUL, DBFUR, DBFLL, DBFLR, DWFL, DWFR, DRUD;
                  DLG=0.0, CBAR_ft=28.24, BSPAN_ft=13.89, Cm_bias=0.006449,
                  CMQ0=-0.22364, CMQ1=0.020457, CMQ2=-0.0016741, CMQ3=0.000031618,
                  CNP0=0.40031, CNP1=-0.015518, CNP2=-0.00012143, CNP3=0.000018240,
                  CNR0=-0.79533, CNR1=-0.012647, CNR2=0.00032696, CNR3=-0.0000065929,
                  CLP0=-0.55242, CLP1=0.014478, CLP2=-0.0011545, CLP3=0.000017706,
                  CLR0=0.44685, CLR1=0.067411, CLR2=-0.0051866, CLR3=0.00012659)
    p1d = HL20Demo.hl20_poly1d; p2dr = HL20Demo.hl20_poly2dr; p2de = HL20Demo.hl20_poly2de
    i1d = HL20Demo.idx1d; g2dr = HL20Demo.grp2dr; g2de = HL20Demo.grp2de
    alpha_r = alpha_deg * 0.017453292519943295
    cos_alpha = cos(alpha_r); sin_alpha = sin(alpha_r)
    abs_drud = abs(DRUD)
    damp_b2v = BSPAN_ft / (2.0 * (vrw_fps + 0.1))
    damp_c2v = CBAR_ft / (2.0 * (vrw_fps + 0.1))

    CL_base = p1d(i1d("CL0A"), alpha_deg, mach) + p1d(i1d("CLGE"), alpha_deg, hob) + p1d(i1d("CLLG"), alpha_deg, DLG)
    CL_bfl = p2dr(g2dr("CLBFLL"), alpha_deg, DBFLL, mach) + p2dr(g2dr("CLBFLR"), alpha_deg, DBFLR, mach)
    CL_bfu = p2dr(g2dr("CLBFUL"), alpha_deg, DBFUL, mach) + p2dr(g2dr("CLBFUR"), alpha_deg, DBFUR, mach)
    CL_wf = p2dr(g2dr("CLWFL"), alpha_deg, DWFL, mach) + p2dr(g2dr("CLWFR"), alpha_deg, DWFR, mach)
    CL_rud = p2de(g2de("CLRUD"), alpha_deg, abs_drud, mach)
    CL_total = CL_base + CL_bfl + CL_bfu + CL_wf + CL_rud

    CD_base = p1d(i1d("CD0A"), alpha_deg, mach) + p1d(i1d("CDGE"), alpha_deg, hob) + p1d(i1d("CDLG"), alpha_deg, DLG)
    CD_bfl = p2dr(g2dr("CDBFLL"), alpha_deg, DBFLL, mach) + p2dr(g2dr("CDBFLR"), alpha_deg, DBFLR, mach)
    CD_bfu = p2dr(g2dr("CDBFUL"), alpha_deg, DBFUL, mach) + p2dr(g2dr("CDBFUR"), alpha_deg, DBFUR, mach)
    CD_wf = p2dr(g2dr("CDWFL"), alpha_deg, DWFL, mach) + p2dr(g2dr("CDWFR"), alpha_deg, DWFR, mach)
    CD_rud = p2de(g2de("CDRUD"), alpha_deg, abs_drud, mach)
    CD_total = CD_base + CD_bfl + CD_bfu + CD_wf + CD_rud

    CM_base = p1d(i1d("CM0A"), alpha_deg, mach) + p1d(i1d("CMGE"), alpha_deg, hob) + p1d(i1d("CMLG"), alpha_deg, DLG)
    CM_bfl = p2dr(g2dr("CMBFLL"), alpha_deg, DBFLL, mach) + p2dr(g2dr("CMBFLR"), alpha_deg, DBFLR, mach)
    CM_bfu = p2dr(g2dr("CMBFUL"), alpha_deg, DBFUL, mach) + p2dr(g2dr("CMBFUR"), alpha_deg, DBFUR, mach)
    CM_wf = p2dr(g2dr("CMWFL"), alpha_deg, DWFL, mach) + p2dr(g2dr("CMWFR"), alpha_deg, DWFR, mach)
    CM_rud = p2de(g2de("CMRUD"), alpha_deg, abs_drud, mach)
    CM_damp = (CMQ0 + CMQ1*alpha_deg + CMQ2*alpha_deg^2 + CMQ3*alpha_deg^3) * qb * damp_c2v
    CM_total = CM_base + CM_bfl + CM_bfu + CM_wf + CM_rud + CM_damp + Cm_bias

    CY_base = (p1d(i1d("CY0A"), alpha_deg, mach) + p1d(i1d("CYGE"), alpha_deg, hob) + p1d(i1d("CYLG"), alpha_deg, DLG)) * beta_deg
    CY_bfl = p2dr(g2dr("CYBFLL"), alpha_deg, DBFLL, mach) - p2dr(g2dr("CYBFLR"), alpha_deg, DBFLR, mach)
    CY_bfu = p2dr(g2dr("CYBFUL"), alpha_deg, DBFUL, mach) - p2dr(g2dr("CYBFUR"), alpha_deg, DBFUR, mach)
    CY_wf = p2dr(g2dr("CYWFL"), alpha_deg, DWFL, mach) - p2dr(g2dr("CYWFR"), alpha_deg, DWFR, mach)
    CY_rud = p2de(g2de("CYRUD"), alpha_deg, abs_drud, mach)
    CY_total = CY_base + CY_bfl + CY_bfu + CY_wf + CY_rud

    CN_base = (p1d(i1d("CN0A"), alpha_deg, mach) + p1d(i1d("CNGE"), alpha_deg, hob) + p1d(i1d("CNLG"), alpha_deg, DLG)) * beta_deg
    CN_bfl = p2dr(g2dr("CNBFLL"), alpha_deg, DBFLL, mach) - p2dr(g2dr("CNBFLR"), alpha_deg, DBFLR, mach)
    CN_bfu = p2dr(g2dr("CNBFUL"), alpha_deg, DBFUL, mach) - p2dr(g2dr("CNBFUR"), alpha_deg, DBFUR, mach)
    CN_wf = p2dr(g2dr("CNWFL"), alpha_deg, DWFL, mach) - p2dr(g2dr("CNWFR"), alpha_deg, DWFR, mach)
    CN_rud = p2de(g2de("CNRUD"), alpha_deg, abs_drud, mach)
    CN_damp = (CNP0 + CNP1*alpha_deg + CNP2*alpha_deg^2 + CNP3*alpha_deg^3) * pb * damp_b2v +
              (CNR0 + CNR1*alpha_deg + CNR2*alpha_deg^2 + CNR3*alpha_deg^3) * rb * damp_b2v
    CN_total = CN_base + CN_bfl + CN_bfu + CN_wf + CN_rud + CN_damp

    CR_base = (p1d(i1d("CR0A"), alpha_deg, mach) + p1d(i1d("CRGE"), alpha_deg, hob) + p1d(i1d("CRLG"), alpha_deg, DLG)) * beta_deg
    CR_bfl = p2dr(g2dr("CRBFLL"), alpha_deg, DBFLL, mach) - p2dr(g2dr("CRBFLR"), alpha_deg, DBFLR, mach)
    CR_bfu = p2dr(g2dr("CRBFUL"), alpha_deg, DBFUL, mach) - p2dr(g2dr("CRBFUR"), alpha_deg, DBFUR, mach)
    CR_wf = p2dr(g2dr("CRWFL"), alpha_deg, DWFL, mach) - p2dr(g2dr("CRWFR"), alpha_deg, DWFR, mach)
    CR_rud = p2de(g2de("CRRUD"), alpha_deg, abs_drud, mach)
    CR_damp = (CLP0 + CLP1*alpha_deg + CLP2*alpha_deg^2 + CLP3*alpha_deg^3) * pb * damp_b2v +
              (CLR0 + CLR1*alpha_deg + CLR2*alpha_deg^2 + CLR3*alpha_deg^3) * rb * damp_b2v
    CR_total = CR_base + CR_bfl + CR_bfu + CR_wf + CR_rud + CR_damp

    CX = CL_total * sin_alpha - CD_total * cos_alpha
    CZ = -CL_total * cos_alpha - CD_total * sin_alpha
    (CX, CY_total, CZ, CR_total, CM_total, CN_total)
end

outs = ["CX", "CY", "CZ", "Cl", "Cm", "Cn"]
incols = ["alpha_deg","beta_deg","mach","vrw_fps","hob","pb","qb","rb",
          "DBFUL","DBFUR","DBFLL","DBFLR","DWFL","DWFR","DRUD"]
ncases = size(df, 1)
maxdiff = Dict(o => -1.0 for o in outs)
nonfinite = Dict(o => 0 for o in outs)
open(report, "w") do io
    for r in 1:ncases
        args = [indf[r, c] for c in incols]
        ref = aero_ref(args...)
        for (i, o) in enumerate(outs)
            got = df[r, "$(o)(t)"]
            d = abs(got - ref[i])
            if !isfinite(d)
                nonfinite[o] += 1
            elseif d > maxdiff[o]
                maxdiff[o] = d
            end
        end
    end
    for o in outs
        @printf(io, "%s  max |model - spec| = %.3e over %d cases\n", o, maxdiff[o], ncases)
        nonfinite[o] > 0 &&
            @printf(io, "%s  %d NON-FINITE results\n", o, nonfinite[o])
    end
    worst = maximum(values(maxdiff))
    nbad = sum(values(nonfinite))
    if ncases == 0
        println(io, "PARITY FAIL: no result rows")
    elseif nbad > 0
        println(io, "PARITY FAIL: $nbad non-finite results")
    else
        println(io, worst <= 1e-12 ? "PARITY OK" : "PARITY FAIL")
    end
end
println(read(report, String))
ncases == 0 && error("parity check produced no result rows")
sum(values(nonfinite)) > 0 && error("parity check produced non-finite results")
maximum(values(maxdiff)) <= 1e-12 || error("parity check failed: worst |model - spec| = $(maximum(values(maxdiff)))")
