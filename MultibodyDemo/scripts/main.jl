using MultibodyDemo
using MultibodyComponents
using GLMakie                 # load a Makie backend BEFORE calling render
using DyadInterface: symbolic_container


################################################################
########### 1. PENDULUM ###########
################################################################

result1 = PendulumTransient()  # runs the analysis

# 1. Single interactive frame at t = 1.0 s (slider window)
fig, t, scene = MultibodyComponents.render(result1, 1.0)
display(fig)

# 2. Animation of the full trajectory -> writes an mp4 in the working dir
MultibodyComponents.render(result1)

# 3. Custom camera / output file / frame tracing, using model + sol directly
model = symbolic_container(result1)
sol   = result1.sol
MultibodyComponents.render(model, sol;
    filename  = "pendulum_trace.mp4",
    framerate = 30,
    x = 2, y = 0.5, z = 2,        # camera position
    traces = [model.body.frame_a] # draw the path the body sweeps
)


################################################################
########### 2. Spring Damper ###########
################################################################

result2 = SpringDamperSystemTestAnalysis()  # runs the analysis

# 1. Single interactive frame at t = 1.0 s (slider window)
fig, t, scene = MultibodyComponents.render(result2, 1.0)
display(fig)

# 2. Animation of the full trajectory -> writes an mp4 in the working dir
MultibodyComponents.render(result2)

# 3. Custom camera / output file / frame tracing, using model + sol directly
model = symbolic_container(result2)
sol   = result2.sol
MultibodyComponents.render(model, sol;
    filename  = "spring-damper_trace.mp4",
    framerate = 30,
    x = 2, y = 0.5, z = 2,        # camera position
    traces = [model.body.frame_a] # draw the path the body sweeps
)


################################################################
########### 3. Balancing Robot ###########
################################################################

result3 = DyadBalans2DAnalysis()  # runs the analysis

# 1. Single interactive frame at t = 1.0 s (slider window)
fig, t, scene = MultibodyComponents.render(result3, 1.0)
display(fig)

# 2. Animation of the full trajectory -> writes an mp4 in the working dir
MultibodyComponents.render(result3)

# 3. Custom camera / output file / frame tracing, using model + sol directly
model = symbolic_container(result3)
sol   = result3.sol
MultibodyComponents.render(model, sol;
    filename  = "balancing-robot_trace.mp4",
    framerate = 30,
    x = 2, y = 0.5, z = 2,        # camera position
    traces = [model.body_mass.frame_a] # draw the path the body sweeps
)


################################################################
########### 4. Car ###########
################################################################

result4 = TwoTrackModelTestAnalysis()  # runs the analysis

# 1. Single interactive frame at t = 1.0 s (slider window)
fig, t, scene = MultibodyComponents.render(result4, 1.0)
display(fig)

# 2. Animation of the full trajectory -> writes an mp4 in the working dir
MultibodyComponents.render(result4)

# 3. Custom camera / output file / frame tracing, using model + sol directly
model = symbolic_container(result4)
sol   = result4.sol
MultibodyComponents.render(model, sol;
    filename  = "car_trace.mp4",
    framerate = 30,
    x = 15, y = 15, z = 10,        # camera position
    traces = [model.body.frame_a] # draw the path the body sweeps
)