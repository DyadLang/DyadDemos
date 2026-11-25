# Full-throttle straight-line acceleration: hold zero throttle for 1 s, then
# step the throttle to 1 and hold for 16 s. The vehicle settles for 3 s before
# the driver engages (logged as t = 0) so the launch is comparable to a
# simulation starting from the settled pose.
import pychrono.vehicle as veh
import sedan_common as C


def driver(time, vehicle):
    di = veh.DriverInputs()
    di.m_steering = 0.0
    di.m_throttle = 0.0 if time < 1.0 else 1.0
    di.m_braking = 0.0
    return di


if __name__ == "__main__":
    C.run(17.0, driver, "accel.csv", settle=3.0)
