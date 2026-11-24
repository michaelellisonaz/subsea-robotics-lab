## Base class for loads (forces and torques) acting on SimBody instances.
##
## A model adds loads to a body's accumulators in apply(). Simple models only
## override compute_force(), which returns one force through the body origin.
## Models are either global (PhysicsWorld.force_models: every body) or attached
## to one body (SimBody.local_force_models: e.g. a vehicle's thrusters). New
## physical effects are added as new models; the integrator does not change.
class_name ForceModel
extends RefCounted

## Key used in SimBody.force_breakdown / torque_breakdown.
var model_name: String = "force"
var enabled: bool = true
## True for a model that supplies a body's complete hydrodynamic loads; the
## global isotropic drag model then skips that body to avoid double counting.
var replaces_global_drag: bool = false


func apply(body: SimBody, context: StepContext) -> void:
	body.add_force(compute_force(body, context), model_name)


func compute_force(_body: SimBody, _context: StepContext) -> Vector3:
	return Vector3.ZERO
