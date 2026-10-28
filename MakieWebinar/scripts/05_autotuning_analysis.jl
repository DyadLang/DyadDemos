# Run with julia +dyad-3.5.1 --project=scripts scripts/05_autotuning_analysis.jl
using DyadExampleComponents, DyadControlSystems
using ModelingToolkit: @named

@named model = DyadExampleComponents.ActiveSuspension()

spec = DyadControlSystems.PIDAutotuningAnalysisSpec(;
    name=:ActiveSuspensionAutotuning,
    model=model,
    measurement="y",
    control_input="u",
    step_input="reference_input",
    ref=1.0, # Track a unit reference step.
    step_output="y",
    num_frequencies=200,
)

DyadControlSystems.launch_pid_autotuning_designer(spec)
