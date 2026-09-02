using ModelingToolkit
using ModelingToolkit: t_nounits
using DyadData
using DataInterpolations: DataInterpolations
using BlockComponents.Tables: InterpolationType, ExtrapolationType
using Moshi.Match: @match

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

    # Stack channels into rows: (n_channels, n_times) — the convention
    # DataInterpolations expects for vector-valued u.
    data_matrix = permutedims(stack(getproperty(tb, Symbol(d)) for d in deps))

    interp_value = @match interpolation_type begin
        InterpolationType.ConstantInterpolation() =>
            DataInterpolations.ConstantInterpolation(data_matrix, independent_var; extrapolation, kwargs...)
        InterpolationType.SmoothedConstantInterpolation() =>
            DataInterpolations.SmoothedConstantInterpolation(data_matrix, independent_var; extrapolation, kwargs...)
        InterpolationType.LinearInterpolation() =>
            DataInterpolations.LinearInterpolation(data_matrix, independent_var; extrapolation, kwargs...)
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

    @parameters (interpolator::typeof(interp_value))(..)[1:n_outputs]=interp_value [tunable=false]

    @variables u(t_nounits), [input = true]
    @variables y(t_nounits)[1:n_outputs], [output = true]

    eqs = [y[i] ~ interpolator(u)[i] for i in 1:n_outputs]

    System(eqs, t_nounits, [u, y], [interpolator]; name)
end
