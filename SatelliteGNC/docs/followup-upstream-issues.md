# Upstream follow-up draft: Generated behavior block parameter cycles

Suggested issue: **rc2 generated documentation behavior examples create cyclic parameter bindings**.
No issue was filed. The full issue draft and minimal FIR reproduction are in
[the shared upstream report](../../followup-upstream-issues.md#new-draft-generated-behavior-examples-create-self-referential-bindings).

`dyad document SatelliteGNC` emits behavior examples that declare external
symbols with the same parameter names, pass them to the generated constructors,
and call `full_equations(sys)`. Seven blocks fail on rc2 with
`ParameterBindingsGraph` cycle errors:

| Component | First cycle parameter |
|---|---|
| `AttitudeController` | `Kp_x` |
| `LuenbergerObserver` | `Ixx` |
| `ReactionJet` | `rx` |
| `SatelliteBody` | `Ixx` |
| `SatelliteBody6DOF` | `Ixx` |
| `ThrusterAllocator` | `F_max` |
| `TrapezoidalProfile` | `target_angle` |

All seven identical generated Julia blocks pass against the preserved original
3.4 model. The initial audit tested the first three; the review follow-up tested
the remaining four in 5.078403 s (exit 0, no caught failures). These are symbolic
construction/equation comparisons, not a complete 3.4 site build. Exact commands,
logs and limits are in [the project validation](followup-validation.md) and shared
report. The strict rc2 generated-document build remains failed; the physical
model was preserved.

Expected fix: keep generated symbolic overrides valid with the constructor seeding contract, and execute generated examples with example errors fatal. Do not change the physical model or downgrade example failures to warnings.
