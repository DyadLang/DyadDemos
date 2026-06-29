# MultibodyDemo

This project is a collection of 2D (planar) multibody dynamics demos built with Dyad and ModelingToolkit. Each model is assembled from the `MultibodyComponents.PlanarMechanics` library — rigid bodies, joints, wheels, and a gravity field that all move and interact in a single vertical or top-down plane. Signal sources and controllers come from `BlockComponents`; rotational drivetrain parts (inertias, torque sources, gears) come from `RotationalComponents`. Results can be animated as 3D renderings via `MultibodyComponents.render` (which uses `GLMakie`).

The demos range from a textbook single pendulum up to a feedback-controlled self-balancing robot and a four-wheel car with tire slip and a differential.

## Getting Started

Download this folder to your machine and open it in VS Code with the [Dyad extension](https://help.juliahub.com/dyad/dev/getting_started/).

The Dyad models live in `dyad/`. Each model has a paired `analysis` that runs it as a `TransientAnalysis`. Compiling the project (Dyad extension, or the build step) generates the Julia code in `generated/`, after which the analyses are callable from Julia.

## Models

All models are defined in `dyad/`. Each `*.dyad` model file is accompanied by an analysis (either inline, as in `Pendulum.dyad`, or in a separate `*analysis.dyad` file).

### Pendulum (`dyad/Pendulum.dyad`)

A single planar pendulum: a `World` gravity field, a `Revolute` joint, a rigid `FixedTranslation` rod (length 1 m), and a point `Body` (m = 1 kg) at the end. It swings freely under gravity from a horizontal start.
Analysis: `PendulumTransient` (stop = 3 s).

### Spring–Damper System (`dyad/springdampersystemtest.dyad`)

A free `Body` (m = 0.5 kg) suspended from a fixed anchor by a 2D `SpringDamper` (stiffness and damping in both x and y). The body is released from an offset position and oscillates as the spring and damper pull it toward equilibrium. The body's motion is otherwise unconstrained.
Analysis: `SpringDamperSystemTestAnalysis` (stop = 10 s).

### Self-Balancing Robot — "Balans" (`dyad/dyadbalans2d.dyad`)

A wheeled balancing robot (an inverted pendulum on a driven wheel, the classic Segway problem) stabilized by a **cascade control system**:

- **Inner loop** — `angle_controller` (`LimPID`) holds the body tilt angle upright by commanding motor torque.
- **Outer loop** — `pos_controller` (`LimPID`) regulates the cart position; its output is a small reference lean angle (saturated to ±25°) fed to the inner loop, so the robot leans to drive toward a target — exactly how a rider moves a Segway.

A filtered square wave provides the moving position setpoint. The body rolls on a `OneDOFRollingWheelJoint` driven by a `SimpleMotor`, and an `AbsolutePosition` sensor (the "IMU") feeds tilt and position back to the controllers. Named `analysis_point`s tap the loop signals for linearization/loop analysis. *("Balans" is Swedish for "balance.")*
Analysis: `DyadBalans2DAnalysis` (stop = 10 s).

### Two-Track Car Model (`dyad/twotrackmodeltest.dyad`)

A four-wheel ("double track") vehicle viewed from above (`World` gravity set to 0). Each wheel is a `SlipBasedWheelJoint` with an adhesion/slip friction curve, the rear axle is driven through a `DifferentialGear` from an engine torque source, and the front wheels are steered by a square-wave steering torque acting through revolute joints. It demonstrates tire slip, drivetrain coupling, and planar vehicle handling.
Analysis: `TwoTrackModelTestAnalysis` (stop = 10 s).

## Running the Demo

**`scripts/main.jl`** runs all four analyses and renders each one. For every model it opens an interactive single-frame view and writes an animation (`.mp4`) of the full trajectory to the working directory. A pre-rendered example, `multibody_DyadBalans2D.mp4`, is included in the project root.

The basic pattern for running and rendering a model:

```julia
using MultibodyDemo
using MultibodyComponents
using GLMakie                          # load a Makie backend BEFORE rendering
using DyadInterface: symbolic_container

result = PendulumTransient()           # runs the analysis

# interactive frame at t = 1.0 s
fig, t, scene = MultibodyComponents.render(result, 1.0)
display(fig)

# animation of the full trajectory -> writes an mp4 in the working dir
MultibodyComponents.render(result)
```

You can also drive the renderer directly with the model and solution for custom cameras, output filenames, and traced paths:

```julia
model = symbolic_container(result)
sol   = result.sol
MultibodyComponents.render(model, sol;
    filename  = "pendulum_trace.mp4",
    framerate = 30,
    x = 2, y = 0.5, z = 2,             # camera position
    traces = [model.body.frame_a]      # draw the path the body sweeps
)
```

And the same accessors work for inspecting any variable as a time series:

```julia
model = symbolic_container(result)
sol   = result.sol
sol[model.revolute.phi]   # pendulum joint angle vs. time
sol.t                     # the time vector
```

Run the full script from the project root with the project environment active:

```
julia --project=. scripts/main.jl
```

or from a REPL with `include("scripts/main.jl")`.

**`scripts/analysis-notebook.ipynb`** provides an interactive environment to run the analyses and plot variables of interest.

Notes:
- A Makie backend (`GLMakie`) must be loaded **before** calling `MultibodyComponents.render`.
- The first run compiles the models and the rendering stack, so expect it to take a few minutes.
