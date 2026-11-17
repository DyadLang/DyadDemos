# eval_component_run.jl — reusable numeric evaluator for algebraic Dyad components.
# Provides run_eval(qualified_name, inputs_csv, outputs_csv); the HL20Demo
# project must already be activated.
#
# Only for purely algebraic components (feed-forward through the connect
# graph): after binding the input ports, iterating the equations resolves all
# unknowns. Dynamic components (integrators/derivatives) are rejected.

using HL20Demo
using ModelingToolkit, Symbolics
using CSV, DataFrames

function resolve_comp(path)
    c = getfield(Main, Symbol(path[1]))
    for part in path[2:end]
        c = getfield(c, Symbol(part))
    end
    return c
end

const FNMAP = Dict{String,Function}(
    "hl20_poly1d" => HL20Demo.hl20_poly1d,
    "hl20_poly2dr" => HL20Demo.hl20_poly2dr,
    "hl20_poly2de" => HL20Demo.hl20_poly2de,
)

opname(op) = last(split(string(op), ('.', '₊', '#')))

function to_num(x, D)
    x = Symbolics.value(Symbolics.substitute(x, D))
    x isa Number && return Float64(x)
    if Symbolics.iscall(x)
        nm = opname(Symbolics.operation(x))
        f = get(FNMAP, nm, nothing)
        if f === nothing
            s = Symbol(nm)
            f = isdefined(Base, s) ? getfield(Base, s) : nothing
            f isa Function || (f = nm == "ifelse" ? ((c, a, b) -> c ? a : b) : nothing)
        end
        f === nothing && return nothing
        vals = [to_num(a, D) for a in Symbolics.arguments(x)]
        all(v -> v !== nothing, vals) || return nothing
        return try
            Float64(f(vals...))
        catch
            nothing
        end
    end
    return nothing
end

function run_eval(libname, inputs_csv, outputs_csv)
    compty = resolve_comp(split(libname, "."))
    @named m = compty()
    fsys = ModelingToolkit.expand_connections(m)
    eqs = equations(fsys)
    sts = unknowns(fsys)
    S = Set(sts)

    raw_bindings = Dict{Any,Any}()
    for src in (ModelingToolkit.bindings(fsys), ModelingToolkit.initial_conditions(fsys))
        for (k, v) in src
            raw_bindings[k] = v
        end
    end

    df = CSV.read(inputs_csv, DataFrame)
    innames = names(df)
    portvars = Dict{String,Any}()
    for s in sts
        base = replace(string(s), r"\(.*$" => "")
        base in innames && (portvars[base] = s)
    end
    missing_ports = setdiff(innames, collect(keys(portvars)))
    isempty(missing_ports) || error("ports not found among unknowns: $missing_ports")

    D0 = Dict{Any,Float64}()
    pend = collect(raw_bindings)
    for _ in 1:200
        still = Pair{Any,Any}[]
        progressed = false
        for (k, v) in pend
            nv = to_num(v, D0)
            if nv !== nothing
                D0[k] = nv; progressed = true
            else
                push!(still, k => v)
            end
        end
        pend = still
        isempty(pend) && break
        progressed || (@warn "unresolved parameter bindings" pend; break)
    end

    nrow = size(df, 1)
    outcols = Dict{String,Vector{Float64}}()
    order = String[]
    for s in sts
        base = string(s)
        if !(base in order)
            push!(order, base); outcols[base] = fill(NaN, nrow)
        end
    end

    for r in 1:nrow
        D = copy(D0)
        for nm in innames
            D[portvars[nm]] = Float64(df[r, nm])
        end
        unresolved = collect(eqs)
        for _ in 1:200
            still = eltype(unresolved)[]
            progressed = false
            for eq in unresolved
                l, rr = eq.lhs, eq.rhs
                lv = to_num(l, D); rv = to_num(rr, D)
                if rv !== nothing && l in S && lv === nothing
                    D[l] = rv; progressed = true
                elseif lv !== nothing && rr in S && rv === nothing
                    D[rr] = lv; progressed = true
                elseif lv === nothing || rv === nothing
                    push!(still, eq)
                end
            end
            unresolved = still
            isempty(unresolved) && break
            progressed || break
        end
        isempty(unresolved) || error("row $r: $(length(unresolved)) unresolved equations")
        for s in sts
            v = get(D, s, nothing)
            v === nothing && (v = to_num(s, D))
            outcols[string(s)][r] = v === nothing ? NaN : Float64(v)
        end
    end
    odf = DataFrame(outcols)
    CSV.write(outputs_csv, odf)
    println("wrote $outputs_csv: $(size(odf,1)) rows x $(size(odf,2)) cols")
    return odf
end
