# PassiveSuspension

A car hits a bump, and its springs and dampers decide how much of the jolt
reaches the person in the seat. This library models one corner of a car -- one
wheel, the body above it, and the seat -- with
[Dyad](https://help.juliahub.com/dyad), and compares a purely passive
suspension against an actively controlled one.

The passive model drives over an ISO 8608 Class C road profile -- the standard
description of an average-to-poor quality paved road. Rider comfort is scored
against ISO 2631-1, the standard that sets how much vibration a seated person
will tolerate before calling a ride uncomfortable.

As shipped, the passive model lands short of that standard's top comfort band.
Finding damper values that reach it is the point of the demo.

## Getting Started

Download this folder to your machine and open it in VS Code with the [Dyad
extension](https://help.juliahub.com/dyad/dev/getting_started/).

## Models

The following Dyad models are defined in the `dyad/` directory:

- **`ISO8608RoadC`** -- Road displacement source approximating an ISO 8608 Class
  C profile
  (`Gd_n0 = 256e-6 m^3`) as a sum of `N = 30` sinusoids spaced between 0.5 and
  30 Hz. The `v` parameter
  sets how rough the road feels: amplitudes scale with the square root of
  vehicle speed. The frequencies,
  amplitudes, and phases come from helper functions in `src/iso8608.jl`.

- **`MyPassiveSuspension`** -- Three stacked `MassSpringDamper` components
  (wheel 45 kg, car and
  suspension 400 kg, human and seat 80 kg) riding on the `ISO8608RoadC` profile
  at 20 m/s. There is no
  actuator: disturbance rejection comes entirely from the springs and dampers.

- **`MyActiveSuspension`** -- A local copy of
  `DyadExampleComponents.ActiveSuspension`. Same three-mass
  stack, but with a force actuator between car and seat driven by a `LimPID`
  controller holding seat
  position at 1.5 m, and `u`/`y` analysis points for control design.

Two things differ between the two models, so they are not a like-for-like pair:

1. `MyActiveSuspension` uses `DyadExampleComponents.RoadData` -- a single smooth 0.2 m bump
   repeating every 10 s -- rather than the Class C profile.
2. Its masses and spring rates are the example library's values (25 / 1000 / 100
   kg), not the more
   realistic quarter-car values used in `MyPassiveSuspension`.

Each file also defines a 10 s transient analysis with `dtmax = 0.01`:
`PassiveSuspensionTransient` and
`ActiveSuspensionTransient`.

## Running Experiments

`scripts/analysis-notebook.ipynb` loads the library through `DyadOrchestrator`,
runs either analysis, and
produces plots. Set `analysis_name` to `"PassiveSuspensionTransient"` or
`"ActiveSuspensionTransient"` and
run the cells.

## Rider Comfort

Comfort is measured by the ISO 2631-1 frequency-weighted RMS vertical
acceleration at the seat:

$$a_w = \sqrt{\frac{1}{T} \int_0^T a_w(t)^2\,dt}$$

where `a_w(t)` is the seat acceleration (`seat.mass.a`) passed through the
standard's `W_k` weighting
curve for vertical whole-body vibration of a seated person, and `T` is the
averaging period. ISO 2631-1
Annex C maps the resulting `a_w` to comfort reactions in public transport:

| `a_w` (m/s^2) | Reaction |
|---|---|
| < 0.315 | Not uncomfortable |
| 0.315 -- 0.63 | A little uncomfortable |
| 0.5 -- 1.0 | Fairly uncomfortable |
| 0.8 -- 1.6 | Uncomfortable |
| 1.25 -- 2.5 | Very uncomfortable |
| > 2.0 | Extremely uncomfortable |

The bands overlap, as they do in the standard: the values are approximate
indications, not hard limits.
The target for this demo is the top band, `a_w < 0.315 m/s^2`.

## Prompts Used for a Typical Demo

1. Summarize the models in this repo.
2. Compute the ISO 2631-1 weighted RMS seat acceleration for
   `PassiveSuspensionTransient`. Which comfort
   band does it land in?
3. Sweep the damper values (`wheel_damping`, `suspension_damping`,
   `seat_damping`) to find a combination
   that reaches "not uncomfortable" on a Class C road at 20 m/s. What trade-offs
   does it make -- suspension
   travel, wheel load, response to a discrete bump?
4. Turn the sweep into a design optimization over the same parameters.
5. Animate the three masses vibrating in response to the Class C profile.
