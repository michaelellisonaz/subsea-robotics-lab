## Data handed to every system during one fixed simulation step.
## A single instance is reused for the whole run to avoid per-step allocation.
class_name StepContext
extends RefCounted

## Step duration, s.
var dt: float = 0.0
## Simulation time at the start of the step, s.
var sim_time: float = 0.0
var environment: EnvironmentConfig
var world: WorldModel
## All simulation objects (lets e.g. a gripper find objects to grasp).
var objects: ObjectRegistry
