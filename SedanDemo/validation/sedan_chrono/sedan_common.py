# Shared setup for the Project Chrono reference simulations of the sedan
# example. Builds the JSON-defined sedan (the same files this example was
# ported from) on a rigid flat terrain, headless, and logs a standard set of
# channels to CSV. See README.md for how to set up PyChrono.
import math
import os
import pychrono as chrono
import pychrono.vehicle as veh

STEP = float(os.environ.get("SEDAN_STEP", "1e-4"))
LOG_HZ = 100
# Tire model selection: "tmeasy" (default, matches the example) or "pac02"
TIRE_JSON = {
    "tmeasy": "sedan/tire/Sedan_TMeasyTire.json",
    "pac02": "sedan/tire/Sedan_Pac02Tire.json",
}[os.environ.get("SEDAN_TIRE", "tmeasy").lower()]


def build_vehicle(init_fwd_vel=0.0):
    veh.SetVehicleDataPath(chrono.GetChronoDataPath() + "vehicle/")
    vehicle = veh.WheeledVehicle(
        veh.GetVehicleDataFile("sedan/vehicle/Sedan_Vehicle.json"), chrono.ChContactMethod_SMC
    )
    vehicle.Initialize(chrono.ChCoordsysd(chrono.ChVector3d(0, 0, 0.5), chrono.QUNIT), init_fwd_vel)
    vehicle.GetChassis().SetFixed(False)
    vehicle.SetChassisVisualizationType(chrono.VisualizationType_NONE)
    vehicle.SetSuspensionVisualizationType(chrono.VisualizationType_NONE)
    vehicle.SetSteeringVisualizationType(chrono.VisualizationType_NONE)
    vehicle.SetWheelVisualizationType(chrono.VisualizationType_NONE)

    engine = veh.ReadEngineJSON(veh.GetVehicleDataFile("sedan/powertrain/Sedan_EngineSimpleMap.json"))
    transmission = veh.ReadTransmissionJSON(
        veh.GetVehicleDataFile("sedan/powertrain/Sedan_AutomaticTransmissionSimpleMap.json")
    )
    vehicle.InitializePowertrain(veh.ChPowertrainAssembly(engine, transmission))

    for axle in vehicle.GetAxles():
        for wheel in axle.GetWheels():
            tire = veh.ReadTireJSON(veh.GetVehicleDataFile(TIRE_JSON))
            vehicle.InitializeTire(tire, wheel, chrono.VisualizationType_NONE)

    terrain = veh.RigidTerrain(vehicle.GetSystem(), veh.GetVehicleDataFile("terrain/RigidPlane.json"))
    terrain.Initialize()
    return vehicle, terrain


def tire_normal_load(wheel):
    # Terrain normal is +z; report the vertical component of the tire force
    return wheel.GetTire().ReportTireForce(None).force.z


HEADER = (
    "t,x,y,z,roll,pitch,yaw,speed,gear,engine_rpm,engine_torque,"
    "throttle,steering,braking,fz_FL,fz_FR,fz_RL,fz_RR,"
    "omega_FL,omega_FR,omega_RL,omega_RR,driveshaft_speed"
)


def log_row(f, time, vehicle, driver_inputs):
    chassis = vehicle.GetChassis()
    pos = chassis.GetPos()
    rot = chassis.GetRot()
    e = rot.GetCardanAnglesXYZ()
    speed = vehicle.GetSpeed()
    engine = vehicle.GetPowertrainAssembly().GetEngine()
    transmission = vehicle.GetPowertrainAssembly().GetTransmission()
    axles = vehicle.GetAxles()
    wheels = [
        axles[0].GetWheel(veh.LEFT), axles[0].GetWheel(veh.RIGHT),
        axles[1].GetWheel(veh.LEFT), axles[1].GetWheel(veh.RIGHT),
    ]
    spindle_omegas = [
        vehicle.GetSpindleOmega(0, veh.LEFT), vehicle.GetSpindleOmega(0, veh.RIGHT),
        vehicle.GetSpindleOmega(1, veh.LEFT), vehicle.GetSpindleOmega(1, veh.RIGHT),
    ]
    row = [
        time, pos.x, pos.y, pos.z, e.x, e.y, e.z, speed,
        transmission.GetCurrentGear(),
        engine.GetMotorSpeed() * 30 / math.pi,
        engine.GetOutputMotorshaftTorque(),
        driver_inputs.m_throttle, driver_inputs.m_steering, driver_inputs.m_braking,
    ]
    row += [tire_normal_load(w) for w in wheels]
    row += spindle_omegas
    row.append(vehicle.GetDriveline().GetOutputDriveshaftSpeed())
    f.write(",".join(f"{v:.6g}" for v in row) + "\n")


def run(t_end, driver_inputs_fn, csv_path, init_fwd_vel=0.0, settle=0.0):
    # Chrono initializes the chassis 0.28 m above ride height, so the vehicle
    # starts with a drop-bounce transient (airborne front axle, wheelspin
    # under throttle). With `settle > 0` the vehicle is held at rest for that
    # long before the driver function is engaged, and logged times are
    # shifted so the driver engages at t = 0 — matching a simulation that
    # starts from the settled configuration.
    vehicle, terrain = build_vehicle(init_fwd_vel)
    n_steps = int(round((t_end + settle) / STEP))
    log_every = int(round(1 / (LOG_HZ * STEP)))
    with open(csv_path, "w") as f:
        f.write(HEADER + "\n")
        for i in range(n_steps):
            time = vehicle.GetSystem().GetChTime()
            if time < settle:
                di = veh.DriverInputs()
                di.m_steering = 0.0
                di.m_throttle = 0.0
                di.m_braking = 0.5
            else:
                di = driver_inputs_fn(time - settle, vehicle)
                if (i - int(round(settle / STEP))) % log_every == 0:
                    log_row(f, time - settle, vehicle, di)
            terrain.Synchronize(time)
            vehicle.Synchronize(time, di, terrain)
            terrain.Advance(STEP)
            vehicle.Advance(STEP)
    print(f"wrote {csv_path}")
    return vehicle
