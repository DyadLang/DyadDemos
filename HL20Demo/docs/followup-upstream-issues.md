# Upstream follow-up draft: Generated behavior block parameter cycle

Suggested issue: **rc2 generated documentation behavior examples create cyclic parameter bindings**.
No issue was filed. The full issue draft and minimal FIR reproduction are in
[the shared upstream report](../../followup-upstream-issues.md#new-draft-generated-behavior-examples-create-self-referential-bindings).

`dyad document HL20Demo` emits a behavior example for `shared.HL20Aero` that declares
external symbols with the same parameter names, passes them to the generated
constructor, and calls `full_equations(sys)`. On rc2 the example throws
`ParameterBindingsGraph`'s cyclic-parameter error for `DLG`. The strict
generated-document build remains failed; the physical model was preserved.

The original 3.4 construction fails earlier on undefined `ChallengeComponent`; no successful old full-flight baseline exists. FIR independently demonstrates the cycle regression with an otherwise valid model on both versions.

Expected fix: keep generated symbolic overrides valid with the constructor seeding contract, and execute generated examples with example errors fatal. Do not change the physical model or downgrade example failures to warnings.
