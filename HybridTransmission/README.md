# HybridTransmission
  
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

6. Type `using HybridTransmission`.  This will load your model library.

7. Type `World()` to run a simulation of the `Hello` model.  The first time you run it,
   this might take a few seconds, but each successive time you run it, it should be very fast.

8. To see simulation results type `using Plots` (and answer `y` if asked if you want
   to add it as a dependency).

9. To plot results of the `World` simulation, simply type `plot(World())`.

10. You can plot variations on that simulation using keyword arguments.  For example,
    try `plot(World(stop=20, k=4))`.
   
# Demo Notes
1. This is a model of a torque-split hybrid transmission, and follows an ECMS 
(Equivalent Consumption Minimization Strategy) control strategy to split torque
demand between the battery and the engine
2. ECMS: the core principle is that in real-time, a weight cost that is the sum of 
fuel-burn and battery drain is minimized. The relative costs of fuel burn and battery
drain are deteremined by an equivalent factor. In this model, an effective equivalent
factor is set dynamically. 
3. Fuel burn is determed by a BFSC (Brake Specific Fuel Consumption) map in the engine
component, expressed as polynomials. This was extracted by our agent from a book called 
Vehicle Propulsion Systems
4. The battery is a very simple equivalent circuit lumped parameter soc estimator, 
loosely based on a Nickel Metal Hydride chemistry. This was developed just for the 
control systems development.
5. A standard EPA Highway Drive cycle was downloaded from the internet by the agent
and used as a source block. Vehicle speed tracking is not the focus of this model so
a simple proportional law is incorporated in the controller.
6. The vehicle is modeled as a simple lumped mass with rolling resistance and aerodynamic drag.
7. The coupling mechanism is modeled as an ideal planetary gear which actuates two
electric motors MG1 and MG2

## Prompts used for a typical demo: 
1. Summarize the models in this repo
2. Please take a look at hybrid_full_cycle.png. The controller seems to fail charge sustaining operation. Can the controller be tuned to improve performance? Provide an assessment. 
3. Can you write an optimization script to tune the controller and make a new plot just like the full cycle one?

## Future Improvements to the Model
1. Perfect speed tracking through a separate closed loop PID 
2. Higher fidelity battery model 
3. This model operates only in hybrid mode. With state machines you can operate this
in pure EV or pure gas mode