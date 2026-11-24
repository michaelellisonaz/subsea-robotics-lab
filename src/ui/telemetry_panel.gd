## Vehicle telemetry (live state), thruster output, and the applied
## configuration's static and performance characteristics.
class_name TelemetryPanel
extends VBoxContainer

const REFRESH_INTERVAL := 0.08  # s
const TELEMETRY_ROWS := [
	["control", "Control", "What the keyboard controls (Tab toggles pilot / free camera, V cycles views)."],
	["position", "Position", "East, north and depth of the vehicle CG."],
	["depth", "Depth", ""],
	["altitude", "Altitude", "Lowest hull point above the local seabed."],
	["heading", "Heading", "Compass heading of the vehicle's bow."],
	["attitude", "Pitch / roll", "Pitch positive nose up; roll positive starboard down."],
	["sog", "Speed over ground", ""],
	["stw", "Speed through water", "Speed relative to the local current."],
	["body", "Surge / sway / heave", "Velocity along the vehicle's own axes (forward, starboard, up)."],
	["yaw_rate", "Yaw rate", "Positive clockwise seen from above."],
	["net_buoyancy", "Net buoyancy", "In the current water (density and gravity from the Environment tab)."],
	["contact", "Seabed contact", ""],
	["lights", "Lights (L)", ""],
	["trip", "Distance / max speed", "Since the last reset."],
]
const CHARACTERISTIC_ROWS := [
	["mass", "Weight / buoyancy", "Weight in air and full buoyancy in the current water."],
	["volume", "Displaced volume", ""],
	["bg", "BG (CB above CG)", "Positive = passively stable in roll and pitch."],
	["trim", "Static pitch trim", "Equilibrium pitch from the CG / CB arrangement."],
	["restoring", "Roll / pitch stiffness", "Small-angle restoring moment, buoyancy x BG."],
	["periods", "Roll / pitch period", "Undamped natural periods, including added inertia."],
	["thrust_surge", "Surge thrust fwd / rev", "Maximum force from the thruster layout (allocation-limited)."],
	["thrust_sway", "Sway thrust", ""],
	["thrust_heave", "Heave thrust up / down", ""],
	["moments", "Yaw / pitch / roll moment", "Maximum moments; 0 = axis not actuated by this layout."],
	["speed_surge", "Top speed surge fwd / rev", "Predicted steady speed in still water, one axis at a time."],
	["speed_sway", "Top speed sway", ""],
	["speed_heave", "Top speed heave up / down", "Includes net buoyancy."],
	["yaw_rate_max", "Max yaw rate", ""],
]

var _engine: SimulationEngine
var _vehicle: RovVehicle
var _views: ViewController
## Set by the dashboard so the control row can show arm control.
var pilot: PilotInput
var _values: Dictionary = {}
var _characteristics: Dictionary = {}
var _thruster_box: VBoxContainer
var _thrust_bars: Array[ThrustBar] = []
var _thrust_labels: Array[Label] = []
var _stability_warning: Label
var _elapsed: float = 0.0

var depth_hold_toggle: CheckBox
var heading_hold_toggle: CheckBox
var position_hold_toggle: CheckBox
var attitude_hold_toggle: CheckBox
var _aids_label: Label


