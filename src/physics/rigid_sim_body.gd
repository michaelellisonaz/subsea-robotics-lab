## Six-degree-of-freedom rigid body for underwater vehicles.
##
## Equations of motion (Kirchhoff form, body axes, origin at the CG, diagonal
## mass and inertia matrices):
##
##   (m + M_A) v̇ = F_b - ω × (m v + M_A v_r)
##   (J + J_A) ω̇ = T_b - ω × ((J + J_A) ω) - v_r × (M_A v_r)
##
## v = body-frame velocity, v_r = velocity relative to the local current,
## ω = body-frame angular velocity, M_A / J_A = added mass / added inertia.
## The last term is the Munk moment, which makes elongated bodies turn
## broadside to the flow. Integration is semi-implicit Euler; orientation is
## advanced with the exact rotation for the step's angular velocity and
## renormalised.
##
## Simplifications: diagonal matrices (no off-diagonal coupling or products of
## inertia), added mass acts on the absolute acceleration (exact only for a
## uniform, steady current), no fluid memory effects.
class_name RigidSimBody
extends SimBody

## Principal moments of inertia about the CG along body axes x, y, z, kg·m².
var inertia: Vector3 = Vector3.ONE
## Translational added mass along body axes x, y, z, kg.
var added_mass_linear: Vector3 = Vector3.ZERO
## Rotational added inertia about body axes x, y, z, kg·m².
var added_inertia: Vector3 = Vector3.ZERO
## Angular velocity in body axes, rad/s.
var angular_velocity: Vector3 = Vector3.ZERO

var _initial_angular_velocity: Vector3 = Vector3.ZERO


func effective_mass() -> float:
	return mass


func world_angular_velocity() -> Vector3:
	return orientation * angular_velocity


## Linear velocity expressed in body axes, m/s.
func body_velocity() -> Vector3:
	return orientation.inverse() * velocity


func integrate(context: StepContext) -> void:
	net_force = _force_accumulator
	net_torque = _torque_accumulator
	var dt := context.dt
	var to_body := orientation.inverse()
	var force_b := to_body * net_force
	var torque_b := to_body * net_torque
	var v := to_body * velocity
	var current_b := Vector3.ZERO
	if context.world != null:
		current_b = to_body * context.world.current_velocity_at(position)
	var v_rel := v - current_b
	var w := angular_velocity
	var m_rigid := Vector3(mass, mass, mass)
	var m_total := m_rigid + added_mass_linear
	var j_total := inertia + added_inertia

	var momentum := m_rigid * v + added_mass_linear * v_rel
	var linear_acceleration := (force_b - w.cross(momentum)) / m_total
	var angular_acceleration := (torque_b - w.cross(j_total * w) - v_rel.cross(added_mass_linear * v_rel)) / j_total

	v += linear_acceleration * dt
	w += angular_acceleration * dt
	angular_velocity = w
	var rate := w.length()
	if rate * dt > 1e-9:
		orientation = (orientation * Quaternion(w / rate, rate * dt)).normalized()
	velocity = orientation * v
	position += velocity * dt


func capture_initial_state() -> void:
	super()
	_initial_angular_velocity = angular_velocity


func reset_state() -> void:
	super()
	angular_velocity = _initial_angular_velocity


func get_type_name() -> String:
	return "RigidSimBody"
