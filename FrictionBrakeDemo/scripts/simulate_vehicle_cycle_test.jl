using FrictionBrakeDemo
using ModelingToolkit, DyadInterface

@named model = VehicleCycleTest()
res = @time TransientAnalysis(; model, alg = ODEAlg.Rodas5P(), stop = 2000)
sol = rebuild_sol(res)
ModelingToolkit.SciMLBase.successful_retcode(sol) ||
    error("Vehicle-cycle solve failed with return code $(sol.retcode)")
isempty(sol.t) && error("Vehicle-cycle solve returned no time samples")
last(sol.t) == 2000 ||
    error("Vehicle-cycle solve stopped at $(last(sol.t)); expected 2000 s")
all(isfinite, sol.t) && all(isfinite, Array(sol)) ||
    error("Vehicle-cycle solve returned non-finite time or state samples")

using Plots
plot(res, idxs=[model.vehicle_speed_ref.y, model.vehicle.vehicle_speed])
plot(res, idxs=[model.brake_thermal.disk_mass.T, model.brake_thermal.pad_mass.T])
plot(res, idxs=[model.driver.throttle, model.driver.brake])
plot(res, idxs=[model.powertrain.drive.tau, model.brake.shaft.tau])
plot(res, idxs=[model.brake_thermal.heat_disk.Q_flow, model.brake_thermal.heat_pad.Q_flow])

plot(res, idxs = (model.vehicle_speed_ref.y, model.brake_thermal.disk_mass.T))
