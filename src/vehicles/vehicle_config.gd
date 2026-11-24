## Configuration of an inspection-class ROV: geometry, mass properties,
## buoyancy, centre positions, propulsion and thruster layout.
##
## Editable parameters live in the PARAMETERS table (the dashboard builds its
## rows from it). Everything else - inertia, added mass, damping, thruster
## positions, contact points - is DERIVED from those parameters with the
## simplified estimates documented below and in the README. The derived values
## are engineering approximations for an open-frame vehicle, not measured or
## validated coefficients.
##
## Geometric frame: origin at the centre of the frame's bounding box, body axes
## (+X starboard, +Y up, +Z aft; forward is -Z). The simulation body origin is
## the centre of gravity, so geometric points are converted with to_body().
class_name VehicleConfig
extends Resource

signal changed_value(key: String)

const FILE_FORMAT := "subsea-robotics-lab/vehicle"
const FILE_VERSION := 1
## Net buoyancy is specified in this reference water.
const REFERENCE_DENSITY := 1025.0
const REFERENCE_GRAVITY := 9.81

const LAYOUT_ORDER := ["vectored_4h_4v", "vectored_4h_2v", "basic_2h_2v"]
const LAYOUTS := {
	"vectored_4h_4v": {
		"label": "8 thrusters · 4 vectored H + 4 V",
		"description": "Four horizontal thrusters at 45° in the corners plus four vertical thrusters. Actuates all six degrees of freedom.",
	},
	"vectored_4h_2v": {
		"label": "6 thrusters · 4 vectored H + 2 V",
		"description": "Four vectored horizontal thrusters plus two vertical thrusters on the centreline. Surge, sway, heave, pitch and yaw; roll is passive (buoyancy restoring only).",
	},
	"basic_2h_2v": {
		"label": "4 thrusters · 2 H + 2 V",
		"description": "Two fore-aft horizontal thrusters plus two vertical thrusters on the centreline. Surge, heave, pitch and yaw; no sway, roll is passive.",
	},
}

const ARM_LAYOUT_ORDER := ["arm_5dof", "arm_6dof", "arm_4dof", "arm_3dof", "none"]
const ARM_LAYOUTS := {
	"arm_5dof": {"label": "5 DOF + gripper (6-function)",
		"description": "Shoulder yaw, shoulder pitch, elbow, wrist pitch and wrist roll. Typical inspection / light work-class arm."},
	"arm_6dof": {"label": "6 DOF + gripper (7-function)",
		"description": "Adds a wrist yaw joint: redundant, more ways to reach a point around obstacles."},
	"arm_4dof": {"label": "4 DOF + gripper (5-function)",
		"description": "No wrist roll: the gripper cannot be rotated about its own axis."},
	"arm_3dof": {"label": "3 DOF + gripper (4-function)",
		"description": "Shoulder yaw, shoulder pitch and elbow only: the tool angle follows the arm and cannot be chosen."},
	"none": {"label": "No manipulator", "description": "Vehicle without an arm."},
}

