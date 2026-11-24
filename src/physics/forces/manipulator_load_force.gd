## Loads of the manipulator and its payload on the vehicle.
##
## The vehicle (mass, buoyancy, CG) is assumed trimmed with the arm STOWED.
## For each arm link this model therefore applies its weight in water at the
## link's current centre of gravity and the opposite force at its stowed
## centre of gravity: zero net force, but the moment changes as the arm moves
## (the vehicle pitches / rolls when the arm reaches out). A held payload adds
## its full weight in water at the gripper.
##
## A mounted tool's weight in water moves from the tool skid (where the
## vehicle was trimmed with it) to the tool's centre of gravity. Contact loads
## (arm or held item pressing on the seabed / a structure, tool tip contact
## force) and the tool's reaction torque (spinning brush) act on the vehicle.
## Contact loads are computed by the Manipulator after the previous step.
##
## Not modelled: inertial (acceleration) reactions of the moving arm and
## hydrodynamic drag on the arm.
class_name ManipulatorLoadForce
extends ForceModel

var manipulator: Manipulator


func _init(p_manipulator: Manipulator = null) -> void:
	model_name = "manipulator"
	manipulator = p_manipulator


func apply(body: SimBody, context: StepContext) -> void:
	if manipulator == null or not manipulator.is_installed():
		return
	var env := context.environment
	var weights := manipulator.link_wet_weights(env.water_density, env.gravity)
	var current := manipulator.link_points(manipulator.current_angles())
	var stowed := manipulator.stowed_link_points
	for i in weights.size():
		var force := Vector3(0.0, -weights[i], 0.0)
		body.add_force_at_point(force, body.local_to_world_point(current[i]), model_name)
		body.add_force_at_point(-force, body.local_to_world_point(stowed[i]), model_name)
	var payload := manipulator.grasped
	if payload != null:
		body.add_force_at_point(Vector3(0.0, -payload.submerged_weight(env), 0.0), payload.position, model_name)
	var tool := manipulator.tool
	if tool != null:
		var weight := Vector3(0.0, -tool.wet_weight(env), 0.0)
		body.add_force_at_point(weight, body.local_to_world_point(manipulator.tool_center_of_gravity()), model_name)
		body.add_force_at_point(-weight, body.local_to_world_point(manipulator.skid_position), model_name)
		body.add_torque(tool.reaction_torque, model_name)
	for load in manipulator.contact_loads:
		body.add_force_at_point(load[1], load[0], model_name)
