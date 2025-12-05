# How to do PID Autotuning in Dyad

This guide shows the exact steps to autotune a PID controller in a Dyad model using the DyadControlSystems package.

## Prerequisites

1. A Dyad model with a PID controller (typically `BlockComponents.LimPID`)
2. A feedback control loop where you want to optimize the controller

## Step 1: Install DyadControlSystems Package

In Julia REPL:
```julia
using Pkg
Pkg.add("DyadControlSystems")
```

## Step 2: Add Analysis Points to Your Dyad Model

Analysis points mark the locations where signals are measured and controlled. Add them in the `relations` block of your component:

```dyad
component MyControlledSystem
  # ... component definitions ...
  
  controller = BlockComponents.LimPID(k=1000, Ti=100, Td=0)
  plant = MyPlant()
  
relations
  # Analysis points MUST come before connect statements
  y_ap: analysis_point(plant.output, controller.u_m)
  u_ap: analysis_point(controller.y, plant.input)
  
  # Then your normal connections
  connect(plant.output, controller.u_m)
  connect(controller.y, plant.input)
  # ... other connections ...
end
```

**Key points:**
- `y_ap` marks the measurement signal (plant output → controller input)
- `u_ap` marks the control signal (controller output → plant input)
- Analysis point names can be anything, but use descriptive names
- The analysis point mirrors the `connect` statement but adds a name

## Step 3: Compile Your Dyad Code

Ensure your Dyad model compiles successfully with the analysis points added.

## Step 4: Create the Autotuning Specification in Julia

In Julia REPL:

```julia
using ThermalHouseDemo  # Replace with your library name
using DyadControlSystems
using DyadInterface

# Create an instance of your test component
# This must be a ModelingToolkit System (use name=:test)
model_sys = ThermalHouseDemo.TestMyControlledSystem(name=:test)

# Create the autotuning specification
spec = DyadControlSystems.PIDAutotuningAnalysisSpec(
    name = :MyAutotuning,
    model = model_sys,
    
    # Analysis point names (hierarchical path if nested)
    measurement = "controlled_house.y_ap",      # Plant output to controller
    control_input = "controlled_house.u_ap",    # Controller output to plant
    step_input = "controlled_house.u_ap",       # For step response
    step_output = "controlled_house.y_ap",      # For step response
    
    # Controller specifications
    Ts = 60.0,              # Sampling time (s) - choose based on your dynamics
    duration = 7200.0,      # Step response duration (s)
    
    # Robustness constraints (sensitivity function bounds)
    Ms = 1.4,               # Sensitivity constraint (typical: 1.2-2.0)
    Mt = 1.4,               # Complementary sensitivity constraint
    Mks = 1.4,              # Input sensitivity constraint
    
    # Frequency range for analysis
    wl = 1e-5,              # Low frequency (rad/s)
    wu = 1e-1,              # High frequency (rad/s)
    num_frequencies = 200   # Number of frequency points
)
```

**Parameter Guidelines:**
- `Ts`: Choose 1-10% of your system's time constant
- `duration`: 2-5 times the dominant time constant
- `Ms, Mt, Mks`: Lower values (1.2-1.5) = more robust, higher values (1.8-2.0) = more aggressive
- `wl, wu`: Should span your system's bandwidth

## Step 5: Run the Autotuning Analysis

```julia
# Run the analysis (may take several minutes)
result = DyadInterface.run_analysis(spec)

# Display the result
println(result)
```

## Step 6: Extract the Optimized Parameters

```julia
# Get the parameter table
params = DyadInterface.artifacts(result, :OptimizedParameters)

println("Optimized PID Parameters (Standard Form for LimPID):")
println("  k  (Kp):  ", params.Kp_standard[1])
println("  Ti:       ", params.Ti_standard[1], " s")
println("  Td:       ", params.Td_standard[1], " s")
println("  Nd:       ", params.Nd[1])
```

**The table contains:**
- `Kp_standard`: Proportional gain (use for `k` parameter)
- `Ti_standard`: Integral time (use for `Ti` parameter)
- `Td_standard`: Derivative time (use for `Td` parameter)
- `Nd`: Derivative filter coefficient (use for `Nd` parameter)

## Step 7: View Available Artifacts

```julia
# List all available visualizations and data
artifact_names = DyadInterface.artifacts(result)
println("Available artifacts:")
for name in artifact_names
    println("  - ", name)
end

# Available artifacts typically include:
#   - SensitivityFunctions
#   - NoiseSensitivityAndController
#   - OptimizedResponse
#   - ControlSignalResponse
#   - NyquistPlot
#   - OptimizedParameters
```

## Step 8: Apply Parameters to Your Dyad Model

Update your Dyad component with the optimized values:

```dyad
component MyControlledSystem
  controller = BlockComponents.LimPID(
    k = 1.4,          # From Kp_standard
    Ti = 796656,      # From Ti_standard
    Td = 0.0439,      # From Td_standard
    Nd = 15752,       # From Nd
    y_max = 10000,
    y_min = 0
  )
  # ... rest of component ...
end
```

## Troubleshooting

### "Analysis point not found"
- Check that analysis point names match exactly (case-sensitive)
- Use hierarchical names if your analysis points are in a subcomponent: `"subcomponent.y_ap"`
- Ensure analysis points are in the component you're analyzing

### "Optimization failed" or "Error in step computation"
- Try adjusting the frequency range (`wl`, `wu`)
- Relax robustness constraints (increase `Ms`, `Mt`, `Mks` to 2.0)
- Increase `duration` for slower systems
- Check that your model is stable in open loop

### Very different parameters from manual tuning
- This is normal - autotuning optimizes for robustness, not speed
- For systems with periodic disturbances (like solar cycles), integral times can be very large
- Trust the optimization if it meets your robustness criteria
