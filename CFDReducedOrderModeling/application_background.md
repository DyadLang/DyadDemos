# Reduced-Order Modeling of CFD for System Simulation

## The Application: Thermal Management of a Hydraulic Manifold

Industrial hydraulic systems — presses, injection molding machines, mobile equipment — route high-pressure oil through a cast-iron or aluminum manifold block. The manifold contains drilled passages, valve cavities, and internal galleries where oil flows at pressures up to 350 bar.

Heat is generated throughout the hydraulic circuit:

- **Pump inefficiency** converts a fraction of input shaft power to heat (typically 5–15% of rated power, often several kW)
- **Throttling losses** at proportional valves, pressure relief valves, and orifices dissipate energy as heat directly into the oil
- **Viscous friction** in long passages and fittings adds further thermal load

The oil carries this heat into the manifold block. If wall temperatures rise too far, consequences include:

- Oil degradation (oxidation accelerates above 80–90°C, halving oil life for every 10°C above the threshold)
- Seal failure at elevated temperatures
- Viscosity reduction that changes system dynamics (a 20°C rise can halve oil viscosity, altering valve response and actuator speed)
- Thermal distortion of precision-machined valve bores

To manage this, manifold blocks typically include cooling passages — drilled channels where coolant (water or water-glycol) flows through the block to extract heat from the oil passages. The design question is: given a duty cycle of varying hydraulic loads, does the cooling system keep oil and wall temperatures within limits?

## Why CFD?

The geometry of manifold passages is complex: intersecting drilled holes, sharp corners at gallery junctions, varying cross-sections, and thin walls separating hot oil from coolant channels. Predicting the temperature distribution through these walls requires resolving:

- **Conjugate heat transfer** between the oil flow, the solid metal wall, and the coolant flow
- **Turbulent convection** on both the oil and coolant sides (Reynolds numbers typically 2,000–20,000)
- **Three-dimensional conduction** through the wall, where heat spreads laterally as well as through-wall
- **Local hot spots** at stagnation zones, sharp corners, and regions where oil passages run close together

A 3D CFD model (e.g., in ANSYS Fluent, STAR-CCM+, or OpenFOAM) with conjugate heat transfer can resolve all of this. A typical model of one manifold section might have 2–5 million cells and take 30 minutes to several hours per steady-state evaluation, or days for a transient duty cycle.

CFD answers the component design question well: *given this geometry and these boundary conditions, what is the temperature field?* It tells the designer where the hot spots are, whether the cooling channel placement is adequate, and what wall thicknesses provide sufficient thermal resistance.

## Why a Reduced-Order Model?

CFD cannot answer the **system-level** question: *given a realistic duty cycle with varying pump speed, valve commands, and load profiles, does the complete machine stay within thermal limits over an 8-hour shift?*

The reasons are practical:

| Concern | CFD | ROM |
|---------|-----|-----|
| **Evaluation time** | Minutes to hours per time step | Microseconds per time step |
| **Duty cycle simulation** | Impractical for hours of real time | Runs in seconds |
| **Coupling to system model** | Requires co-simulation infrastructure | Drops into Modelica/Dyad as a component |
| **Controller design** | Cannot close the loop with CFD in it | ROM is fast enough for real-time control loops |
| **Design optimization** | Each evaluation is expensive | Thousands of evaluations are feasible |
| **Digital twin deployment** | Cannot run on edge hardware | ROM runs on embedded controllers |

A ROM captures the *input–output behavior* of the CFD model — how wall temperatures respond to heat input over time — in a compact mathematical form that evaluates orders of magnitude faster. The ROM does not resolve the internal 3D field, but it reproduces the quantities that matter for system integration: zone-averaged temperatures, heat fluxes at boundaries, and thermal time constants.

### Concrete use cases for the ROM

1. **Full-system thermal simulation.** Embed the manifold thermal ROM into a system model that includes the hydraulic pump, valves, actuators, oil reservoir, and cooling circuit. Simulate a realistic duty cycle (e.g., a press performing 500 stamping cycles per shift with varying force profiles) and predict oil temperature, wall temperature, and coolant demand over the full shift.

2. **Cooling system controller design.** The coolant flow rate is often controlled by a thermostat or a variable-speed pump. Tuning this controller requires a plant model that responds in the right time scale. The ROM provides that plant model. You can run closed-loop simulations, tune PID gains, or apply model-based control design (LQG, MPC) with the ROM in the loop.

3. **Design space exploration.** Varying wall thickness, coolant flow rate, oil flow velocity, or material properties across hundreds of combinations is infeasible with CFD but straightforward with a parameterized ROM. This enables early-stage trade studies before committing to detailed CFD runs.

4. **Real-time monitoring (digital twin).** Deploy the ROM on edge hardware alongside the physical machine. Feed it measured pump speed, valve positions, and coolant inlet temperature. It predicts internal wall temperatures that cannot be measured directly, enabling predictive maintenance alerts before thermal limits are reached.

## The Demo: From Synthetic CFD to Deployable ROMs

