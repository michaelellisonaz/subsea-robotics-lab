## Read-only environment state: the configured values plus derived quantities
## (pressure, kinematic viscosity, estimated daylight, current components ...).
class_name InfoPanel
extends VBoxContainer

const ROWS := [
	["depth", "Seabed depth (ref.)", ""],
	["pressure_abs", "Pressure at seabed", "Absolute: atmosphere + rho·g·depth (hydrostatic)."],
	["pressure_gauge", "Gauge pressure", "Hydrostatic only: rho·g·depth."],
	["density", "Density", ""],
	["viscosity", "Dynamic viscosity", ""],
	["kinematic", "Kinematic viscosity", "nu = mu / rho"],
	["temperature", "Temperature", "Metadata only in Stage 1."],
	["gravity", "Gravity", ""],
	["visibility", "Visibility", ""],
	["extinction", "Optical extinction", "3.912 / visibility (Koschmieder). Used as the fog density."],
	["daylight", "Daylight at seabed", "Rough estimate: exp(-Kd·depth) with Kd ~ 1.44 / visibility. For visualisation only."],
	["current", "Current", "Direction the current flows toward."],
	["current_en", "Current  E / N", "East and north components of the current."],
	["current_profile", "Current profile", "Above the bottom boundary layer the current is uniform; inside it the speed falls toward the seabed (1/7 power law)."],
	["reynolds", "Re per metre", "Reynolds number U·L/nu for L = 1 m at the current speed. Indicative only."],
	["objects", "Simulation objects", "Objects registered with the simulation engine."],
]

var _engine: SimulationEngine
var _values: Dictionary = {}


func _init() -> void:
	name = "InfoPanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func bind(engine: SimulationEngine) -> void:
	_engine = engine
	add_child(UIWidgets.section_header("Environment state"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	for row in ROWS:
		grid.add_child(UIWidgets.dim_label(row[1], row[2]))
		var value := Label.new()
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)
		_values[row[0]] = value
	add_child(grid)
	engine.environment.parameter_changed.connect(func(_key: String, _value: float) -> void: refresh())
	engine.objects.object_registered.connect(func(_object: SimObject) -> void: refresh())
	engine.objects.object_unregistered.connect(func(_object: SimObject) -> void: refresh())
	refresh()


func get_value_text(key: String) -> String:
	return _values[key].text


func refresh() -> void:
	var env := _engine.environment
	var depth := env.water_depth
	_show("depth", "%.1f m" % depth)
	_show("pressure_abs", "%.2f bar" % (env.absolute_pressure_at_depth(depth) / 1.0e5))
	_show("pressure_gauge", "%.2f bar" % (env.gauge_pressure_at_depth(depth) / 1.0e5))
	_show("density", "%.1f kg/m³" % env.water_density)
	_show("viscosity", "%.2f mPa·s" % (env.dynamic_viscosity * 1000.0))
	_show("kinematic", "%.3f mm²/s" % (env.kinematic_viscosity() * 1.0e6))
	_show("temperature", "%.1f °C" % env.water_temperature)
	_show("gravity", "%.2f m/s²" % env.gravity)
	_show("visibility", "%.1f m" % env.visibility)
	_show("extinction", "%.3f /m" % env.optical_extinction_coefficient())
	_show("daylight", "~%.1f %% of surface" % (env.light_fraction_at_depth(depth) * 100.0))
	_show("current", "%.2f m/s toward %03d° (%s)" % [
		env.current_speed, int(round(env.current_heading)) % 360, WorldFrame.cardinal(env.current_heading)])
	var enu := WorldFrame.godot_to_enu(env.current_velocity())
	_show("current_en", "%+.2f / %+.2f m/s" % [enu.x, enu.y])
	if env.current_boundary_layer > 0.0:
		_show("current_profile", "1/7 law below %.1f m above bed" % env.current_boundary_layer)
	else:
		_show("current_profile", "uniform to the seabed")
	_show("reynolds", _scientific(env.reynolds_number(1.0, env.current_speed)))
	_show("objects", str(_engine.objects.count()))


func _show(key: String, text: String) -> void:
	_values[key].text = text


static func _scientific(value: float) -> String:
	if value <= 0.0:
		return "0"
	var exponent := floori(log(value) / log(10.0))
	return "%.2fe%d" % [value / pow(10.0, exponent), exponent]
