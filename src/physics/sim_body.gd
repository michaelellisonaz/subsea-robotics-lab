## A simulation object with dynamics, integrated by PhysicsWorld.
##
## SimBody itself is a point mass (translation only; torques are recorded but
## not integrated). RigidSimBody extends it to six degrees of freedom. Loads
## are accumulated each step by ForceModels through add_force(),
## add_torque() and add_force_at_point(), then integrate() advances the state.
##
## Body axes (Godot convention): +X right (starboard), +Y up, +Z aft; the
## body's forward direction is -Z. The body origin is its centre of gravity.
class_name SimBody
extends SimObject

## Dry mass, kg.
var mass: float = 1.0
## Volume of water displaced when fully submerged, m³.
var displaced_volume: float = 0.0
## Isotropic added mass used by the point-mass integrator, kg.
var added_mass: float = 0.0
## Quadratic drag coefficient Cd for the global isotropic drag model.
var drag_coefficient: float = 1.0
## Reference area for the global isotropic drag model, m².
var reference_area: float = 0.0
## Characteristic length for the linear (viscous) drag term, m.
var characteristic_length: float = 0.0
## Distance from the origin down to the lowest point, used by the simple
## seabed constraint (the origin never goes below seabed + clearance), m.
var bottom_clearance: float = 0.0
## When false the body is never moved by PhysicsWorld.
var is_dynamic: bool = true
## Radius of the sphere used to keep the body out of fixed structures, m
## (0 = no structure collision; rigid vehicles use their own hull contact).
var collision_radius: float = 0.0
## Centre of buoyancy relative to the origin (CG), body axes, m. Buoyancy
## acting here gives rigid bodies their restoring moment.
var center_of_buoyancy: Vector3 = Vector3.ZERO
## Vertical extent used to estimate partial submergence at the surface, m.
## 0 = fully submerged whenever the origin is below the surface.
var submersion_height: float = 0.0
## Force models acting on this body only (thrusters, own hydrodynamics, contact).
var local_force_models: Array[ForceModel] = []

## Linear velocity in the world frame, m/s.
var velocity: Vector3 = Vector3.ZERO
## Total force applied during the last step (world frame), N.
var net_force: Vector3 = Vector3.ZERO
## Total torque about the origin during the last step (world frame), N·m.
var net_torque: Vector3 = Vector3.ZERO
## Force contributed by each model during the last step (model name -> N).
var force_breakdown: Dictionary = {}
## Torque contributed by each model during the last step (model name -> N·m).
var torque_breakdown: Dictionary = {}
## True if the seabed was touched during the last step.
var in_seabed_contact: bool = false

var _force_accumulator: Vector3 = Vector3.ZERO
var _torque_accumulator: Vector3 = Vector3.ZERO
var _initial_velocity: Vector3 = Vector3.ZERO


## Mass used for translational acceleration, kg.
func effective_mass() -> float:
	return mass + added_mass


## Weight minus buoyancy when fully submerged (positive = sinks), N.
func submerged_weight(environment: EnvironmentConfig) -> float:
	return (mass - environment.water_density * displaced_volume) * environment.gravity


## True if one of the body's own models provides its hydrodynamic loads.
func has_own_hydrodynamics() -> bool:
	for model in local_force_models:
		if model.enabled and model.replaces_global_drag:
			return true
	return false


## Fraction of the displaced volume below the surface (0..1). Linear in the
## immersion of a body of height submersion_height centred on the origin.
func submerged_fraction(surface_y: float = WorldModel.SURFACE_Y) -> float:
	if submersion_height <= 0.0:
		return 1.0 if position.y <= surface_y else 0.0
	return clampf((surface_y - (position.y - submersion_height * 0.5)) / submersion_height, 0.0, 1.0)


## Angular velocity in the world frame (zero for a point mass), rad/s.
func world_angular_velocity() -> Vector3:
	return Vector3.ZERO


func local_to_world_point(local_point: Vector3) -> Vector3:
	return position + orientation * local_point


func local_to_world_vector(local_vector: Vector3) -> Vector3:
	return orientation * local_vector


func world_to_local_vector(world_vector: Vector3) -> Vector3:
	return orientation.inverse() * world_vector


## Velocity of a point fixed to the body, world frame, m/s.
func velocity_at_point(world_point: Vector3) -> Vector3:
	return velocity + world_angular_velocity().cross(world_point - position)


func clear_loads() -> void:
	_force_accumulator = Vector3.ZERO
	_torque_accumulator = Vector3.ZERO
	force_breakdown.clear()
	torque_breakdown.clear()
	in_seabed_contact = false


## Adds a world-frame force through the body origin.
func add_force(force: Vector3, source: String = "") -> void:
	_force_accumulator += force
	if source != "":
		force_breakdown[source] = force_breakdown.get(source, Vector3.ZERO) + force


## Adds a world-frame torque about the body origin.
func add_torque(torque: Vector3, source: String = "") -> void:
	_torque_accumulator += torque
	if source != "":
		torque_breakdown[source] = torque_breakdown.get(source, Vector3.ZERO) + torque


## Adds a world-frame force acting at a world-space point (force + moment).
func add_force_at_point(force: Vector3, world_point: Vector3, source: String = "") -> void:
	add_force(force, source)
	add_torque((world_point - position).cross(force), source)


## Advances the state by one step from the accumulated loads (point mass:
## semi-implicit Euler on translation; torques are not integrated).
func integrate(context: StepContext) -> void:
	net_force = _force_accumulator
	net_torque = _torque_accumulator
	velocity += net_force / effective_mass() * context.dt
	position += velocity * context.dt


func capture_initial_state() -> void:
	super()
	_initial_velocity = velocity


func reset_state() -> void:
	super()
	velocity = _initial_velocity
	net_force = Vector3.ZERO
	net_torque = Vector3.ZERO
	force_breakdown.clear()
	torque_breakdown.clear()
	in_seabed_contact = false


func get_type_name() -> String:
	return "SimBody"
