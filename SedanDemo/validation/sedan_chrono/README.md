# Chrono reference simulations for the sedan model

The scripts in this folder run the original Project Chrono JSON sedan (the
model this one was ported from) headless through PyChrono and log
reference trajectories to CSV. The committed copies of those CSVs live in
`test/references/sedan/` and are what `test/test_vehicles.jl` regresses
against, so CI never needs Chrono; re-run these scripts only to regenerate the
references.

## Setup

PyChrono builds with the vehicle module are only published on the
`projectchrono` conda channel (the conda-forge build disables the vehicle
module, and the `pychrono` package on PyPI is an unrelated project). Without a
conda installation, use the static micromamba binary:

```bash
curl -L https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj bin/micromamba
export MAMBA_ROOT_PREFIX=$PWD/mamba-root
./bin/micromamba create -y -n pychrono -c projectchrono -c conda-forge \
    "projectchrono::pychrono=10" python=3.12 numpy
```

The package ships the Chrono data directory, including the sedan JSONs and the
ISO double-lane-change path, so no additional data is needed.

## Runs

```bash
micromamba run -n pychrono python run_settle.py      # 4 s, zero inputs
micromamba run -n pychrono python run_accel.py       # settle 1 s, then full throttle
micromamba run -n pychrono python run_step_steer.py  # hold 15 m/s, steering step 0.1 at t = 12 s
micromamba run -n pychrono python run_dlc.py         # ISO double lane change at 12 m/s
```

Each writes a CSV at 100 Hz with the schema in `sedan_common.py` (`HEADER`).
The tire model is selected with the `SEDAN_TIRE` environment variable:
`tmeasy` (default, matches this model) or `pac02`.
Positions/angles are in Chrono's ISO frame (x forward, y left, z up); the
Julia tests convert to this library's world frame (x forward, y up, z right)
via `y_world = z_iso`, `z_world = -y_iso`, `yaw_world = yaw_iso`.

Notes:
- The step-steer script implements the speed controller directly (same
  proportional law as `VehicleComponents.SpeedController`) so the Chrono and
  Dyad runs use identical longitudinal control by construction.
- The lane-change run uses Chrono's `ChPathFollowerDriver` with gains (0.8,
  0, 0), look-ahead 5 m, and speed gains (0.4, 0, 0). Chrono's path tracker
  misbehaves after the path end (x_iso = 56, about t = 15.5 s at 12 m/s);
  comparisons should use t ≤ 15 s.
- The vehicle in `run_dlc.py` starts at the path origin (-125, -125); the
  other runs start at the world origin.
