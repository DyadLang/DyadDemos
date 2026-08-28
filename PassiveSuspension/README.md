# PassiveSuspension
  
## Getting Started
  
This library was created with the Dyad Studio VS Code extension.  Your Dyad
models should be placed in the `dyad` directory and the files should be
given the `.dyad` extension.  Several such files have already been placed
in there to get you started.  The Dyad compiler will compile the Dyad models
into Julia code and place it in the `generated` folder.  Do not edit the
files in that directory or remove/rename that directory.

A complete tutorial on using Dyad Studio can be found [here](#).  But you
can run the provided example models by doing the following:

1. Run `Julia: Start REPL` from the command palette.

2. Type `]`.  This will take you to the package manager prompt.

3. At the `pkg>` prompt, type `instantiate` (this downloads all the Julia libraries
   you will need, and the very first time you do it it might take a while).

4. From the same `pkg>` prompt, type `test`.  This will test to make sure the models
   are working as expected.  It may also take some time but you should eventually
   see a result that indicates 2 of 2 tests passed.

5. Use the `Backspace`/`Delete` key to return to the normal Julia REPL, it should
   look like this: `julia>`.

6. Type `using PassiveSuspension`.  This will load your model library.

7. Type `World()` to run a simulation of the `Hello` model.  The first time you run it,
   this might take a few seconds, but each successive time you run it, it should be very fast.

8. To see simulation results type `using Plots` (and answer `y` if asked if you want
   to add it as a dependency).

9. To plot results of the `World` simulation, simply type `plot(World())`.

10. You can plot variations on that simulation using keyword arguments.  For example,
    try `plot(World(stop=20, k=4))`.

# Notes
1. In this library, we can perform a comparison of an active suspension system 
and an equivalent passive suspension system. 
2. The active suspension system is an example model from DyadExampleComponents,
it uses a control system and an ideal actuator to damp out the disturbance from the road. 
3. The passive suspension model tries to damp out the disturbance using just 
natural damping from the mass spring damper. 
4. A second difference is that we are using an ISO 8608 Class C disturbance
profile as the external disturbance. We notice that in this passive suspension model
that the damping system does not provide adequate rider comfort. The metric for rider
comfort is 
5. So now we ask the agent to either find appropriate damper values in the suspension
to ensure rider comfort. Specifically, we can conduct a parameter sweep or design
optimization for the damper values to ensure rider comfort.
6. What does rider comfort mean? The ISO 2631-1 defines several levels of rider comfort. 
For a class C road - which is an average to poor quality paved road, can we achieve the
top level of comfort at 20 meters per second? What trade offs do we make?
7. When we get the final result, can we make an animation showing the system vibrating
in response to the Class C profile?