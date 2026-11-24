# Step steer: a proportional cruise controller (same law as the example's
# SpeedController) holds 15 m/s; at t = 12 s the steering input steps to 0.1.
# The vehicle settles for 3 s before the driver engages (logged as t = 0) so
# the launch is comparable to a simulation starting from the settled pose.
import pychrono.vehicle as veh
import sedan_common as C

V_REF = 15.0
KP = 0.4


def driver(time, vehicle):
    di = veh.DriverInputs()
    u = KP * (V_REF - vehicle.GetSpeed())
    di.m_throttle = min(1.0, max(0.0, u))
    di.m_braking = min(1.0, max(0.0, -u))
    di.m_steering = 0.0 if time < 12.0 else 0.1
    return di


if __name__ == "__main__":
    C.run(20.0, driver, "step_steer.csv", settle=3.0)
