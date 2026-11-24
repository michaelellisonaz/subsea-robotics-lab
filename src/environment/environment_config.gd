## Physical description of the water body, shared by every simulation system.
##
## EnvironmentConfig is plain data plus a few derived quantities. It knows
## nothing about rendering or UI: the renderer, the dashboard and the physics
## framework all read it and listen to [signal parameter_changed].
##
## To add a parameter, add an entry to [constant PARAMETERS] and its key to
## [constant PARAMETER_ORDER] (plus a typed accessor below if code needs one).
## The dashboard builds its editing rows from this table, and save/load picks
## it up automatically.
##
## All values are stored in SI units. "display_scale" only affects how the
## dashboard shows a value (e.g. viscosity in mPa*s).
class_name EnvironmentConfig
extends Resource

## Emitted whenever one parameter changes (after clamping).
signal parameter_changed(key: String, value: float)

const FILE_FORMAT := "subsea-robotics-lab/environment"
const FILE_VERSION := 1

## Standard atmospheric pressure at the sea surface, Pa.
const STANDARD_ATMOSPHERE_PA := 101325.0
## Koschmieder constant ln(1 / 0.02): visibility is taken as the distance at
## which apparent contrast falls to 2 %, so extinction = 3.912 / visibility.
const KOSCHMIEDER_CONSTANT := 3.912
## Poole-Atkins constant (Kd ~ 1.44 / Secchi depth). Used only as a rough
## estimate of how quickly daylight fades with depth, for visualisation.
const POOLE_ATKINS_CONSTANT := 1.44

const PARAMETER_ORDER := [
	"water_depth",
	"water_density",
	"dynamic_viscosity",
	"gravity",
	"water_temperature",
	"visibility",
	"current_speed",
	"current_heading",
	"current_boundary_layer",
]

## min / max / default are SI values; "step" is in display units.
const PARAMETERS := {
	"water_depth": {
		"label": "Water depth", "unit": "m",
		"min": 5.0, "max": 1000.0, "default": 30.0, "step": 0.5, "exponential": true,
		"description": "Depth of the seabed reference level below the sea surface (y = 0).",
	},
	"water_density": {
		"label": "Water density", "unit": "kg/m³",
		"min": 990.0, "max": 1060.0, "default": 1025.0, "step": 0.5,
		"description": "Mass density of the water. Typical seawater ~1025 kg/m³, fresh water ~998 kg/m³.",
	},
	"dynamic_viscosity": {
		"label": "Dynamic viscosity", "unit": "mPa·s", "display_scale": 1000.0,
		"min": 0.0005, "max": 0.0025, "default": 0.00108, "step": 0.01,
		"description": "Dynamic viscosity (stored in Pa·s, shown in mPa·s). Seawater at 20 °C ~1.08 mPa·s, at 5 °C ~1.6 mPa·s.",
	},
	"gravity": {
		"label": "Gravity", "unit": "m/s²",
		"min": 0.0, "max": 25.0, "default": 9.81, "step": 0.01,
		"description": "Gravitational acceleration. Earth standard 9.81 m/s².",
	},
	"water_temperature": {
		"label": "Water temperature", "unit": "°C",
		"min": -2.0, "max": 40.0, "default": 10.0, "step": 0.1,
		"description": "Water temperature. Stage 1 records it as metadata only; it does not yet change density or viscosity automatically.",
	},
	"visibility": {
		"label": "Visibility", "unit": "m",
		"min": 1.0, "max": 60.0, "default": 30.0, "step": 0.5, "exponential": true,
		"description": "Horizontal visual range (distance at which contrast falls to ~2 %). Drives the underwater fog and the estimated daylight attenuation.",
	},
	"current_speed": {
		"label": "Current speed", "unit": "m/s",
		"min": 0.0, "max": 3.0, "default": 0.25, "step": 0.01,
		"description": "Speed of the (uniform) water current.",
	},
	"current_heading": {
		"label": "Current heading", "unit": "°",
		"min": 0.0, "max": 359.0, "default": 90.0, "step": 1.0, "wrap": true,
		"description": "Compass direction the current flows TOWARD (oceanographic convention): 0 = North, 90 = East.",
	},
	"current_boundary_layer": {
		"label": "Bottom boundary layer", "unit": "m",
		"min": 0.0, "max": 20.0, "default": 3.0, "step": 0.1,
		"description": "Thickness of the seabed boundary layer. Inside it the current slows toward the seabed (1/7 power law of height above the bed). 0 = uniform current down to the seabed.",
	},
}

var _values: Dictionary = {}

var water_depth: float:
	get:
		return _values["water_depth"]
	set(value):
		set_value("water_depth", value)

