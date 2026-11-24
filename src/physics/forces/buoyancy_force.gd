## Archimedes buoyancy: F = rho * g * V * f, acting straight up (+Y) at the
## body's centre of buoyancy. Because it acts at the CB, a rigid body whose CB
## lies above its CG feels a restoring moment when tilted.
##
## f is the submerged fraction: with SimBody.submersion_height = 0 the body is
## fully submerged below the surface and fully emerged above it; otherwise f
## grows linearly as a body of that height enters the water. The CB is not
## moved by partial submergence (simplification).
class_name BuoyancyForce
extends ForceModel


func _init() -> void:
	model_name = "buoyancy"


func apply(body: SimBody, context: StepContext) -> void:
	if body.displaced_volume <= 0.0:
		return
	var fraction := body.submerged_fraction()
	if fraction <= 0.0:
		return
	var env := context.environment
	var force := Vector3(0.0, env.water_density * env.gravity * body.displaced_volume * fraction, 0.0)
	body.add_force_at_point(force, body.local_to_world_point(body.center_of_buoyancy), model_name)
