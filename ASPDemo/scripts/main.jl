using ASPDemo
using Plots
using DyadInterface

result = simbenchplant()

sys = artifacts(result, :SimplifiedSystem)
plot(result; idxs = [sys.blower1.Q_air, sys.blower2.Q_air, sys.blower3.Q_air])

plot(result; idxs=[sys.source.port.Q]) # incoming flow rate
plot(result; idxs=[sys.sinkEffluent.port.Q]) # clean water flow rate
plot(result; idxs=[sys.PI1.y]) # control signal
plot(result; idxs=[sys.PI2.y]) # control signal
plot(result; idxs=[sys.blower1.Q_air, sys.blower2.Q_air, sys.blower3.Q_air]) # blower air flow rate (1/2 are fixed, 3 is controlled)
plot(result; idxs=[sys.recyclePump.portOut.Q, sys.returnPump.portOut.Q, sys.wastePump.portOut.Q]) # flow rates from pumps
plot(result; idxs=[sys.sensor_NO.Sno, sys.sensor_O2.So]) # sensor readings
plot(result; idxs=[sys.sensor_effluent.COD]) # chemical oxygen demand (how clean the water is, less is more clean)
plot(result; idxs=[sys.sensor_effluent.TSS]) # total suspended solid (how clean the water is, less is more clean)