## Physics framework: computes loads on SimBody objects and integrates them.
##
## Each fixed step, for every dynamic body:
##   1. clear the body's load accumulators;
##   2. apply all enabled global force models, then the body's own models;
##   3. body.integrate()  - point mass (SimBody) or 6-DOF (RigidSimBody);
##   4. apply world constraints (domain bounds, seabed non-penetration of the
##      body origin as a safety net).
##
## Environment parameters (density, viscosity, gravity, current) reach the
## bodies only through force models, so new physical effects are added as new
## models rather than by editing the integrators. Godot's built-in physics
## engine is not used, which keeps stepping deterministic and on the
## simulation clock.
class_name PhysicsWorld
extends RefCounted

var force_models: Array[ForceModel] = []
## Keep each body origin above the seabed (+ bottom_clearance).
var seabed_constraint_enabled: bool = true
## Keep bodies inside the horizontal simulation domain.
var bounds_constraint_enabled: bool = true
## Coulomb friction coefficient for point bodies resting on the seabed or a structure.
var friction_coefficient: float = 0.6


func add_default_models() -> void:
	add_force_model(GravityForce.new())
	add_force_model(BuoyancyForce.new())
	add_force_model(HydrodynamicDragForce.new())


func add_force_model(model: ForceModel) -> void:
	if not force_models.has(model):
		force_models.append(model)


func remove_force_model(model: ForceModel) -> void:
	force_models.erase(model)


func get_force_model(model_name: String) -> ForceModel:
	for model in force_models:
		if model.model_name == model_name:
			return model
	return null


func step(bodies: Array[SimBody], context: StepContext) -> void:
	for body in bodies:
		if not body.is_dynamic:
			continue
		if body.effective_mass() <= 0.0:
			push_warning("SimBody '%s' has non-positive mass; skipped." % body.display_name)
			continue
		body.clear_loads()
		for model in force_models:
			if model.enabled:
				model.apply(body, context)
		for model in body.local_force_models:
			if model.enabled:
				model.apply(body, context)
		body.integrate(context)
		_apply_constraints(body, context.world, context.dt)


func _apply_constraints(body: SimBody, world: WorldModel, dt: float) -> void:
	if bounds_constraint_enabled and not world.is_within_bounds(body.position):
		var clamped := world.clamp_to_bounds(body.position)
		if clamped.x != body.position.x:
			body.velocity.x = 0.0
		if clamped.z != body.position.z:
			body.velocity.z = 0.0
		body.position = clamped
	if body.collision_radius > 0.0 and not world.structures.is_empty():
		var hit := world.structure_penetration(body.position, body.collision_radius)
		if not hit.is_empty():
			var normal: Vector3 = hit["normal"]
			body.position += normal * float(hit["depth"])
			var into := body.velocity.dot(normal)
			if into < 0.0:
				body.velocity -= normal * into
			_apply_friction(body, normal, dt)
			body.in_seabed_contact = true
	if seabed_constraint_enabled:
		var floor_y := world.seabed_y_at(body.position.x, body.position.z) + body.bottom_clearance
		if body.position.y <= floor_y:
			body.position.y = floor_y
			if body.velocity.y < 0.0:
				body.velocity.y = 0.0
			_apply_friction(body, Vector3.UP, dt)
			body.in_seabed_contact = true


# Coulomb friction for a body resting on a surface: removes up to
# mu · N / m · dt of tangential speed per step, where N is the part of the
# net force pressing the body onto the surface. A body pushed sideways by less
# than mu · N therefore stays put (static friction).
func _apply_friction(body: SimBody, normal: Vector3, dt: float) -> void:
	var pressing := maxf(0.0, -body.net_force.dot(normal))
	if pressing <= 0.0:
		return
	var tangential := body.velocity - normal * body.velocity.dot(normal)
	var speed := tangential.length()
	if speed < 1e-9:
		return
	var reduction := minf(speed, friction_coefficient * pressing / body.effective_mass() * dt)
	body.velocity -= tangential / speed * reduction
	# The integrator already moved the body with the pre-friction velocity this
	# step; take that part of the motion back so a stuck body does not creep.
	body.position -= tangential / speed * reduction * dt
