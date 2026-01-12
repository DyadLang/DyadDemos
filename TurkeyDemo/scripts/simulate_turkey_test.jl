using TurkeyDemo
using ModelingToolkit, DyadInterface

@named model = TurkeySphereTest()
res = @time TransientAnalysis(; model, stop = 14400)

import Plots
Plots.plot(res, idxs=[model.turkey.T_degF[1]])
Plots.plot(res, idxs=[TurkeyDemo.KelvinToFahrenheit(model.T_oven), model.turkey.T_degF[1], TurkeyDemo.KelvinToFahrenheit(model.turkey.surface.T)])

