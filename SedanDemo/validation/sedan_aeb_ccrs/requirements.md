# Sedan AEB: Euro NCAP CCRs requirements

An autonomous emergency braking (AEB) function for the `Sedan` model, tested in the
Euro NCAP car-to-car rear, stationary target scenario (CCRs) and scored with the
protocol's colour bands.

## Sources

- **Authoritative:** Euro NCAP *Crash Avoidance – Frontal Collisions – Protocol*,
  version 1.2, July 2026 (implementation January 2026). URL and SHA-256 are in
  [`protocol.toml`](protocol.toml) `[source]`. Every test condition, measurement
  definition, colour band and score below traces to it. Citations give the section,
  the printed page and the PDF page (PDF page = printed page + 2). Protocol text is
  paraphrased; the PDF is not redistributed in this repository.
- **Helpers (no criteria):**
  - Protocol version 1.1, October 2025: same CCRs grid, colour bands and scoring as
    1.2.
  - *AEB Car-to-Car Test Protocol* 4.3.1 (2024): only to map the request's
    "−50 % to +50 % overlap" wording (DEC-1).
  - Technical Bulletin TB 025, *Global Vehicle Target Specification*, 1.0 (2018):
    target dimensions, a declared input. Version 1.2 points to ISO 19206-3:2021,
    which was not read.

The AEB function is designed here, not reproduced from a source. The protocol
supplies the test procedure and the scoring. Only REQ-AEB-1 is a pass/fail
criterion from the protocol; the colour grid and points are reported results.

## Scenario and test conduct

| ID | Requirement | Rationale | Method |
| --- | --- | --- | --- |
| REQ-SCN-1 | Run every cell of the grid: VUT speed 10, 20, …, 80 km/h × impact location 0, 25, 50, 75, 100 % (standard range), plus −25 % and 125 % (extended range). | §3.1.1.1, p.29 / PDF 31 | A |
| REQ-SCN-2 | The target is stationary (0 km/h) and its rear faces the VUT. | §3.1.1.1, p.29 / PDF 31 | I |
| REQ-SCN-3 | The test starts (T0) at time-to-collision 4.0 s, located on the dense solution. | §1.5.1, p.22 / PDF 24 | T |
| REQ-SCN-4 | From T0 to the start of AEB braking (TAEB): VUT speed within ±1.0 km/h of the test speed (DEC-8); lateral deviation of the front-axle centre within 0 ± 0.05 m of the intended path. Checked in every run; a run that misses it is reported as invalid, not scored. | §4.3.2, p.64 / PDF 66; §1.2.2, p.10 / PDF 12 | T |
| REQ-SCN-5 | The accelerator is released once the speed has dropped 5 km/h below the test speed, and it never overrides AEB braking. There is no other brake input. | §4.3.2, p.65 / PDF 67 | T |
| REQ-SCN-6 | The impact location aligns the target's rear-centre point with a percentage of the VUT width: 0 % at the near-side edge (right, LHD), 100 % at the far-side edge. | §1.2.5, p.13 / PDF 15; §1.4.1.4, p.21 / PDF 23; §1.1.1, p.8 / PDF 10 | I |
| REQ-SCN-7 | The road friction meets the minimum peak braking coefficient of 0.9 (TMeasy `mu_road = 0.9`, DEC-9). | §2.1, p.24 / PDF 26 | I |

## Measurement

| ID | Requirement | Rationale | Method |
| --- | --- | --- | --- |
| REQ-MEAS-1 | Vimpact is the VUT speed at the first instant its front profile (seven points over the width minus 50 mm per side) reaches the target's rear plane while the two overlap laterally. It is located on the dense solution by root finding, not taken from the nearest output sample. Vrel_impact = Vimpact (stationary target). A run with no contact has Vimpact = 0. | Definitions, p.4 / PDF 6; §1.3.1, p.18 / PDF 20 | T |
| REQ-MEAS-2 | TAEB is the first instant the filtered longitudinal acceleration is below −3 m/s², traced back to its first crossing of −1 m/s². Filter: 12-pole phaseless Butterworth, 10 Hz. Reported only. | Definitions, p.4 / PDF 6; §1.5.3, p.23 / PDF 25 | A |
| REQ-MEAS-3 | Recorded channels are sampled at 100 Hz or faster. | §1.5, p.22 / PDF 24 | I |

## AEB function

| ID | Requirement | Rationale | Method |
| --- | --- | --- | --- |
| REQ-AEB-1 | **Acceptance.** Vimpact = 0 (full avoidance) at 10 and 20 km/h for every standard-range impact location. | §5.1, p.66 / PDF 68 (entry condition for any CCRs AEB points) | T |
| REQ-AEB-2 | Each cell gets the colour of its Vrel_impact under Figure 5-1, and the grid gets the standard-range and extended-range points of §5.3.1–5.3.2. Reported only: this is the prediction a manufacturer submits, not a verdict. | Figure 5-1, p.67 / PDF 69; §5.3.1–5.3.2, p.73 / PDF 75 | A |
| REQ-AEB-3 | The AEB is a native Dyad component in `VehicleComponents`, driving the `Sedan` through its `throttle` and `braking` inputs. | DEC-3 | I |
| REQ-AEB-4 | The AEB, target and sensor contain no discrete events, so that the scenario stays cheap to batch in parameter sweeps. | DEC-4 | I |

