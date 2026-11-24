## Six-degree-of-freedom hydrodynamic damping for a rigid vehicle, computed in
## body axes relative to the local current (Fossen-style diagonal damping):
##
##   F_i = -(Dl_i · (mu / mu_ref) + 0.5 · rho · Cd_i · A_i · |v_r,i|) · v_r,i
##   M_i = -(Dlr_i · (mu / mu_ref) + Dqr_i · (rho / rho_ref) · |w_i|) · w_i
##
## for each body axis i (x = sway, y = heave, z = surge; rotations about x =
## pitch, y = yaw, z = roll). Linear terms are empirical and scaled with water
## viscosity; quadratic terms scale with water density.
##
## Simplifications: no coupling between axes, coefficients constant with
## speed, forces scaled by the submerged fraction near the surface. Not CFD:
## coefficients are estimates (see VehicleConfig), not measured values.
class_name HydrodynamicDamping
extends ForceModel

const REFERENCE_DENSITY := 1025.0
const REFERENCE_VISCOSITY := 0.00108

## Linear translational damping per body axis at the reference viscosity, N·s/m.
var linear_translational: Vector3 = Vector3.ZERO
## Quadratic drag coefficient Cd per body axis.
var drag_coefficients: Vector3 = Vector3.ONE
## Projected (flow-blocking) area per body axis, m².
var projected_areas: Vector3 = Vector3.ZERO
## Linear rotational damping about each body axis at reference viscosity, N·m·s/rad.
var linear_rotational: Vector3 = Vector3.ZERO
## Quadratic rotational damping about each body axis at reference density, N·m·s²/rad².
var quadratic_rotational: Vector3 = Vector3.ZERO


func _init() -> void:
	model_name = "hydrodynamic_damping"
	replaces_global_drag = true


## Quadratic translational coefficients 0.5·rho·Cd·A for a water density, N·s²/m².
func quadratic_translational(density: float) -> Vector3:
	return 0.5 * density * drag_coefficients * projected_areas


func apply(body: SimBody, context: StepContext) -> void:
	var rigid := body as RigidSimBody
	if rigid == null:
		return
	var fraction := body.submerged_fraction()
	if fraction <= 0.0:
		return
	var env := context.environment
	var to_body := body.orientation.inverse()
	var v_rel := to_body * (body.velocity - context.world.current_velocity_at(body.position))
	var viscosity_ratio := env.dynamic_viscosity / REFERENCE_VISCOSITY
	var density_ratio := env.water_density / REFERENCE_DENSITY
	var k_quad := quadratic_translational(env.water_density)
	var force_b := -(linear_translational * viscosity_ratio + k_quad * v_rel.abs()) * v_rel
	var w := rigid.angular_velocity
	var torque_b := -(linear_rotational * viscosity_ratio + quadratic_rotational * density_ratio * w.abs()) * w
	body.add_force(body.orientation * (force_b * fraction), model_name)
	body.add_torque(body.orientation * (torque_b * fraction), model_name)