const PARAMETER_ORDER := [
	"length", "width", "height", "dry_mass", "net_buoyancy",
	"cg_height", "cg_forward", "cb_height",
	"max_thrust", "reverse_thrust_ratio", "thruster_time_constant",
	"arm_upper_length", "arm_forearm_length", "arm_joint_speed", "arm_payload", "arm_backlash",
]
## min / max / default in the stated unit; "step" is the UI step.
const PARAMETERS := {
	"length": {"label": "Length", "unit": "m", "min": 0.6, "max": 2.0, "default": 1.0, "step": 0.01,
		"description": "Overall frame length (fore-aft)."},
	"width": {"label": "Width", "unit": "m", "min": 0.4, "max": 1.4, "default": 0.7, "step": 0.01,
		"description": "Overall frame width (port-starboard)."},
	"height": {"label": "Height", "unit": "m", "min": 0.3, "max": 1.0, "default": 0.55, "step": 0.01,
		"description": "Overall frame height including the buoyancy module."},
	"dry_mass": {"label": "Dry mass", "unit": "kg", "min": 20.0, "max": 400.0, "default": 85.0, "step": 0.5,
		"description": "Mass in air."},
	"net_buoyancy": {"label": "Net buoyancy", "unit": "N", "min": -100.0, "max": 100.0, "default": 3.0, "step": 0.5,
		"description": "Buoyancy minus weight in reference seawater (1025 kg/m³, g = 9.81 m/s²). Positive floats up. Sets the displaced volume."},
	"cg_height": {"label": "CG height", "unit": "m", "min": -0.3, "max": 0.3, "default": -0.08, "step": 0.005,
		"description": "Centre of gravity above the frame centre (negative = below)."},
	"cg_forward": {"label": "CG forward offset", "unit": "m", "min": -0.3, "max": 0.3, "default": 0.0, "step": 0.005,
		"description": "Centre of gravity ahead of the frame centre. A non-zero value trims the vehicle nose-down (or nose-up)."},
	"cb_height": {"label": "CB height", "unit": "m", "min": -0.3, "max": 0.3, "default": 0.06, "step": 0.005,
		"description": "Centre of buoyancy above the frame centre. CB above CG gives passive roll and pitch stability."},
	"max_thrust": {"label": "Thruster max thrust", "unit": "N", "min": 10.0, "max": 500.0, "default": 90.0, "step": 1.0,
		"description": "Forward (bollard) thrust of each thruster."},
	"reverse_thrust_ratio": {"label": "Reverse thrust ratio", "unit": "", "min": 0.3, "max": 1.0, "default": 0.8, "step": 0.01,
		"description": "Reverse thrust as a fraction of forward thrust (propellers are usually less efficient in reverse)."},
	"thruster_time_constant": {"label": "Thruster response time", "unit": "s", "min": 0.0, "max": 1.0, "default": 0.15, "step": 0.01,
		"description": "First-order time constant of thrust following a command change."},
	"arm_upper_length": {"label": "Arm upper link", "unit": "m", "min": 0.25, "max": 0.8, "default": 0.42, "step": 0.01,
		"description": "Shoulder-to-elbow length of the manipulator."},
	"arm_forearm_length": {"label": "Arm forearm link", "unit": "m", "min": 0.25, "max": 0.8, "default": 0.38, "step": 0.01,
		"description": "Elbow-to-wrist length of the manipulator."},
	"arm_joint_speed": {"label": "Arm joint speed", "unit": "°/s", "min": 5.0, "max": 90.0, "default": 30.0, "step": 1.0,
		"description": "Maximum speed of every arm joint."},
	"arm_payload": {"label": "Arm rated payload", "unit": "kg", "min": 2.0, "max": 60.0, "default": 12.0, "step": 0.5,
		"description": "Rated lift in water (apparent mass) with the arm fully extended horizontally. More can be lifted closer in."},
	"arm_backlash": {"label": "Arm joint backlash", "unit": "°", "min": 0.0, "max": 2.0, "default": 0.3, "step": 0.05,
		"description": "Free play in each joint gearbox; causes direction-dependent positioning error."},
}

# --- Fixed modelling assumptions (documented estimates) -----------------------
## Fraction of each bounding-box face that blocks flow (open frame).
const SOLIDITY := 0.85
## Quadratic drag coefficients per body axis (x sway, y heave, z surge).
const DRAG_COEFFICIENTS := Vector3(1.0, 1.1, 0.9)
## Added mass per body axis as a multiple of the displaced water mass.
const ADDED_MASS_COEFFICIENTS := Vector3(0.6, 0.9, 0.35)
## Added inertia as a fraction of the rigid-body inertia.
const ADDED_INERTIA_FACTOR := 0.3
## Empirical linear damping per body axis, N·s/m.
const LINEAR_DAMPING := Vector3(12.0, 15.0, 10.0)
## Empirical linear rotational damping about body axes (pitch, yaw, roll), N·m·s/rad.
const LINEAR_ROTATIONAL_DAMPING := Vector3(12.0, 15.0, 8.0)
## Drag coefficient used for the rotational (strip-theory) damping estimate.
const ROTATIONAL_DRAG_COEFFICIENT := 2.0
## Fraction of the half-width / half-length at which corner thrusters sit.
const THRUSTER_INSET := 0.72

var vehicle_name: String = "SRL-1 Inspection ROV"
var layout: String = "vectored_4h_4v"
var arm_layout: String = "arm_5dof"
var _values: Dictionary = {}

var length: float:
	get:
		return _values["length"]
var width: float:
	get:
		return _values["width"]
var height: float:
	get:
		return _values["height"]
var dry_mass: float:
	get:
		return _values["dry_mass"]


func _init() -> void:
	for key in PARAMETER_ORDER:
		_values[key] = float(PARAMETERS[key]["default"])


static func get_spec(key: String) -> Dictionary:
	return PARAMETERS.get(key, {})


