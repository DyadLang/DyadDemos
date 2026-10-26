# Optional rendering and artifact follow-up

No new issue was filed. The [shared diagnostic draft](../../followup-upstream-issues.md#optional-rendering-diagnostics-observations-no-new-issue-filed) distinguishes expected missing-DISPLAY errors on both runtimes from the earlier MultibodyComponents.Render/Makie dependency diagnostic.

The fresh rc2 explicit-import probe successfully loaded Render (MultibodyComponents 0.3.0, Makie 0.24.16) and retried extensions; it did not reproduce the earlier dependency diagnostic or validate a GUI. A useful upstream report needs the original failing package-test sandbox context. MultibodyComponents is absent from the 3.4 distribution.

Generated docs are separately blocked by the DyadDAQP_jll 0.10.3 artifact HTTP 403. Both handwritten CairoMakie example blocks and actual SVG export passed. This access failure does not establish a compiler/library defect.

After task access to `github.com` was granted, the unchanged generation retry
still failed at that release URL with HTTP 403 CONNECT-tunnel rejection
(13.352420 s, exit 1). See the [retry evidence](followup-validation.md#artifact-access-retry).
No upstream issue is justified by this access result alone.
