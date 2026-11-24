# Resolve a mesh or data asset shipped with the sedan model to an absolute path.
# The meshes (chassis, rim, tire) and the Pac02 tire property file originate from
# the Project Chrono vehicle data set, https://github.com/projectchrono/chrono
# (data/vehicle/sedan), licensed BSD-3-Clause.
sedan_asset(name) = normpath(joinpath(@__DIR__, "..", "assets", "sedan", name))
