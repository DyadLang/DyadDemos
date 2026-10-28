# Upstream follow-up draft: Generated behavior block parameter cycles

Suggested issue: **rc2 generated documentation behavior examples create cyclic parameter bindings**.
No issue was filed. The full issue draft and minimal FIR reproduction are in
[the shared upstream report](../../followup-upstream-issues.md#new-draft-generated-behavior-examples-create-self-referential-bindings).

`dyad document HybridTransmission` emits behavior examples for `ECMSController` and `HybridBattery`. Each declares
external symbols with the same parameter names, passes them to the generated
constructor, and calls `full_equations(sys)`. On rc2 the examples throw
`ParameterBindingsGraph`'s cyclic-parameter error for `s_base` and `V_nom`, respectively. The strict
generated-document build remains failed; the physical model was preserved.

Both generated Julia blocks pass against this project’s preserved original 3.4 model. Exact commands, timings and limitations are in [the project validation](followup-validation.md) and shared report.

Expected fix: keep generated symbolic overrides valid with the constructor seeding contract, and execute generated examples with example errors fatal. Do not change the physical model or downgrade example failures to warnings.
