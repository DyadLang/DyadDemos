# ISO double lane change at 12 m/s with Chrono's own path-follower driver.
# The path file starts at ISO (-125, -125); the vehicle is initialized there
# so positions in the log are later shifted to path-relative coordinates.
# The vehicle settles for 3 s before the driver engages (logged as t = 0) so
# the launch is comparable to a simulation starting from the settled pose.
import pychrono as chrono
import pychrono.vehicle as veh
import sedan_common as C


class DLC:
    def __init__(self):
        self.driver = None

    def __call__(self, time, vehicle):
        if self.driver is None:
            path = chrono.ChBezierCurve.Read(veh.GetVehicleDataFile("paths/ISO_double_lane_change.txt"), False)
            self.driver = veh.ChPathFollowerDriver(vehicle, path, "dlc", 12.0)
            self.driver.GetSteeringController().SetGains(0.8, 0, 0)
            self.driver.GetSteeringController().SetLookAheadDistance(5.0)
            self.driver.GetSpeedController().SetGains(0.4, 0, 0)
            self.driver.Initialize()
        self.driver.Synchronize(time)
        self.driver.Advance(C.STEP)
        di = veh.DriverInputs()
        di.m_steering = self.driver.GetSteering()
        di.m_throttle = self.driver.GetThrottle()
        di.m_braking = self.driver.GetBraking()
        return di


if __name__ == "__main__":
    import sedan_common

    # start at the path origin
    orig_build = sedan_common.build_vehicle

    def build_at_path(init_fwd_vel=0.0):
        veh.SetVehicleDataPath(chrono.GetChronoDataPath() + "vehicle/")
        vehicle = veh.WheeledVehicle(
            veh.GetVehicleDataFile("sedan/vehicle/Sedan_Vehicle.json"), chrono.ChContactMethod_SMC
        )
        vehicle.Initialize(
            chrono.ChCoordsysd(chrono.ChVector3d(-125, -125, 0.5), chrono.QUNIT), init_fwd_vel
        )
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
                tire = veh.ReadTireJSON(veh.GetVehicleDataFile(C.TIRE_JSON))
                vehicle.InitializeTire(tire, wheel, chrono.VisualizationType_NONE)
        terrain = veh.RigidTerrain(vehicle.GetSystem(), veh.GetVehicleDataFile("terrain/RigidPlane.json"))
        terrain.Initialize()
        return vehicle, terrain

    sedan_common.build_vehicle = build_at_path
    C.run(25.0, DLC(), "dlc.csv", settle=3.0)