## Decisions

| ID | Date | Decision | Context and alternatives |
| --- | --- | --- | --- |
| DEC-1 | 2026-10-25 | Use protocol 1.2 (2026). **User** | The request describes protocol 4.3.1: 5 km/h steps, overlap −50/−75/100/+75/+50 % (the sign gives the side). Protocol 1.2 governs late-2026 ratings and uses impact locations instead. |
| DEC-2 | 2026-10-25 | AEB in all eight speed cells; the FCW test with robot braking (60–80 km/h) is out of scope. **User** | The protocol lets AEB stand in for the FCW cells (§3.1.1.1 note, PDF 31). |
| DEC-3 | 2026-10-25 | Ideal sensor: exact range and closing speed to the target, with an in-path check against the VUT width. **User** | Consequence: the impact location changes the result only through geometry, so the grid is expected to be nearly flat across its columns. A field-of-view sensor is optional. |
| DEC-4 | 2026-10-25 | The AEB, target and sensor stay event-free (REQ-AEB-4). **User** | |
| DEC-5 | 2026-11-24 | Run on the Dyad 3.5 stack (`dyad-3.5.0` distribution, compiler 3.5.0), with the closed-form double wishbone of `VehicleComponents`. | The records in this folder were written on that stack. |
| DEC-6 | 2026-10-25 | Vehicle mass as modeled (1550 kg chassis, plus wheels). **User** | The protocol loads the car to kerb mass + 200 kg, within ±1 % (§2.4, p.27 / PDF 29). Accepted deviation. |
| DEC-7 | 2026-11-24 | Resolve the environment with the 3.5.0 runtime. | |
| DEC-8 | 2026-10-25 | Read the VUT speed tolerance, printed "+ 1.0 km/h", as ±1.0 km/h, and report the signed deviation. | Protocol 1.2 and 4.3.1 print it the same way. |
| DEC-9 | 2026-10-25 | Take the tire's `mu_road = 0.9` as meeting the surface's minimum peak braking coefficient of 0.9. | The protocol characterizes the surface with a standard test tire; the model has one road friction parameter. |
| DEC-10 | 2026-10-25 | Add a per-wheel slip limiter (idealized ABS), `VehicleComponents.ABSBrake`: algebraic, no events or states; slip band 0.08–0.16; inactive below 1 m/s, full above 2 m/s. **User** | Without it, full braking locks the rear wheels (brake spike). A bias split alone does not prevent lock through the open differential. |
| DEC-11 | 2026-10-25 | `abs_enabled` is a structural parameter, off by default in `Sedan`; the CCRs scenario turns it on. | The Chrono reference vehicle has no ABS. As a runtime parameter, the limiter's equations shifted the lane-change solution by 0.0044 m/s² in lateral acceleration with zero braking, beyond the 0.002 m/s² reproduction tolerance of `validation/sedan_handling/dyad.csv`; as a structural parameter the default build matches it to 3.9×10⁻⁶ m/s². |
| DEC-12 | 2026-10-26 | AEB law (`VehicleComponents.AEBController`): brake on the deceleration required to stop 1.0 m short of an in-path target, a_req = v²/(2(gap − 1.0 m)). The brake request is 0 at a_req = 5 m/s² and rises linearly to 1 at 8 m/s²; a 0.15 s first-order lag models pressure build-up; the throttle is cut once the applied command exceeds 0.02. | The protocol tests the function and does not define it. A TTC threshold with full braking needs a latch, which is discrete state (against DEC-4); the required-deceleration law closes the loop without one. The thresholds are design parameters, reported with a sensitivity study. |
| DEC-13 | 2026-10-26 | Each run starts from rest. A PI speed controller (Kp 0.4, Ki 0.1, back-calculation anti-windup Kt 5) brings the car to the test speed; the target stands 30 s of travel at the test speed ahead of the start; T0 is located on the solution. | Starting the multibody car at speed needs consistent driveline, CVT and tire states. The run cost is about 1.2 s per cell. |
| DEC-14 | 2026-10-26 | The accelerator robot (`VehicleComponents.ThrottleRobot`) arms 6 s of travel before the target and then releases the accelerator at a 5 km/h speed drop. Conduct checks (REQ-SCN-4, REQ-SCN-5) run from T0. | Before arming, the speed is below the release speed during the launch from rest. |

## Declared inputs

The protocol does not give these values. Acceptance uses the nominal value.

| Input | Nominal | Range | Basis |
| --- | --- | --- | --- |
| Target width | 1.712 m | 1.662–1.762 m | TB 025 §1.2, width excluding mirrors, ±50 mm |
| Target length | 4.023 m | 3.973–4.073 m | TB 025 §1.2 |
| VUT width | 1.849 m | 1.80–1.85 m | Extent of `assets/sedan/sedan_chassis_vis.obj`; the protocol width excludes mirrors, and the mesh may include them |
| VUT front, ahead of the chassis frame origin | 2.412 m | — | Forward extent of the same mesh along chassis x |
| VUT front profile | Straight line at the front extent, turning with the vehicle yaw | — | The protocol's seven points come from the manufacturer; none are published for this car |
| Driving side | Left-hand drive | — | Sets the near side (REQ-SCN-6); the model is symmetric |
| AEB thresholds and braking levels | Design parameters | — | Not a protocol input |
