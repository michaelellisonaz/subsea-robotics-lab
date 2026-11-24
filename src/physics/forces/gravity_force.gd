## Weight: F = m * g, acting straight down (-Y). Added mass has no weight.
class_name GravityForce
extends ForceModel


func _init() -> void:
	model_name = "gravity"


func compute_force(body: SimBody, context: StepContext) -> Vector3:
	return Vector3(0.0, -body.mass * context.environment.gravity, 0.0)
