# Settle test: zero driver inputs for 4 s; the last row gives the static
# per-corner tire loads and chassis pose.
import pychrono.vehicle as veh
import sedan_common as C


def driver(time, vehicle):
    di = veh.DriverInputs()
    di.m_steering = 0.0
    di.m_throttle = 0.0
    di.m_braking = 0.0
    return di


if __name__ == "__main__":
    C.run(4.0, driver, "settle.csv")
