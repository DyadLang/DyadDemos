#!/usr/bin/env julia
"""
Thermal House Comparison Script

Compares two thermal house models over a 3-day period:
1. Original: Winter conditions with constant 7.5kW heater
2. Day/Night: Spring conditions with solar cycle, no heater

Generates a comparison plot showing temperature profiles and solar irradiance.
"""

# Activate the project environment
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using ThermalHouseDemo
using ModelingToolkit, OrdinaryDiffEqDefault
using Plots

println("="^70)
println("THERMAL HOUSE MODEL COMPARISON")
println("="^70)

# ==============================================================================
# RUN SIMULATIONS
# ==============================================================================

println("\n[1/3] Running Original Model (Winter + Constant Heater)...")
println("      - Duration: 3 days")
println("      - Outdoor temperature: 0°C")
println("      - Heater: 7500 W (constant)")
println("      - Solar: None")

model_orig = TestThermalHouse(name=:test_orig)
sys_orig = structural_simplify(model_orig)
prob_orig = ODEProblem(sys_orig, [], (0.0, 259200.0))  # 3 days
sol_original = solve(prob_orig)

if sol_original.retcode == :Success
    println("      ✓ Simulation successful")
else
    println("      ✗ Simulation failed: ", sol_original.retcode)
    exit(1)
end

println("\n[2/3] Running Day/Night Model (Spring + Solar Cycle)...")
println("      - Duration: 3 days")
println("      - Outdoor temperature: 10°C")
println("      - Heater: None")
println("      - Solar: 0-800 W/m² diurnal cycle")

result_daynight = TestDayNightCycle()
sol_daynight = result_daynight.sol

if sol_daynight.retcode == :Success
    println("      ✓ Simulation successful")
else
    println("      ✗ Simulation failed: ", sol_daynight.retcode)
    exit(1)
end

# ==============================================================================
# EXTRACT DATA
# ==============================================================================

println("\n[3/3] Generating comparison plot...")

# Original model data
t_orig = sol_original.t ./ 3600.0  # Convert to hours
T_orig = sol_original[sys_orig.house.thermal_mass.T] .- 273.15  # Convert to °C

# Day/night model data
t_daynight = sol_daynight.t ./ 3600.0  # Convert to hours
T_daynight = sol_daynight[result_daynight.spec.model.house.house.thermal_mass.T] .- 273.15
solar_daynight = [sol_daynight(t, idxs=result_daynight.spec.model.house.solar_cycle.y) 
                  for t in sol_daynight.t]

# ==============================================================================
# CREATE PLOT
# ==============================================================================

p = plot(
    title="Thermal House Comparison (3 Days): Constant Heater vs Solar Cycle",
    xlabel="Time (hours)",
    ylabel="Interior Temperature (°C)",
    legend=:right,
    size=(1200, 600),
    linewidth=2.5,
    grid=true,
    gridstyle=:dot,
    gridalpha=0.3
)

# Plot original model
plot!(p, t_orig, T_orig, 
    label="Winter: 7.5kW Constant Heater (0°C outdoor)",
    color=:blue,
    linewidth=2.5)

# Plot day/night model
plot!(p, t_daynight, T_daynight,
    label="Spring: Solar Cycle, No Heater (10°C outdoor)",
    color=:red,
    linewidth=2.5)

# Add solar irradiance on secondary axis
plot!(twinx(p), t_daynight, solar_daynight ./ 1000,
    ylabel="Solar Irradiance (kW/m²)",
    label="Solar Irradiance",
    color=:orange,
    linestyle=:dash,
    linewidth=2,
    legend=:topright,
    ylims=(0, 1.0))

# Save plot
output_file = joinpath(@__DIR__, "..", "thermal_house_comparison_3days.png")
savefig(p, output_file)

# ==============================================================================
# PRINT SUMMARY
# ==============================================================================

println("\n" * "="^70)
println("RESULTS SUMMARY")
println("="^70)

println("\n📊 Original Model (Winter + Constant Heater):")
println("   Duration:   3 days (72 hours)")
println("   Initial:    ", round(T_orig[1], digits=1), " °C")
println("   Final:      ", round(T_orig[end], digits=1), " °C")
println("   Maximum:    ", round(maximum(T_orig), digits=1), " °C")
println("   Conditions: 0°C outdoor, 7500 W heater (constant), no solar")

println("\n📊 Day/Night Model (Spring + Solar Cycle):")
println("   Duration:     3 days (72 hours)")
println("   Initial:      ", round(T_daynight[1], digits=1), " °C")
println("   Minimum:      ", round(minimum(T_daynight), digits=1), " °C")
println("   Maximum:      ", round(maximum(T_daynight), digits=1), " °C")
println("   Daily swing:  ", round(maximum(T_daynight) - minimum(T_daynight), digits=1), " K")
println("   Conditions:   10°C outdoor, no heater, 0-800 W/m² solar cycle")

println("\n✓ Plot saved to: ", output_file)
println("\n" * "="^70)
