## Applies the current thrust of each of a vehicle's thrusters at the
## thruster's mounting point, producing both force and moment on the body.
## A thruster whose mounting point is above the sea surface produces no thrust.
class_name ThrusterForceModel
extends ForceModel

var thrusters: Array[Thruster] = []


func _init(p_thrusters: Array[Thruster] = []) -> void:
	model_name = "thrusters"
	thrusters = p_thrusters


func apply(body: SimBody, _context: StepContext) -> void:
	for thruster in thrusters:
		if thruster.thrust == 0.0:
			continue
		var point := body.local_to_world_point(thruster.position)
		if point.y > WorldModel.SURFACE_Y:
			continue
		var force := body.orientation * (thruster.direction * thruster.thrust)
		body.add_force_at_point(force, point, model_name)
