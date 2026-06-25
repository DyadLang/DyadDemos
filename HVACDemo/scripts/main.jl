# ---------------------------------------------------------------------------
# main.jl
#
# Runs the HVAC vapor-compression cycle analysis and plots a few of the most
# instructive variables. Meant as a starting point for exploring the model.
#
# Run from the project root with the project environment active:
#   julia --project=. scripts/plot_results.jl
# or, inside a REPL:
#   include("scripts/plot_results.jl")
# ---------------------------------------------------------------------------

using HVACDemo
using HVACComponents
using DyadInterface      # provides `symbolic_container`
using Plots

# --- 1. Run the analysis -----------------------------------------------------
# This is a stiff two-phase + moist-air model integrated to t = 1400 s with
# Rodas5P. The first run also compiles, so expect it to take a few minutes.
result = CompleteCycleFixedControls_SRP_Analysis()

sol   = result.sol                    # the underlying ODESolution
model = symbolic_container(result)    # lets us index variables by name

println("solver retcode: ", sol.retcode)
println("simulated:      ", sol.t[1], " s  →  ", sol.t[end], " s")

# --- 2. Pull out interesting variables --------------------------------------
# Indexing `sol[expr]` returns the time series; `sol.t` is the time vector.
# A helper keeps unit conversions readable.
ts      = sol.t
get(sym) = sol[sym]

# Refrigerant circuit
p_high  = get(model.compressor.pd)        .* 1e-5   # discharge (condenser) pressure [bar]
p_low   = get(model.compressor.ps)        .* 1e-5   # suction (evaporator) pressure  [bar]
p_ratio = get(model.compressor.pRat)                # pressure ratio                 [-]
mdot_c  = get(model.compressor.m_flow_comp) .* 1e3  # refrigerant flow (compressor)  [g/s]
mdot_v  = get(model.LEV.m_flow)             .* 1e3  # refrigerant flow (valve)       [g/s]
power   = get(model.compressor.shaftPower)          # compressor shaft power         [W]
T_dis   = get(model.compressor.TDischarge) .- 273.15  # discharge temperature        [°C]
T_suc   = get(model.compressor.TSuction)   .- 273.15  # suction temperature          [°C]

# Air side (what the occupant actually feels)
T_air_cond = get(model.condenser.air_medium_out.T)  .- 273.15  # condenser air out [°C]
T_air_evap = get(model.evaporator.air_medium_out.T) .- 273.15  # evaporator air out [°C]

# --- 3. Build the plots ------------------------------------------------------
gr()
common = (; lw = 2, legend = :best, xlabel = "time [s]", grid = true)

p1 = plot(ts, p_high; label = "discharge (high)", ylabel = "pressure [bar]",
          title = "Refrigerant pressures", common...)
plot!(p1, ts, p_low; label = "suction (low)")

p2 = plot(ts, mdot_c; label = "compressor", ylabel = "mass flow [g/s]",
          title = "Refrigerant mass flow", common...)
plot!(p2, ts, mdot_v; label = "expansion valve")

p3 = plot(ts, power; label = "shaft power", ylabel = "power [W]",
          title = "Compressor power", common...)

p4 = plot(ts, T_dis; label = "discharge", ylabel = "temperature [°C]",
          title = "Refrigerant temperatures", common...)
plot!(p4, ts, T_suc; label = "suction")

p5 = plot(ts, T_air_cond; label = "condenser air out (heated)",
          ylabel = "temperature [°C]", title = "Air outlet temperatures", common...)
plot!(p5, ts, T_air_evap; label = "evaporator air out (cooled)")

p6 = plot(ts, p_ratio; label = "p_discharge / p_suction", ylabel = "ratio [-]",
          title = "Compressor pressure ratio", common...)

fig = plot(p1, p2, p3, p4, p5, p6; layout = (2, 3), size = (1400, 800),
           plot_title = "HVAC vapor-compression cycle — overview")

# --- 4. Show and save --------------------------------------------------------
outfile = joinpath(@__DIR__, "../cycle_overview.png")
savefig(fig, outfile)
println("saved figure to: ", outfile)
display(fig)
