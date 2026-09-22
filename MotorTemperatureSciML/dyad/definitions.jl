using ModelingToolkit
using StaticArrays: SVector
using ModelingToolkit: t_nounits
using DyadData
using DataInterpolations: DataInterpolations
using EnzymeCore: EnzymeCore
using BlockComponents.Tables: InterpolationType, ExtrapolationType
using Moshi.Match: @match

"""
    ForcingInterpolation(itp)

Callable wrapper around a `DataInterpolations` interpolator that carries *measured
forcing*: data the model is driven by, never calibrated. The type exists so that an
AD backend can be told, in user code, that nothing reachable from it is differentiable
(e.g. `EnzymeRules.inactive_type` on the type + `EnzymeRules.inactive` on the call),
without making that claim about `DataInterpolations` types in general.
"""
struct ForcingInterpolation{I}
    itp::I
end
(f::ForcingInterpolation)(t) = getfield(f, :itp)(t)
# transparent to readers of the data (`profile_data` reads `.t`/`.u`)
Base.getproperty(f::ForcingInterpolation, s::Symbol) =
    s === :itp ? getfield(f, :itp) : getproperty(getfield(f, :itp), s)

# Enzyme: the forcing is constant data. Both rules are needed and sufficient:
#  - `inactive_type` shrinks the parameter shadow (no `make_zero`/`remake_zero!` copy of
#    the tables on every VJP, ~6x per reverse pass on the motor model);
#  - `inactive` on the CALL guarantees no active-typed pointer is ever loaded out of the
#    inactive object — the evaluation returns an isbits `SVector`, so nothing downstream
#    can form ∂/∂(table) and accumulate it into the aliased primal (Enzyme.jl#1569 class).
#    The type rule alone happened to work on this wrapper, but the same shape with one more
#    container hop corrupts the tables under static activity, so do not rely on it.
# Deliberately NOT declared on `DataInterpolations` types: users calibrating interpolation
# data need those gradients.
EnzymeCore.EnzymeRules.inactive_type(::Type{<:ForcingInterpolation}) = true
EnzymeCore.EnzymeRules.inactive(::ForcingInterpolation, args...; kwargs...) = nothing

"""
    FastVectorInterpolation(; interpolation_type, extrapolation_type, dataset,
                              n_outputs, name, kwargs...)

One `DataInterpolations` interpolator over all `dependent_vars` of `dataset`,
stored as a concretely-typed, non-tunable callable parameter:

    @parameters (interpolator::typeof(itp))(..)[1:n_outputs] = itp [tunable = false]

The `::typeof(itp)` annotation avoids the `FunctionWrapper` fallback (which
boxes every call — costly under ForwardDiff), and `[tunable = false]` keeps
the slot out of the tunable buffer. The `interpolator(t)[i]` reads CSE into
a single time search per RHS call, however many channels are consumed.

`n_outputs` must equal `length(get_dependent_vars(dataset))`; channel `i`
is the i-th dependent var.
"""
function FastVectorInterpolation(; interpolation_type, extrapolation_type = ExtrapolationType.None(),
        dataset, n_outputs, name, kwargs...)
    extrapolation = @match extrapolation_type begin
        ExtrapolationType.None()       => DataInterpolations.ExtrapolationType.None
        ExtrapolationType.Constant()   => DataInterpolations.ExtrapolationType.Constant
        ExtrapolationType.Linear()     => DataInterpolations.ExtrapolationType.Linear
        ExtrapolationType.Extension()  => DataInterpolations.ExtrapolationType.Extension
        ExtrapolationType.Periodic()   => DataInterpolations.ExtrapolationType.Periodic
        ExtrapolationType.Reflective() => DataInterpolations.ExtrapolationType.Reflective
        _ => error("Unsupported extrapolation type: $extrapolation_type")
    end

    deps = get_dependent_vars(dataset)
    n_outputs == length(deps) ||
        error("FastVectorInterpolation: n_outputs ($n_outputs) ≠ length(get_dependent_vars(dataset)) ($(length(deps)))")

    # `build_table` once; `dataset[col]` would rebuild it per-column otherwise.
    tb = build_table(dataset)
    independent_var = getproperty(tb, Symbol(get_independent_var(dataset)))

    # One `SVector` per time sample rather than an (n_channels, n_times) matrix:
    # DataInterpolations then returns an `SVector` from each evaluation — no heap
    # allocation per RHS call (the matrix layout allocates the result vector, and
    # the slope vector unless parameters are cached), and no pointer-valued
    # temporary for Enzyme's static activity analysis to classify.
    cols = [getproperty(tb, Symbol(d)) for d in deps]
    data_matrix = [SVector{n_outputs, Float64}(ntuple(j -> Float64(cols[j][i]), n_outputs))
                   for i in eachindex(independent_var)]

    interp_value = @match interpolation_type begin
        InterpolationType.ConstantInterpolation() =>
            DataInterpolations.ConstantInterpolation(data_matrix, independent_var; extrapolation, kwargs...)
        InterpolationType.SmoothedConstantInterpolation() =>
            DataInterpolations.SmoothedConstantInterpolation(data_matrix, independent_var; extrapolation, kwargs...)
        InterpolationType.LinearInterpolation() =>
            DataInterpolations.LinearInterpolation(data_matrix, independent_var; extrapolation,
                cache_parameters = true, kwargs...)
        InterpolationType.QuadraticInterpolation() =>
            DataInterpolations.QuadraticInterpolation(data_matrix, independent_var; extrapolation, kwargs...)
        InterpolationType.LagrangeInterpolation(n) =>
            DataInterpolations.LagrangeInterpolation(data_matrix, independent_var, n; extrapolation, kwargs...)
        InterpolationType.QuadraticSpline() =>
            DataInterpolations.QuadraticSpline(data_matrix, independent_var; extrapolation, kwargs...)
        InterpolationType.CubicSpline() =>
            DataInterpolations.CubicSpline(data_matrix, independent_var; extrapolation, kwargs...)
        InterpolationType.AkimaInterpolation() =>
            DataInterpolations.AkimaInterpolation(data_matrix, independent_var; extrapolation, kwargs...)
        _ => error("Unsupported interpolation type: $interpolation_type")
    end

    # measured forcing, never calibrated: see `ForcingInterpolation`
    interp_value = ForcingInterpolation(interp_value)
    @parameters (interpolator::typeof(interp_value))(..)[1:n_outputs]=interp_value [tunable=false]

    @variables u(t_nounits), [input = true]
    @variables y(t_nounits)[1:n_outputs], [output = true]

    eqs = [y[i] ~ interpolator(u)[i] for i in 1:n_outputs]

    System(eqs, t_nounits, [u, y], [interpolator]; name)
end