func _init() -> void:
	name = "TelemetryPanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func bind(engine: SimulationEngine, vehicle: RovVehicle, views: ViewController) -> void:
	_engine = engine
	_vehicle = vehicle
	_views = views
	add_child(UIWidgets.section_header("Pilot aids (sensor-based)"))
	var aids_row := HBoxContainer.new()
	depth_hold_toggle = CheckBox.new()
	depth_hold_toggle.text = "Depth hold (J)"
	depth_hold_toggle.tooltip_text = "Hold the measured depth (depth sensor + DVL). Heave input overrides and re-captures."
	heading_hold_toggle = CheckBox.new()
	heading_hold_toggle.text = "Heading hold (K)"
	heading_hold_toggle.tooltip_text = "Hold the measured heading (compass + IMU). Yaw input overrides and re-captures."
	position_hold_toggle = CheckBox.new()
	position_hold_toggle.text = "Position (B)"
	position_hold_toggle.tooltip_text = "Station keeping from DVL dead reckoning + compass. Surge / sway input overrides and re-captures."
	depth_hold_toggle.text = "Depth (J)"
	heading_hold_toggle.text = "Heading (K)"
	attitude_hold_toggle = CheckBox.new()
	attitude_hold_toggle.text = "Level (T)"
	attitude_hold_toggle.tooltip_text = "Attitude hold: keeps pitch and roll at zero using the IMU (auto-trim)."
	for toggle in [depth_hold_toggle, heading_hold_toggle, position_hold_toggle, attitude_hold_toggle]:
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		aids_row.add_child(toggle)
	add_child(aids_row)
	attitude_hold_toggle.toggled.connect(func(on: bool) -> void:
		if on != vehicle.aids.attitude_hold:
			vehicle.aids.set_attitude_hold(on, vehicle, vehicle.last_update_time)
		_sync_aids())
	position_hold_toggle.toggled.connect(func(on: bool) -> void:
		if on != vehicle.aids.position_hold:
			vehicle.aids.set_position_hold(on, vehicle, vehicle.last_update_time)
		_sync_aids())
	depth_hold_toggle.toggled.connect(func(on: bool) -> void:
		if on != vehicle.aids.depth_hold:
			vehicle.aids.set_depth_hold(on, vehicle, vehicle.last_update_time)
		_sync_aids())
	heading_hold_toggle.toggled.connect(func(on: bool) -> void:
		if on != vehicle.aids.heading_hold:
			vehicle.aids.set_heading_hold(on, vehicle, vehicle.last_update_time)
		_sync_aids())
	_aids_label = UIWidgets.dim_label("")
	_aids_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_aids_label)
	add_child(UIWidgets.spacer(4.0))
	add_child(UIWidgets.section_header(vehicle.display_name + "  (true state)"))
	add_child(_make_grid(TELEMETRY_ROWS, _values))
	add_child(UIWidgets.spacer(4.0))
	add_child(UIWidgets.section_header("Thrusters"))
	_thruster_box = VBoxContainer.new()
	_thruster_box.add_theme_constant_override("separation", 2)
	add_child(_thruster_box)
	add_child(UIWidgets.spacer(4.0))
	add_child(UIWidgets.section_header("Characteristics (applied configuration)"))
	add_child(_make_grid(CHARACTERISTIC_ROWS, _characteristics))
	_stability_warning = Label.new()
	_stability_warning.add_theme_color_override("font_color", UITheme.STATE_PAUSED)
	_stability_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_stability_warning)
	var note := UIWidgets.dim_label("Predictions use the simplified models described in the README; they are estimates, not validated performance data.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	vehicle.configuration_applied.connect(_on_configuration_applied)
	engine.environment.parameter_changed.connect(func(_key: String, _value: float) -> void: refresh_characteristics())
	_on_configuration_applied()
	refresh()


func get_value_text(key: String) -> String:
	return _values[key].text


func get_characteristic_text(key: String) -> String:
	return _characteristics[key].text


func _process(delta: float) -> void:
	if _vehicle == null:
		return
	_elapsed += delta
	if _elapsed >= REFRESH_INTERVAL:
		_elapsed = 0.0
		refresh()


func _sync_aids() -> void:
	var aids := _vehicle.aids
	depth_hold_toggle.set_pressed_no_signal(aids.depth_hold)
	heading_hold_toggle.set_pressed_no_signal(aids.heading_hold)
	position_hold_toggle.set_pressed_no_signal(aids.position_hold)
	attitude_hold_toggle.set_pressed_no_signal(aids.attitude_hold)
	var parts: Array[String] = []
	if aids.depth_hold:
		parts.append("holding %.2f m depth" % aids.depth_setpoint)
	if aids.heading_hold:
		parts.append("holding heading %05.1f°" % aids.heading_setpoint)
	if aids.position_hold:
		parts.append("holding position (estimated offset %.2f m)" % aids.position_offset.length())
	if aids.attitude_hold:
		parts.append("keeping level")
	var text := ", ".join(parts)
	if aids.status != "":
		text = aids.status if text == "" else text + "
" + aids.status
	_aids_label.text = text if text != "" else "Off. Aids use sensor readings, so they need the simulation running."


func refresh() -> void:
	_sync_aids()
	var v := _vehicle
	var world := _engine.world
	var body := v.body_velocity_components()
	var sog := v.velocity.length()
	var controlling := "PILOT · "
	if pilot != null and pilot.arm_mode:
		controlling = "ARM · "
	_show("control", (controlling if _views.is_piloting() else "") + _views.get_mode_name())
	_show("position", "E %.1f  N %.1f  D %.1f m" % [v.position.x, -v.position.z, -v.position.y])
	_show("depth", "%.2f m" % v.depth())
	_show("altitude", "%.2f m" % v.altitude(world))
	_show("heading", "%05.1f° (%s)" % [v.heading_degrees(), WorldFrame.cardinal(v.heading_degrees())])
	_show("attitude", "%+.1f° / %+.1f°" % [v.pitch_degrees(), v.roll_degrees()])
	_show("sog", "%.2f m/s  (%.2f kn)" % [sog, sog * 1.943844])
	_show("stw", "%.2f m/s" % v.water_relative_velocity(world).length())
	_show("body", "%+.2f / %+.2f / %+.2f m/s" % [body.x, body.y, body.z])
	_show("yaw_rate", "%+.1f °/s" % v.yaw_rate_degrees())
	var net := v.net_buoyancy(_engine.environment)
	_show("net_buoyancy", "%+.1f N (%s)" % [net, "floats" if net > 0.05 else ("sinks" if net < -0.05 else "neutral")])
	_show("contact", "Yes (%d points)" % v.contact.points_in_contact if v.in_seabed_contact else "No")
	_show("lights", "On" if v.lights_on else "Off")
	_show("trip", "%.1f m / %.2f m/s" % [v.distance_travelled, v.max_speed])
	for i in mini(_thrust_bars.size(), v.thrusters.size()):
		var thruster := v.thrusters[i]
		_thrust_bars[i].fraction = thruster.thrust_fraction()
		_thrust_labels[i].text = "%+.0f N" % thruster.thrust


func refresh_characteristics() -> void:
	var c := _vehicle.characteristics(_engine.environment)
	_set_characteristic("mass", "%.0f / %.0f N" % [c["weight"], c["buoyancy"]])
	_set_characteristic("volume", "%.4f m³" % c["displaced_volume"])
	_set_characteristic("bg", "%.3f m" % c["bg"])
	_set_characteristic("trim", "-" if is_nan(c["static_pitch_trim"]) else "%+.1f°" % c["static_pitch_trim"])
	_set_characteristic("restoring", "%.0f N·m/rad" % c["restoring_stiffness"])
	_set_characteristic("periods", "%s / %s" % [_period(c["roll_period"]), _period(c["pitch_period"])])
	_set_characteristic("thrust_surge", "%.0f / %.0f N" % [c["thrust_surge_forward"], c["thrust_surge_reverse"]])
	_set_characteristic("thrust_sway", "%.0f N" % c["thrust_sway"])
	_set_characteristic("thrust_heave", "%.0f / %.0f N" % [c["thrust_heave_up"], c["thrust_heave_down"]])
	_set_characteristic("moments", "%.0f / %.0f / %.0f N·m" % [c["moment_yaw"], c["moment_pitch"], c["moment_roll"]])
	_set_characteristic("speed_surge", "%.2f / %.2f m/s" % [c["speed_surge"], c["speed_surge_reverse"]])
	_set_characteristic("speed_sway", "%.2f m/s" % c["speed_sway"])
	_set_characteristic("speed_heave", "%.2f / %.2f m/s" % [c["speed_heave_up"], c["speed_heave_down"]])
	_set_characteristic("yaw_rate_max", "%.0f °/s" % c["yaw_rate"])
	if c["bg"] <= 0.0:
		_stability_warning.text = "Warning: CB is not above CG - the vehicle has no passive roll/pitch stability."
	else:
		_stability_warning.text = ""


func _on_configuration_applied() -> void:
	for child in _thruster_box.get_children():
		child.free()
	_thrust_bars.clear()
	_thrust_labels.clear()
	for thruster in _vehicle.thrusters:
		var row := HBoxContainer.new()
		var name_label := UIWidgets.dim_label(thruster.thruster_name)
		name_label.custom_minimum_size = Vector2(88.0, 0.0)
		row.add_child(name_label)
		var bar := ThrustBar.new()
		row.add_child(bar)
		var value := Label.new()
		value.custom_minimum_size = Vector2(56.0, 0.0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		_thruster_box.add_child(row)
		_thrust_bars.append(bar)
		_thrust_labels.append(value)
	refresh_characteristics()


func _make_grid(rows: Array, target: Dictionary) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	for row in rows:
		grid.add_child(UIWidgets.dim_label(row[1], row[2]))
		var value := Label.new()
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)
		target[row[0]] = value
	return grid


func _show(key: String, text: String) -> void:
	_values[key].text = text


func _set_characteristic(key: String, text: String) -> void:
	_characteristics[key].text = text


static func _period(seconds: float) -> String:
	return "-" if is_inf(seconds) or is_nan(seconds) else "%.2f s" % seconds
