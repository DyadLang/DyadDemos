# Upstream documentation follow-up draft

Suggested issue: **large inline component SVG makes generated documentation exceed Documenter’s default HTML size limit**. No issue was filed.

The generated FrictionBrake component page is 744.67 KiB and exceeds the unchanged 200 KiB HTML limit after its examples execute. The same generated SVG in a minimal page also exceeds the limit on 3.4 (722.04 KiB). Preserve the icon and emit large SVG as an external asset or compact it; do not disable the size limit to claim success.

The [full issue draft and reproduction](../../followup-upstream-issues.md#draft-inline-svg-makes-an-otherwise-executable-generated-site-fail-html-limits) records exact files, sizes, commands and the old-generator comparison limit. The two numerical/plotting script defects are fixed locally and predate the upgrade; they are not upstream issues.
