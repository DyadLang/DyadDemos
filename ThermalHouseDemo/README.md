# ThermalHouseDemo

<img src="./assets/icon.svg" width="96" align="right"/>

## The problem

A house in winter leaks heat. Some escapes through the walls, roof, floor,
windows and doors; the rest rides out on draughts, as warm indoor air slips
through gaps and cold outdoor air slips in. A heating system has to put back
everything that leaks out, and two questions follow from that:

- **How big does the heater need to be?** Point a fixed 7.5 kW heater at a house
  on a 0 C day and watch where the indoor temperature settles.
- **How well does a thermostat hold the temperature?** Give the same house a
  controller, ask for 21.1 C, and watch it get there.

This demo models a 1000 sq ft house in Dyad and answers both.

## The model

The house is one warm lump — the indoor air plus the drywall and floor slab that
store heat with it. Heat flows into that lump and out of it along these paths:

| Path | Component | What it stands for |
| --- | --- | --- |
| Walls, roof, floor, windows, doors | one `ThermalConductor` each | Heat conducted out through the shell of the building. Each surface has its own insulation quality, so a window leaks far faster than a roof. |
| Draughts | `infiltration_loss` | Air trading places through gaps in the building, carrying its heat with it. Sized by how many times per hour the house swaps its air. |
| Sunlight | `solar_input` | Sun coming through the windows and warming the room. |
| People, lights, appliances | `internal_gains` | Everything indoors that gives off heat without meaning to. |
| Heater | `heater` | The heating system, the one input you control. |
| Stored heat | `thermal_mass` | The air and structure soaking up heat, which is why the house warms and cools slowly rather than instantly. |

### ThermalHouse -- the house on its own

`dyad/ThermalHouse.dyad`. You hand it heater power (`Q_heater`), sunshine
(`solar_irradiance`) and the outdoor temperature (`T_ambient`); it reports the
indoor temperature (`T_interior`). Nothing here decides how much to heat -- you
fix the heater and watch what the house does, which is what makes it the sizing
experiment.

Two more definitions sit in the same file. `TestThermalHouse` wires constant
signals into the house: a 7500 W heater, 0 C outdoors, no sun.
`TestHouseWinterDesign` runs that setup for 7200 seconds.

### ThermalHouseControlled -- the house with a thermostat

`dyad/ThermalHouseControlled.dyad`. This one wraps `ThermalHouse` in a PI
controller, so you hand it a target temperature (`T_setpoint`) rather than a
heater setting. The controller reads the indoor temperature back, compares it to
the target, and raises or lowers the heater to close the gap, never below 0 W
and never above `Q_max`.

Two more definitions sit in the same file. `TestThermalHouseControlled` holds
the target at 21.1 C and the outdoors at 0 C. `TestControlledHouseWinterDesign`
starts the house cold, at 15.5 C, and runs 7200 seconds of warm-up.

## Notes

### Getting started

Download this folder to your machine and open it in VS Code with the [Dyad
extension](https://help.juliahub.com/dyad/dev/getting_started/).

### Sizing the heater: does 7.5 kW warm the house?

```julia
using ThermalHouseDemo
using Plots

sol = TestHouseWinterDesign()
plot(sol)
```

### Tracking a setpoint: how fast does the thermostat get there?

```julia
sol = TestControlledHouseWinterDesign()
plot(sol)
```

### Changing the numbers

Every analysis takes keyword arguments, so you can rerun it against a different
house or a different day:

```julia
# Run for 4 hours instead of 2
sol = TestHouseWinterDesign(stop=14400.0)

# Make the controller more aggressive
sol = TestControlledHouseWinterDesign(k_p=15000.0, T_i=300.0)
```
