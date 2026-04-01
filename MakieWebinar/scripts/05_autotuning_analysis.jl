using DyadExampleComponents, DyadControlSystems
using ModelingToolkit: @named

@named model = DyadExampleComponents.ActiveSuspension()

spec = DyadControlSystems.PIDAutotuningAnalysisSpec(;
    name=:ActiveSuspensionAutotuning,
    model=model,
    measurement="y",
    control_input="u",
    step_input="set_point.y",
    step_output="seat_pos.s",
    num_frequencies=200,
)

DyadControlSystems.launch_pid_autotuning_designer(spec)
