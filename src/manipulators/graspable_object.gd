## A loose item on the site that the manipulator can pick up (debris,
## markers, anodes ...). A point-mass SimBody: it sinks or floats, rests on
## the seabed, collides with structures as a sphere, and is carried rigidly
## by the gripper while held (is_dynamic = false).
##
## Simplifications: no rotational dynamics (released items settle upright),
## no contact between items, grasp succeeds if the item is within the jaws
## and narrower than the maximum opening (no friction / grip-force model).
class_name GraspableObject
extends SimBody

## "box" or "cylinder" (cylinder axis vertical).
var shape: String = "box"
## Box: width (x), height (y), depth (z). Cylinder: diameter, height, diameter.
var size: Vector3 = Vector3(0.2, 0.2, 0.2)
var color: Color = Color(0.6, 0.6, 0.6)
## Jaw opening that holds the item, m.
var grasp_width: float = 0.1
## The manipulator holding the item, or null.
var held_by: Object:
	get:
		return _held_by.get_ref() if _held_by != null else null
	set(value):
		_held_by = weakref(value) if value != null else null
# Weak, so a held item and the arm holding it do not keep each other alive.
var _held_by: WeakRef = null
## Message from the item's last release (installation result ...).
var seat_message: String = ""


func _init(p_name: String = "Object", p_shape: String = "box", p_size: Vector3 = Vector3(0.2, 0.2, 0.2),
		p_mass: float = 5.0, density: float = 2500.0, p_color: Color = Color(0.6, 0.6, 0.6),
		p_position: Vector3 = Vector3.ZERO) -> void:
	super(p_name, p_position)
	shape = p_shape
	size = p_size
	color = p_color
	mass = p_mass
	displaced_volume = p_mass / density
	drag_coefficient = 1.0
	reference_area = p_size.x * p_size.y
	characteristic_length = maxf(p_size.x, maxf(p_size.y, p_size.z))
	bottom_clearance = p_size.y * 0.5
	collision_radius = minf(p_size.x, minf(p_size.y, p_size.z)) * 0.5
	grasp_width = minf(p_size.x, p_size.z)


func reset_state() -> void:
	super()
	is_dynamic = true
	held_by = null


## Where the jaws must close to pick the item up (world).
func grasp_point() -> Vector3:
	return position


func can_be_grasped() -> bool:
	return held_by == null and grasp_width <= Manipulator.GRIPPER_MAX_OPENING


## Spheres used to keep the item out of the seabed and structures while it is
## held: [{"point": world, "radius": m (structures, 0 = skip),
## "clearance": m (height above the seabed it needs, < 0 = skip)}].
func contact_spheres() -> Array[Dictionary]:
	return [{"point": position, "radius": collision_radius, "clearance": bottom_clearance}]


## Called when the gripper opens. Return true if the item has taken care of
## its own pose (e.g. it was installed); otherwise it is released to fall.
func on_released() -> bool:
	return false


func get_type_name() -> String:
	return "GraspableObject"
