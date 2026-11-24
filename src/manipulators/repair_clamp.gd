## Split-sleeve repair clamp for the pipeline crack (a lightweight composite
## clamp, so the light inspection-class arm can handle it).
##
## The clamp lies on the seabed with its two half-shells hinged at the top,
## open. The arm picks it up by the lifting handle on the crown, lowers it over
## the pipe until the inside of the crown sits on the pipe top, and opens the
## gripper. On release the clamp checks its seat (Pipeline.clamp_fit): axis
## within 10° of the pipe axis, centre within 30 mm of the pipe centreline,
## bore matching the pipe diameter, clear of flanges, supports and anodes. If
## it fits, the halves close and bolt up: the clamp becomes part of the
## pipeline (a solid primitive) and repairs the crack if it covers it with a
## 50 mm seal margin each side. Otherwise it is released and falls.
##
## Simplifications: closing and bolting are instantaneous; no seal pressure or
## bolt-torque model; a real steel clamp for this pipe would weigh hundreds of
## kilograms and need a work-class vehicle.
class_name RepairClamp
extends GraspableObject

const CLAMP_LENGTH := 0.4  # m
const WALL := 0.012  # m
const HANDLE_HEIGHT := 0.05  # m above the crown
const CROWN_PROBE_RADIUS := 0.03  # m

var pipeline: Pipeline
var inner_radius: float = 0.305
var outer_radius: float = 0.317
var installed: bool = false
var _generation: int = -1


## `bore_radius`: the pipe radius the clamp is built for (+5 mm clearance).
func _init(p_pipeline: Pipeline = null, bore_radius: float = 0.3, p_position: Vector3 = Vector3.ZERO) -> void:
	inner_radius = bore_radius + 0.005
	outer_radius = inner_radius + WALL
	super("Repair clamp", "clamp", Vector3(CLAMP_LENGTH, outer_radius * 2.0, outer_radius * 2.0),
		18.0, 1900.0, Color(0.85, 0.75, 0.15), p_position)
	pipeline = p_pipeline
	collision_radius = outer_radius
	bottom_clearance = outer_radius
	grasp_width = 0.05
	reference_area = CLAMP_LENGTH * outer_radius * 2.0


## Clamp axis in world (local +X).
func axis_direction() -> Vector3:
	return orientation * Vector3.RIGHT


func up_direction() -> Vector3:
	return orientation * Vector3.UP


func grasp_point() -> Vector3:
	return position + up_direction() * (outer_radius + HANDLE_HEIGHT)


func can_be_grasped() -> bool:
	return not installed and super()


## While held: the inside of the crown (stops on the pipe top when seated) and
## the open bottom edge (kept out of the seabed).
func contact_spheres() -> Array[Dictionary]:
	var up := up_direction()
	return [
		{"point": position + up * (inner_radius + CROWN_PROBE_RADIUS), "radius": CROWN_PROBE_RADIUS, "clearance": CROWN_PROBE_RADIUS},
		{"point": position - up * outer_radius, "radius": 0.0, "clearance": 0.0},
	]


func on_released() -> bool:
	if pipeline == null:
		return false
	var fit := pipeline.clamp_fit(position, axis_direction(), inner_radius, CLAMP_LENGTH)
	if not fit["ok"]:
		seat_message = "Clamp not installed: %s" % fit["reason"]
		return false
	# The halves close around the pipe and pull the clamp concentric.
	position = Vector3(position.x, pipeline.axis_y(), pipeline.axis_z())
	orientation = Quaternion.IDENTITY
	velocity = Vector3.ZERO
	is_dynamic = false
	installed = true
	_generation = pipeline.geometry_generation
	pipeline.install_clamp(position.x, CLAMP_LENGTH, inner_radius, outer_radius, self)
	var covers := pipeline.crack_status() == "clamped"
	seat_message = "Clamp installed at E %.2f%s" % [position.x, ": crack covered" if covers else " (does not cover the crack)"]
	return true


func post_step(_context: StepContext) -> void:
	# An edit of the pipeline geometry (diameter / gap) unseats the clamp.
	if installed and pipeline != null and pipeline.geometry_generation != _generation:
		installed = false
		is_dynamic = true
		seat_message = "Clamp released: the pipeline geometry changed"


func reset_state() -> void:
	super()
	installed = false
	seat_message = ""
	_generation = -1


func get_type_name() -> String:
	return "RepairClamp"
