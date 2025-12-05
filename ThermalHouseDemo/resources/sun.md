# A dummy's guide to solar irradiance

Solar irradiance is the amount of solar energy that is incident on a surface per unit area.  It is typically measured in watts per square meter (W/m²).

A simple formula of solar irradiance (proportionally) relative to the time of day is `max(0, sin(time/3600/24* 2*pi - pi/2))^2` where `time` is the time in seconds since the start of the day.