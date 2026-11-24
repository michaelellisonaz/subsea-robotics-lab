## Hull contact with the seabed and with fixed structures (pipelines ...).
##
## Penalty method on a set of hull points (body axes, relative to the CG):
## each point that penetrates a surface gets a spring-damper force along the
## surface normal
##   F_n = k · penetration - c · v_n   (only pushing, never pulling)
## plus tangential friction |F_t| = min(mu · F_n, c_t · |v_t|) opposing
## sliding (Coulomb friction regularised by a viscous slope near zero speed).
## Forces act at the contact points, so they also produce moments.
##
## Seabed: normal taken as vertical (gentle relief), rigid (no sediment).
## Structures: normal from the touched primitive (cylinder radial / box face).
## Simplifications: point-sampled hull (corners, edge midpoints and face
## centres of the bounding box), so thin features between sample points can
## intrude slightly; gains chosen for stability at the 10 ms step.
class_name HullContactForce
extends ForceModel

## Spring stiffness per contact point, N/m.
var stiffness: float = 30000.0
## Damping per contact point, N·s/m.
var damping: float = 600.0
## Coulomb friction coefficient.
var friction_coefficient: float = 0.5
## Viscous slope that regularises friction at low sliding speed, N·s/m.
var friction_slope: float = 800.0
## Hull points that can touch surfaces (body axes, relative to the CG), m.
var contact_points: PackedVector3Array = PackedVector3Array()
## Radius of the sphere around the hull used to find nearby structures, m.
var bounding_radius: float = 1.0
## Number of points touching the seabed / a structure during the last step.
var points_in_contact: int = 0
var structure_points_in_contact: int = 0


func _init(points: PackedVector3Array = PackedVector3Array()) -> void:
	model_name = "contact"
	contact_points = points
	for p in points:
		bounding_radius = maxf(bounding_radius, p.length())


func apply(body: SimBody, context: StepContext) -> void:
	points_in_contact = 0
	structure_points_in_contact = 0
	var nearby := context.world.structures_near(body.position, bounding_radius + 0.1)
	for local_point in contact_points:
		var point := body.local_to_world_point(local_point)
		var penetration := context.world.seabed_y_at(point.x, point.z) - point.y
		if penetration > 0.0:
			if _push(body, point, Vector3.UP, penetration):
				points_in_contact += 1
		if not nearby.is_empty():
			var hit := context.world.structure_penetration(point, 0.0, nearby)
			if not hit.is_empty():
				if _push(body, point, hit["normal"], hit["depth"]):
					structure_points_in_contact += 1
	if points_in_contact > 0 or structure_points_in_contact > 0:
		body.in_seabed_contact = points_in_contact > 0 or body.in_seabed_contact


func _push(body: SimBody, point: Vector3, normal: Vector3, depth: float) -> bool:
	var point_velocity := body.velocity_at_point(point)
	var normal_speed := point_velocity.dot(normal)
	var normal_force := stiffness * depth - damping * normal_speed
	if normal_force <= 0.0:
		return false
	var force := normal * normal_force
	var tangential := point_velocity - normal * normal_speed
	var slide_speed := tangential.length()
	if slide_speed > 1e-6:
		force -= tangential / slide_speed * minf(friction_coefficient * normal_force, friction_slope * slide_speed)
	body.add_force_at_point(force, point, model_name)
	return true
