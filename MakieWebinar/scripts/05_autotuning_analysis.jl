using DyadExampleComponents, DyadControlSystems

result = DyadExampleComponents.ActiveSuspensionPIDAutotuningAnalysis()
spec = result.spec

DyadControlSystems.launch_pid_autotuning_designer(spec)