func get_value(key: String) -> float:
	if not _values.has(key):
		push_error("Unknown vehicle parameter '%s'" % key)
		return 0.0
	return _values[key]


func set_value(key: String, value: float) -> float:
	if not _values.has(key):
		push_error("Unknown vehicle parameter '%s'" % key)
		return 0.0
	if is_nan(value):
		return _values[key]
	var spec: Dictionary = PARAMETERS[key]
	var v := clampf(value, spec["min"], spec["max"])
	if v != _values[key]:
		_values[key] = v
		changed_value.emit(key)
	return v


func set_layout(layout_id: String) -> void:
	if LAYOUTS.has(layout_id) and layout_id != layout:
		layout = layout_id
		changed_value.emit("layout")


func set_arm_layout(layout_id: String) -> void:
	if ARM_LAYOUTS.has(layout_id) and layout_id != arm_layout:
		arm_layout = layout_id
		changed_value.emit("arm_layout")


func reset_to_defaults() -> void:
	for key in PARAMETER_ORDER:
		set_value(key, PARAMETERS[key]["default"])
	set_layout(LAYOUT_ORDER[0])
	set_arm_layout(ARM_LAYOUT_ORDER[0])


func duplicate_config() -> VehicleConfig:
	var copy := VehicleConfig.new()
	copy.apply_dict(to_dict())
	return copy


func to_dict() -> Dictionary:
	return {"name": vehicle_name, "layout": layout, "arm_layout": arm_layout, "parameters": _values.duplicate()}


func apply_dict(data: Dictionary) -> void:
	if typeof(data.get("name")) == TYPE_STRING:
		vehicle_name = data["name"]
	if typeof(data.get("layout")) == TYPE_STRING:
		set_layout(data["layout"])
	if typeof(data.get("arm_layout")) == TYPE_STRING:
		set_arm_layout(data["arm_layout"])
	var parameters = data.get("parameters", {})
	if typeof(parameters) == TYPE_DICTIONARY:
		for key in PARAMETER_ORDER:
			if parameters.has(key) and (typeof(parameters[key]) == TYPE_FLOAT or typeof(parameters[key]) == TYPE_INT):
				set_value(key, float(parameters[key]))


func equals(other: VehicleConfig) -> bool:
	return other != null and to_dict() == other.to_dict()


