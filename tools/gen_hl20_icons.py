#!/usr/bin/env python3
"""Regenerate the generated HL20Demo icon SVGs in HL20Demo/assets/.

Standard library only. Two template families cover every generated icon:

  * "block" icons - white inner face, coloured 8-unit border, centred bold
    sans-serif text (optionally rotated -90 deg for tall narrow icons).
  * "group" icons (aero_clcd, aero_cycn) - rounded rect with three text rows.

assets/icon.svg is hand-authored NASA HL-20 clip art and is intentionally not
generated; it is listed in docs/layout/HL20Demo/LAYOUT_NOTES.md.

Usage:
    python3 tools/gen_hl20_icons.py            # rewrite the generated icons
    python3 tools/gen_hl20_icons.py --check    # verify, non-zero exit on diff
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "HL20Demo" / "assets"

# Each entry: filename -> (viewbox w, h, border colour, [(x, y, size, text, rotated)]).
# Coordinates/sizes match the committed SVGs byte for byte.
BLOCK_ICONS = {
    "adjlimit.svg": (1000, 1000, "#e8c7de", [(500, 590, 230, "lim", False)]),
    "aero_air.svg": (1000, 1000, "#d8d8d8", [(500, 520, 150, "air data", False), (500, 700, 120, "+ damping", False)]),
    "aero_icon.svg": (400, 800, "#e8a8c8", [(248, 400, 130, "AERO", True)]),
    "aero_lat.svg": (1000, 1000, "#e8c8a8", [(500, 560, 170, "CY Cl Cn", False)]),
    "aero_lon.svg": (1100, 1150, "#a8c8e8", [(550, 634, 170, "CL CD Cm", False)]),
    "aeroangles.svg": (1000, 1000, "#d7c9f2", [(500, 590, 230, "&#945;&#946;", False)]),
    "airdata.svg": (1000, 1000, "#f2dfc9", [(500, 590, 230, "αβ", False)]),
    "atmosphere.svg": (1000, 1000, "#b8e6e0", [(500, 590, 230, "ATM", False)]),
    "cd.svg": (1000, 1500, "#a8d8a8", [(500, 841, 260, "CD", False)]),
    "cl.svg": (1000, 1500, "#a8d8a8", [(500, 841, 260, "CL", False)]),
    "cm.svg": (1000, 1000, "#a8d8a8", [(500, 590, 230, "Cm", False)]),
    "cn.svg": (1000, 1000, "#a8d8a8", [(500, 590, 230, "Cn", False)]),
    "cr.svg": (1000, 1000, "#a8d8a8", [(500, 590, 230, "Cℓ", False)]),
    "ctrl_pitch.svg": (450, 100, "#f2c1a0", [(225, 74, 70, "NZQ", False)]),
    "ctrl_roll.svg": (150, 100, "#f2c1a0", [(75, 74, 70, "φ", False)]),
    "ctrl_speed.svg": (1000, 1000, "#f2c1a0", [(500, 590, 230, "SB", False)]),
    "ctrl_yaw.svg": (150, 100, "#f2c1a0", [(75, 74, 70, "ψ", False)]),
    "cy.svg": (1000, 1000, "#a8d8a8", [(500, 590, 230, "CY", False)]),
    "dynamics6.svg": (250, 1000, "#84bfed", [(155, 500, 120, "6-DOF", True)]),
    "eulerangles.svg": (1000, 1000, "#d7c9f2", [(500, 590, 230, "&#966;&#952;&#968;", False)]),
    "flightstate.svg": (200, 730, "#f4d58d", [(124, 365, 110, "α·β", True)]),
    "forces.svg": (200, 730, "#f2a9a9", [(124, 365, 120, "F·M", True)]),
    "fullsystem.svg": (1000, 1000, "#84bfed", [(500, 590, 170, "HL-20", False)]),
    "matvec.svg": (1400, 1800, "#d7c9f2", [(700, 1016, 330, "A·u", False)]),
    "mixer.svg": (1000, 1000, "#c9d97f", [(500, 590, 230, "MIX", False)]),
    "poly.svg": (1000, 1000, "#f4d58d", [(500, 590, 230, "x³", False)]),
    "quatdcm.svg": (300, 250, "#d7c9f2", [(150, 167, 120, "DCM", False)]),
    "quatkin.svg": (1000, 800, "#c9e2f2", [(500, 480, 230, "q̇", False)]),
    "quatrot.svg": (250, 1000, "#d7c9f2", [(155, 500, 150, "q⊗", True)]),
    "rotdyn.svg": (1000, 800, "#c9e2f2", [(500, 480, 230, "ω̇", False)]),
    "switch.svg": (1000, 1000, "#e8c7de", [(500, 590, 300, "⤨", False)]),
    "table.svg": (1000, 1000, "#e8c7de", [(500, 590, 400, "▦", False)]),
    "transdyn.svg": (1000, 800, "#c9e2f2", [(500, 480, 230, "ẍ", False)]),
    "veh_airdata.svg": (400, 590, "#b8e6e0", [(200, 249, 130, "AIR", False), (200, 446, 130, "DATA", False)]),
    "veh_icon.svg": (100, 300, "#84bfed", [(62, 150, 60, "HL-20", True)]),
    "veh_outputs.svg": (300, 400, "#b8e6e0", [(150, 172, 88, "UNIT", False), (150, 305, 88, "CONV", False)]),
}

# Rounded-rectangle group icons: filename -> (line1, line2, caption).
GROUP_ICONS = {
    "aero_clcd.svg": ("CL", "CD", "lift + drag"),
    "aero_cycn.svg": ("CY", "Cn", "side + yaw"),
}


def block_svg(w, h, color, texts):
    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}">',
        f'  <path fill="#fff" stroke-width="0" d="M4 4h{w - 8}v{h - 8}H4z"/>',
        f'  <path fill="{color}" stroke-width="0" d="M{w - 8} 8v{h - 16}H8V8zm8-8H0v{h}h{w}z"/>',
    ]
    for x, y, size, body, rotated in texts:
        transform = f' transform="rotate(-90 {x} {y})"' if rotated else ""
        lines.append(
            f'  <text x="{x}" y="{y}" font-family="sans-serif" font-size="{size}"'
            f' font-weight="bold" text-anchor="middle" fill="#12203a"{transform}>{body}</text>'
        )
    lines.append("</svg>")
    return "\n".join(lines) + "\n"


def group_svg(line1, line2, caption):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000">\n'
        '  <rect x="0" y="0" width="1000" height="1000" fill="#f5f0ff" stroke="#5e35b1" stroke-width="8" rx="40"/>\n'
        f'  <text x="500" y="300" font-family="Helvetica, Arial, sans-serif" font-size="190" font-weight="bold" fill="#311b92" text-anchor="middle">{line1}</text>\n'
        f'  <text x="500" y="570" font-family="Helvetica, Arial, sans-serif" font-size="190" font-weight="bold" fill="#311b92" text-anchor="middle">{line2}</text>\n'
        f'  <text x="500" y="800" font-family="Helvetica, Arial, sans-serif" font-size="110" fill="#4527a0" text-anchor="middle">{caption}</text>\n'
        '</svg>\n'
    )


def generated():
    out = {}
    for name, (w, h, color, texts) in BLOCK_ICONS.items():
        out[name] = block_svg(w, h, color, texts)
    for name, (line1, line2, caption) in GROUP_ICONS.items():
        out[name] = group_svg(line1, line2, caption)
    return out


def main():
    check = "--check" in sys.argv[1:]
    want = generated()
    bad = []
    for name, text in sorted(want.items()):
        path = ASSETS / name
        current = path.read_text() if path.exists() else None
        if current != text:
            bad.append(name)
            if not check:
                path.write_text(text)
    if bad:
        verb = "differ" if check else "rewrote"
        for name in bad:
            print(f"{verb}: {name}")
        if check:
            return 1
    print(f"{len(want)} icons {'in sync' if check and not bad else 'up to date'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
