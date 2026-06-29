Simulate TrimCase0PitchPulseAuto and create a 3×2 CairoMakie summary plot. Save it to the root directory at px_per_unit=2, figure size ~(1000, 750).

Title: "HL-20 Pitch Pulse Dynamic Check — NASA TM-107580 Appendix F, Trim 0" Subtitle: "1° aft stick t=1→2s · 300 KEAS · 10,000 ft · SAS+Autospeed ON"

Every panel gets a light-red semi-transparent vertical shaded band (vspan!) from t=1 to t=2 marking the pulse window. All x-axes span 0–10 s. Only the bottom row gets "Time [s]" x-labels. Dashed gray horizontal grid lines on all panels.

Panel (1,1) — "Pilot Pitch Stick": Dark gray line: pilot_pitch.y (label "DCPILOT"). Y-axis [°].

Panel (1,2) — "Pitch Rate": Blue line: pitch rate from veh.QDEG converted to °/s (label "QDEG"). Dashed gray horizontal line at 1.5 °/s labeled "NASA ~1.5°/s". Y-axis [°/s].

Panel (2,1) — "Angle of Attack": Red line: veh.fs.alpha_deg (label "α"). Dashed pink horizontal line at the t=0 trim value (label "trim"). Y-axis [°].

Panel (2,2) — "Elevator Command": Orange line: pitch.DECMD output in ° (label "DECMD"). Dashed gray horizontal line at 5.5° labeled "trim 5.5°". Y-axis [°].

Panel (3,1) — "Speedbrake (Autospeed)": Green line: speed.DSBCMD output in ° from the autospeed loop (label "DSBCMD"). Y-axis [°].

Panel (3,2) — "Wing Flap Position": Purple line: mixer.DLE in ° (label "DLE"). Dashed gray horizontal line at 5.5° labeled "trim 5.5°". Y-axis [°].

Each curve should have a legend entry positioned in the right half of the panel. Use axislegend with framevisible=false.




































Run the pitch-pulse closed-loop analysis with autospeed engaged on the speedbrake — implement the autospeed law faithfully from TM-107580 Appendix B, page B-10 (assets/shared/scanned_pages/appB_p050-050.png) in a separate harness, leaving the golden/manual model untouched — and create a 3×2 CairoMakie summary plot. Save it to the root directory at px_per_unit=2, figure size ~(1000, 750).

Title: "HL-20 Pitch Pulse Dynamic Check — NASA TM-107580 Appendix F, Trim 0" Subtitle: "1° aft stick t=1→2s · 300 KEAS · 10,000 ft · SAS+Autospeed ON"

Every panel gets a light-red semi-transparent vertical shaded band (vspan!) from t=1 to t=2 marking the pulse window. All x-axes span 0–10 s. Only the bottom row gets "Time [s]" x-labels. Dashed gray horizontal grid lines on all panels.

Panel (1,1) — "Pilot Pitch Stick": Dark gray line: pulse_add.y (label "DCPILOT"). Y-axis [°].

Panel (1,2) — "Pitch Rate": Blue line: pitch rate from vehicle.QDEG converted to °/s (label "QDEG"). Dashed gray horizontal line at 1.5 °/s labeled "NASA ~1.5°/s". Y-axis [°/s].

Panel (2,1) — "Angle of Attack": Red line: vehicle.flight.alpha_deg (label "α"). Dashed pink horizontal line at the t=0 trim value (label "trim"). Y-axis [°].

Panel (2,2) — "Elevator Command": Orange line: pitch_ctrl.DECMD output in ° (label "DECMD"). Dashed gray horizontal line at 5.5° labeled "trim 5.5°". Y-axis [°].

Panel (3,1) — "Speedbrake (Autospeed)": Green line: speed_ctrl.DSBCMD output in ° from the autospeed loop (label "DSBCMD"). Y-axis [°].

Panel (3,2) — "Wing Flap Position": Purple line: mixer.surf.u[5] in ° (label "DLE"). Dashed gray horizontal line at 5.5° labeled "trim 5.5°". Y-axis [°].

Each curve should have a legend entry positioned in the right half of the panel. Use axislegend with framevisible=false.