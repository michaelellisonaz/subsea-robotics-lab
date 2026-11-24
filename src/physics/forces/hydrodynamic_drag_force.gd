## Simplified isotropic hydrodynamic drag relative to the local water current,
## for bodies that do not carry their own hydrodynamic model.
##
##   v_rel  = v_body - v_current(position)
##   F      = -(k_lin + k_quad * |v_rel|) * v_rel
##   k_lin  = 3 * pi * mu * L        (Stokes drag of a sphere of diameter L)
##   k_quad = 0.5 * rho * Cd * A     (quadratic form drag)
##
## Isotropic, constant Cd (no Reynolds-number dependence), no added-mass or
## history effects. A first-order engineering approximation, not CFD.
## No drag is applied above the sea surface.
class_name HydrodynamicDragForce
extends ForceModel

const STOKES_FACTOR := 3.0 * PI


func _init() -> void:
	model_name = "hydrodynamic_drag"


func apply(body: SimBody, context: StepContext) -> void:
	if body.has_own_hydrodynamics():
		return
	body.add_force(compute_force(body, context), model_name)


func compute_force(body: SimBody, context: StepContext) -> Vector3:
	if body.position.y > WorldModel.SURFACE_Y:
		return Vector3.ZERO
	var env := context.environment
	var relative_velocity := body.velocity - context.world.current_velocity_at(body.position)
	var speed := relative_velocity.length()
	if speed < 1e-9:
		return Vector3.ZERO
	var linear := STOKES_FACTOR * env.dynamic_viscosity * body.characteristic_length
	var quadratic := 0.5 * env.water_density * body.drag_coefficient * body.reference_area
	return -(linear + quadratic * speed) * relative_velocity