This demo uses a simplified 1D through-wall model as a stand-in for CFD. The 20-node finite-difference model (`HighFidelityOilPassage`) represents a cross-section through the manifold wall between an oil passage and a coolant channel. It is computationally cheap (unlike real CFD), but it produces physically representative thermal dynamics — the same exponential rise, the same spatial temperature gradient, the same time constants — that a real CFD model would produce.

Three data-driven ROM construction pipelines are demonstrated, each fully automated from raw snapshot data to a deployable Dyad component:

### 1. SVD Thermal Network (4 zones, calibrated tridiagonal)

Performs SVD on spatial snapshots to discover the dominant thermal modes, then uses energy-weighted k-means clustering on the mode shapes to assign the 20 spatial nodes to physical zones. The zone count is selected automatically based on a per-mode R² threshold. A tridiagonal thermal network (nearest-neighbor coupling) is calibrated against the CFD data via Nelder-Mead optimization.

Zone assignments are data-driven and unequal: zones are finer where the temperature field varies most. The resulting Dyad component (`SVDThermalNetworkROM`) has N zone temperature states with calibrated capacitances and conductances.

**When to use:** General-purpose ROM construction from spatial field data. Produces physically interpretable parameters (thermal capacitance, conductance) suitable for system integration. No knowledge of the governing equations required — only snapshot data.

### 2. Latent Neural ODE Network (4 zones, calibrated tridiagonal)

Trains an Encoder → Neural ODE → Decoder pipeline across a sweep of latent dimensions to discover the optimal ROM order from the data. The encoder compresses spatial snapshots to a latent state, the Neural ODE learns the dynamics in latent space, and the decoder reconstructs the spatial field. After discovering the latent dimension k, SVD mode projection determines the physical zone count and a tridiagonal thermal network is calibrated.

This approach discovers the ROM order automatically — it does not assume a particular number of modes or zones. The zone assignments differ from the SVD method because the Neural ODE captures nonlinear relationships that SVD (a linear decomposition) may miss.

**When to use:** When the system may have nonlinear dynamics that linear SVD cannot capture, or when automatic order discovery is desired. More computationally expensive to train than SVD, but can discover structure that linear methods miss.

### 3. POD/DMDc (k=2 latent states, 3 output zones)

Combines Proper Orthogonal Decomposition (POD) for basis extraction with Dynamic Mode Decomposition with control (DMDc) for dynamics identification. SVD of snapshots yields the dominant POD modes, then finite differences of the projected coordinates give dz/dt, which is fit to a linear model dz/dt = A·z + B·u via least-squares. The output matrix C maps latent POD coordinates to zone-averaged temperature deviations.

Unlike the thermal network ROMs, the states here are abstract POD coordinates — not physical temperatures. The model is a compact linear state-space system with k latent states, 1 input, and N_zones outputs.

**When to use:** When a minimal-state linear ROM is sufficient. Fastest to construct and smallest model size. Works well for linear or mildly nonlinear systems. The abstract state representation means parameters are not physically interpretable, but the input-output behavior is accurate.

### Comparison

| Approach | States | Zones | Interface | Validation RMS | Strengths |
|----------|--------|-------|-----------|----------------|-----------|
| SVD Thermal Network | 4 | 4 [5,5,4,6] | Signal I/O | 0.18 K | Physical parameters, general-purpose |
| Neural ODE Network | 4 | 4 [2,4,6,8] | Signal I/O | 0.17 K | Automatic order discovery, nonlinear |
| POD/DMDc | 2 | 3 [4,6,10] | Signal I/O | 0.12 K | Minimal states, fastest construction |

All three ROMs run in microseconds and generalize to unseen input profiles — the validation uses a ramp input that was not part of the training data (step + sine).

### ROM Construction Pipelines (Julia-side Analyses)

Each ROM is constructed by a Dyad-compatible analysis that implements the full `DyadInterface` API:

```julia
using CFDReducedOrderModeling

# SVD Thermal Network
result = RunSVDThermalNetwork(data="data/cfd_training_data.csv")
artifacts(result, :CalibratedNetwork)   # DataFrame of C, G, Gc parameters
artifacts(result, :ZoneAssignments)     # which spatial points in each zone

# POD/DMDc
result = RunDataDrivenPOD(data="data/cfd_training_data.csv")
artifacts(result, :ROMParameters)       # A, B, C matrices

# Latent Neural ODE
result = RunLatentNeuralODE(data="data/cfd_training_data.csv")
artifacts(result, :LatentDimSweep)      # RMSE vs latent dimension
artifacts(result, :CalibratedNetwork)   # calibrated network parameters
```

The resulting ROM parameters are encoded as Dyad components (`SVDThermalNetworkROM`, `NeuralODEThermalNetworkROM`, `PODDMDcROM`) that compile to ModelingToolkit systems for transient simulation.

### Dashboard

The interactive dashboard (`app/app.jl`) provides:

- **Training data visualization** with zone-averaged temperatures from the 20-node model
- **ROM vs CFD comparison** on unseen validation data for all three methods
- **Relative error plots** showing percentage deviation per zone
- **SVD energy spectrum** from the training snapshots

Launch: `julia --project=.. app/app.jl` → open `http://localhost:9000`
