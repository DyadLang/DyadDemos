using CoffeeMugDemo
using ModelingToolkit, DyadInterface
using Plots

# Simulate espresso system without spoon
@named model = EspressoCupSystemModular()
res = @time TransientAnalysis(; model, alg = "auto", abstol = 10.0e-3, reltol = 1.0e-3, start = 0.0, stop = 6000)

plot(res, idxs=[model.coffeeMug.espressoTemp_degC, model.coffeeMug.cupMass.T - 273.15, model.hand.handMass.T - 273.15, model.environment.T - 273.15])

# Simulate espresso system with spoon
@named model2 = EspressoCupSystemWithSpoon()
res2 = @time TransientAnalysis(; model=model2, alg = "auto", abstol = 10.0e-3, reltol = 1.0e-3, start = 0.0, stop = 6000)

plot(res2, idxs=[model2.coffeeMug.espressoTemp_degC, model2.coffeeMug.cupMass.T - 273.15, model2.hand.handMass.T - 273.15, model2.spoon.spoonMass.T - 273.15, model2.environment.T - 273.15])

# Compare espresso temperature with and without spoon
plot(res, idxs=[model.coffeeMug.espressoTemp_degC])
plot!(res2, idxs=[model2.coffeeMug.espressoTemp_degC])