func save_json(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var payload := {"format": FILE_FORMAT, "version": FILE_VERSION, "vehicle": to_dict()}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return OK


func load_json(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return ERR_PARSE_ERROR
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY or str(data.get("format", "")) != FILE_FORMAT:
		return ERR_PARSE_ERROR
	if typeof(data.get("vehicle")) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR
	apply_dict(data["vehicle"])
	return OK


# --- Derived properties ---------------------------------------------------------

## Displaced volume from dry mass and net buoyancy in reference seawater, m³.
func displaced_volume() -> float:
	var buoyancy := get_value("dry_mass") * REFERENCE_GRAVITY + get_value("net_buoyancy")
	return maxf(buoyancy / (REFERENCE_DENSITY * REFERENCE_GRAVITY), 0.001)


func cg_geometric() -> Vector3:
	return Vector3(0.0, get_value("cg_height"), -get_value("cg_forward"))


func cb_geometric() -> Vector3:
	return Vector3(0.0, get_value("cb_height"), 0.0)


## Converts a point in the geometric frame to the body frame (origin at CG).
func to_body(geometric_point: Vector3) -> Vector3:
	return geometric_point - cg_geometric()


func cb_relative_to_cg() -> Vector3:
	return to_body(cb_geometric())


## Principal inertia about the CG, approximated as a solid box of the frame's
## dimensions with the dry mass (about body x, y, z), kg·m².
func inertia() -> Vector3:
	var m := dry_mass / 12.0
	return Vector3(
		m * (height * height + length * length),
		m * (width * width + length * length),
		m * (width * width + height * height))


func added_mass() -> Vector3:
	return ADDED_MASS_COEFFICIENTS * REFERENCE_DENSITY * displaced_volume()


func added_inertia() -> Vector3:
	return inertia() * ADDED_INERTIA_FACTOR


## Flow-blocking area per body axis: x (side), y (top), z (front), m².
func projected_areas() -> Vector3:
	return Vector3(length * height, length * width, width * height) * SOLIDITY


## Quadratic rotational damping at reference density, N·m·s²/rad². Strip
## theory for a box: a face of width b and extent e rotating about its centre
## gives rho · Cd · b · e⁴ / 64.
func quadratic_rotational_damping() -> Vector3:
	var c := REFERENCE_DENSITY * ROTATIONAL_DRAG_COEFFICIENT / 64.0
	var l4 := pow(length, 4.0)
	var w4 := pow(width, 4.0)
	var h4 := pow(height, 4.0)
	return Vector3(
		c * (width * l4 + width * h4),
		c * (height * l4 + height * w4),
		c * (length * h4 + length * w4)) * SOLIDITY


func build_damping() -> HydrodynamicDamping:
	var damping := HydrodynamicDamping.new()
	damping.linear_translational = LINEAR_DAMPING
	damping.drag_coefficients = DRAG_COEFFICIENTS
	damping.projected_areas = projected_areas()
	damping.linear_rotational = LINEAR_ROTATIONAL_DAMPING
	damping.quadratic_rotational = quadratic_rotational_damping()
	return damping


## Thruster mounting points (geometric frame) and directions for the layout.
func thruster_specs() -> Array[Dictionary]:
	var a := width * 0.5 * THRUSTER_INSET
	var b := length * 0.5 * THRUSTER_INSET
	var y_horizontal := -height * 0.12
	var y_vertical := height * 0.30
	var s := sqrt(0.5)
	var specs: Array[Dictionary] = []
	if layout == "basic_2h_2v":
		specs.append({"name": "H-Port", "position": Vector3(-a, y_horizontal, 0.0), "direction": Vector3.FORWARD})
		specs.append({"name": "H-Stbd", "position": Vector3(a, y_horizontal, 0.0), "direction": Vector3.FORWARD})
	else:
		specs.append({"name": "H-FwdPort", "position": Vector3(-a, y_horizontal, -b), "direction": Vector3(s, 0.0, -s)})
		specs.append({"name": "H-FwdStbd", "position": Vector3(a, y_horizontal, -b), "direction": Vector3(-s, 0.0, -s)})
		specs.append({"name": "H-AftPort", "position": Vector3(-a, y_horizontal, b), "direction": Vector3(-s, 0.0, -s)})
		specs.append({"name": "H-AftStbd", "position": Vector3(a, y_horizontal, b), "direction": Vector3(s, 0.0, -s)})
	if layout == "vectored_4h_4v":
		specs.append({"name": "V-FwdPort", "position": Vector3(-a, y_vertical, -b), "direction": Vector3.UP})
		specs.append({"name": "V-FwdStbd", "position": Vector3(a, y_vertical, -b), "direction": Vector3.UP})
		specs.append({"name": "V-AftPort", "position": Vector3(-a, y_vertical, b), "direction": Vector3.UP})
		specs.append({"name": "V-AftStbd", "position": Vector3(a, y_vertical, b), "direction": Vector3.UP})
	else:
		specs.append({"name": "V-Fwd", "position": Vector3(0.0, y_vertical, -b), "direction": Vector3.UP})
		specs.append({"name": "V-Aft", "position": Vector3(0.0, y_vertical, b), "direction": Vector3.UP})
	return specs


func build_thrusters() -> Array[Thruster]:
	var result: Array[Thruster] = []
	var forward := get_value("max_thrust")
	var reverse := forward * get_value("reverse_thrust_ratio")
	for spec in thruster_specs():
		result.append(Thruster.new(spec["name"], to_body(spec["position"]), spec["direction"],
			forward, reverse, get_value("thruster_time_constant")))
	return result


## Hull sample points relative to the CG, used for contact: the 8 corners,
## 12 edge midpoints and 6 face centres of the bounding box.
func contact_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for sx in [-0.5, 0.0, 0.5]:
		for sy in [-0.5, 0.0, 0.5]:
			for sz in [-0.5, 0.0, 0.5]:
				if sx == 0.0 and sy == 0.0 and sz == 0.0:
					continue
				points.append(to_body(Vector3(sx * width, sy * height, sz * length)))
	return points


## Manipulator base (shoulder yaw joint) in the geometric frame: front,
## starboard of centre, low on the frame.
func arm_mount_geometric() -> Vector3:
	return Vector3(0.18 * width, -0.5 * height + 0.08, -0.5 * length + 0.04)


## Onboard (pilot) camera position in the geometric frame: just ahead of the
## front camera dome.
func camera_position_geometric() -> Vector3:
	return Vector3(0.0, -height * 0.06, -length * 0.5 - 0.075)