var water_density: float:
	get:
		return _values["water_density"]
	set(value):
		set_value("water_density", value)

var dynamic_viscosity: float:
	get:
		return _values["dynamic_viscosity"]
	set(value):
		set_value("dynamic_viscosity", value)

var gravity: float:
	get:
		return _values["gravity"]
	set(value):
		set_value("gravity", value)

var water_temperature: float:
	get:
		return _values["water_temperature"]
	set(value):
		set_value("water_temperature", value)

var visibility: float:
	get:
		return _values["visibility"]
	set(value):
		set_value("visibility", value)

var current_speed: float:
	get:
		return _values["current_speed"]
	set(value):
		set_value("current_speed", value)

var current_heading: float:
	get:
		return _values["current_heading"]
	set(value):
		set_value("current_heading", value)

var current_boundary_layer: float:
	get:
		return _values["current_boundary_layer"]
	set(value):
		set_value("current_boundary_layer", value)


func _init() -> void:
	for key in PARAMETER_ORDER:
		_values[key] = float(PARAMETERS[key]["default"])


static func has_parameter(key: String) -> bool:
	return PARAMETERS.has(key)


## Metadata for one parameter (label, unit, min, max, default, step, description).
static func get_spec(key: String) -> Dictionary:
	return PARAMETERS.get(key, {})


func get_value(key: String) -> float:
	if not _values.has(key):
		push_error("Unknown environment parameter '%s'" % key)
		return 0.0
	return _values[key]


## Sets a parameter, clamping (or wrapping) it into its valid range.
## Returns the value actually stored.
func set_value(key: String, value: float) -> float:
	if not _values.has(key):
		push_error("Unknown environment parameter '%s'" % key)
		return 0.0
	if is_nan(value):
		return _values[key]
	var spec: Dictionary = PARAMETERS[key]
	var v: float
	if spec.get("wrap", false):
		v = fposmod(value, 360.0)
		v = minf(v, spec["max"])
	else:
		v = clampf(value, spec["min"], spec["max"])
	if v == _values[key]:
		return v
	_values[key] = v
	parameter_changed.emit(key, v)
	return v


func reset_to_defaults() -> void:
	for key in PARAMETER_ORDER:
		set_value(key, PARAMETERS[key]["default"])


# --- Derived quantities -------------------------------------------------------

## Hydrostatic gauge pressure (above atmospheric) at a depth, Pa.
func gauge_pressure_at_depth(depth_m: float) -> float:
	return water_density * gravity * maxf(depth_m, 0.0)


## Absolute pressure at a depth (atmosphere + hydrostatic), Pa.
func absolute_pressure_at_depth(depth_m: float) -> float:
	return STANDARD_ATMOSPHERE_PA + gauge_pressure_at_depth(depth_m)


## Kinematic viscosity nu = mu / rho, m²/s.
func kinematic_viscosity() -> float:
	return dynamic_viscosity / water_density


## Free-stream current velocity (above the bottom boundary layer), world
## frame, m/s. Use WorldModel.current_velocity_at() for the local current.
func current_velocity() -> Vector3:
	return WorldFrame.direction_from_heading(current_heading) * current_speed


## Reynolds number Re = U * L / nu.
func reynolds_number(length_m: float, speed_m_s: float) -> float:
	return speed_m_s * length_m / kinematic_viscosity()


## Optical extinction coefficient used for fog, 1/m (Koschmieder relation).
func optical_extinction_coefficient() -> float:
	return KOSCHMIEDER_CONSTANT / visibility


## Rough estimate of the diffuse light attenuation coefficient Kd, 1/m.
## Visualisation only - not a validated optical model.
func estimated_light_attenuation() -> float:
	return POOLE_ATKINS_CONSTANT / visibility


## Estimated fraction of surface daylight remaining at a depth (0..1).
func light_fraction_at_depth(depth_m: float) -> float:
	return exp(-estimated_light_attenuation() * maxf(depth_m, 0.0))


# --- Serialisation ------------------------------------------------------------

func to_dict() -> Dictionary:
	return _values.duplicate()


## Applies known keys from a dictionary (unknown keys are ignored, values clamped).
func apply_dict(data: Dictionary) -> void:
	for key in PARAMETER_ORDER:
		if data.has(key) and (typeof(data[key]) == TYPE_FLOAT or typeof(data[key]) == TYPE_INT):
			set_value(key, float(data[key]))


func save_json(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var payload := {"format": FILE_FORMAT, "version": FILE_VERSION, "parameters": to_dict()}
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
	var parameters = data.get("parameters")
	if typeof(parameters) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR
	apply_dict(parameters)
	return OK
