# ============================================================================
# Shared utilities — available to both golden and agent workspaces.
# ============================================================================
# Pre-provided HL-20 aero table infrastructure:
#   - Lazy DAVE-ML data loading (HL20_aero.dml, atmos_76.dml in assets/shared/)
#   - Registered symbolic functions called from HL20Aero.dyad
#   - Index accessors evaluated at model-construction time (baked as constants)
#
# `HL20Aero.dyad` is provided pre-built in dyad/shared/. The agent uses these
# functions but does not need to reimplement the table parsing or the
# coefficient buildup. See `assets/shared/hl20_spec.md` §7 for the interface.
# ============================================================================

using EzXML
using Interpolations
using Symbolics
using ModelingToolkit: @register_symbolic

# ----- Lazy data loading ---------------------------------------------------

const _HL20 = Ref{Any}(nothing)
# DML files may be at assets/shared/ (source layout) or assets/ (container layout)
const _DML_DIR = let
    shared = joinpath(@__DIR__, "..", "assets", "shared")
    root = joinpath(@__DIR__, "..", "assets")
    isfile(joinpath(shared, "HL20_aero.dml")) ? shared : root
end

function _data()
    _HL20[] === nothing && (_HL20[] = _load())
    return _HL20[]
end

# ----- DML parsing ---------------------------------------------------------

function _load()
    ar = root(readxml(joinpath(_DML_DIR, "atmos_76.dml")))
    Z = _bpvals(ar, "Z_m_pts")
    sig = _tbldata(ar, "sigma_table")
    T_C = _tbldata(ar, "T_dgC_table")
    vs = [49.02 * sqrt(tc * 9/5 + 32 + 459.67) for tc in T_C]

    xr = root(readxml(joinpath(_DML_DIR, "HL20_aero.dml")))

    bps = Dict{String,Vector{Float64}}()
    for bp in findall("//breakpointDef", xr)
        bps[bp["bpID"]] = _parsefloats(nodecontent(findfirst("bpVals", bp)))
    end

    i1d = Dict{String,Any}()
    i2d = Dict{String,Any}()
    refs = Dict{String,String}()
    stbl = Dict{String,Any}()

    for f in findall("//function", xr)
        dep = findfirst("dependentVarRef", f); dep === nothing && continue
        fd = findfirst("functionDefn", f); fd === nothing && continue
        vid = dep["varID"]
        gt = findfirst("griddedTable", fd)
        if gt !== nothing
            bids = [b["bpID"] for b in findall("breakpointRefs/bpRef", gt)]
            d = _parsefloats(nodecontent(findfirst("dataTable", gt)))
            if length(bids) == 1
                i1d[vid] = _interp1d(bps[bids[1]], d)
            else
                i2d[vid] = _interp2d(bps[bids[1]], bps[bids[2]], d)
            end
        end
        gtr = findfirst("griddedTableRef", fd)
        gtr !== nothing && (refs[vid] = gtr["gtID"])
    end

    for gt in findall("//griddedTableDef", xr)
        bids = [b["bpID"] for b in findall("breakpointRefs/bpRef", gt)]
        d = _parsefloats(nodecontent(findfirst("dataTable", gt)))
        stbl[gt["gtID"]] = _interp2d(bps[bids[1]], bps[bids[2]], d)
    end

    k1 = sort(collect(keys(i1d)))
    k2e = sort(collect(keys(i2d)))
    k2r = sort(collect(keys(refs)))

    return (;
        atm_sig = _interp1d(Z, sig), atm_vs = _interp1d(Z, vs),
        i1d, i2d, stbl, refs,
        k1, k2e, k2r,
        ki1 = Dict(k => i for (i,k) in enumerate(k1)),
        ki2e = Dict(k => i for (i,k) in enumerate(k2e)),
        ki2r = Dict(k => i for (i,k) in enumerate(k2r)),
    )
end

_parsefloats(s) = parse.(Float64, filter(!isempty, split(replace(replace(strip(s), r"<!--[^>]*-->" => ""), "," => " "))))
_bpvals(r, id) = _parsefloats(nodecontent(findfirst("bpVals", findfirst("//breakpointDef[@bpID='$id']", r))))
function _tbldata(r, id)
    gt = findfirst("//griddedTableDef[@gtID='$id']", r)
    _parsefloats(nodecontent(findfirst("dataTable", gt)))
end
_interp1d(bp, d) = linear_interpolation(bp, d, extrapolation_bc=Flat())
function _interp2d(bp1, bp2, d)
    linear_interpolation((bp1, bp2), reshape(d, length(bp2), length(bp1))', extrapolation_bc=Flat())
end

# ----- Registered symbolic functions (called from HL20Aero.dyad) -----------

function hl20_poly1d(group_idx, alpha, x)
    d = _data(); gi = Int(group_idx)
    c0=d.i1d[d.k1[gi]](x); c1=d.i1d[d.k1[gi+1]](x)
    c2=d.i1d[d.k1[gi+2]](x); c3=d.i1d[d.k1[gi+3]](x)
    c0 + alpha * (c1 + alpha * (c2 + alpha * c3))
end
@register_symbolic hl20_poly1d(group_idx, alpha, x)

function hl20_poly2dr(group_idx, alpha, defl, mach)
    d = _data(); gi = Int(group_idx)
    c(n) = d.stbl[d.refs[d.k2r[gi+n]]](defl, mach)
    c(0) + alpha * (c(1) + alpha * (c(2) + alpha * c(3)))
end
@register_symbolic hl20_poly2dr(group_idx, alpha, defl, mach)

function hl20_poly2de(group_idx, alpha, defl, mach)
    d = _data(); gi = Int(group_idx)
    c(n) = d.i2d[d.k2e[gi+n]](defl, mach)
    c(0) + alpha * (c(1) + alpha * (c(2) + alpha * c(3)))
end
@register_symbolic hl20_poly2de(group_idx, alpha, defl, mach)

# ----- Index accessors (model-construction time, return constants) ---------
# Accept either the exact varID ("CL0A0", "CLGE0") or the group prefix
# ("CL0A", "CLGE") — the latter resolves to the start of the 4-coefficient
# polynomial group (`prefix * "0"`).

function _resolve(d::Dict, varID::String)
    haskey(d, varID)       && return d[varID]
    haskey(d, varID * "0") && return d[varID * "0"]
    error("Unknown HL-20 aero table varID: $varID")
end
idx1d(varID::String)  = _resolve(_data().ki1,  varID)
idx2de(varID::String) = _resolve(_data().ki2e, varID)
idx2dr(varID::String) = _resolve(_data().ki2r, varID)
grp2dr(prefix::String) = _data().ki2r[prefix * "0"]
grp2de(prefix::String) = _data().ki2e[prefix * "0"]
