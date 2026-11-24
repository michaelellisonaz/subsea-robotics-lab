## Sensor settings: one collapsible section per sensor (enable switch plus
## its parameter table). Changes apply immediately. Settings can be reset,
## saved and loaded (user://sensor_config.json).
class_name SensorConfigPanel
extends VBoxContainer

var config_path: String = "user://sensor_config.json"

var overlay_toggle: CheckBox
var defaults_button: Button
var save_button: Button
var load_button: Button

var _suite: SensorSuite
var _overlay: SensorOverlay
var _rows: Dictionary = {}  # "sensor/param" -> {"spin", "slider"}
var _enable_boxes: Dictionary = {}  # sensor name -> CheckBox
var _bodies: Dictionary = {}  # sensor name -> VBoxContainer
var _updating: bool = false
var _status_label: Label


func _init() -> void:
	name = "SensorConfigPanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func bind(suite: SensorSuite, overlay: SensorOverlay) -> void:
	_suite = suite
	_overlay = overlay
	add_child(UIWidgets.section_header("Sensors"))
	overlay_toggle = CheckBox.new()
	overlay_toggle.text = "Show sensor coverage in 3D"
	overlay_toggle.button_pressed = overlay.coverage_visible
	overlay_toggle.focus_mode = Control.FOCUS_NONE
	overlay_toggle.toggled.connect(overlay.set_coverage_visible)
	add_child(overlay_toggle)
	var note := UIWidgets.dim_label("Changes apply immediately. Noise uses fixed seeds, so a run is repeatable after Reset.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	for sensor in suite.sensors:
		_add_sensor_section(sensor)
	var buttons := HBoxContainer.new()
	defaults_button = UIWidgets.button("Defaults", "Restore default settings for every sensor")
	save_button = UIWidgets.button("Save", "Save sensor settings to " + config_path)
	load_button = UIWidgets.button("Load", "Load sensor settings from " + config_path)
	for b in [defaults_button, save_button, load_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)
	add_child(buttons)
	defaults_button.pressed.connect(_on_defaults_pressed)
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	load_button.disabled = not FileAccess.file_exists(config_path)
	_status_label = UIWidgets.dim_label("")
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)
	_sync_all()


func get_spin(sensor_name: String, key: String) -> SpinBox:
	return _rows[sensor_name + "/" + key]["spin"]


func get_enable_box(sensor_name: String) -> CheckBox:
	return _enable_boxes[sensor_name]


func _add_sensor_section(sensor: Sensor) -> void:
	add_child(UIWidgets.spacer(2.0))
	var header := HBoxContainer.new()
	var enable := CheckBox.new()
	enable.text = sensor.sensor_name
	enable.tooltip_text = "Enable / disable the " + sensor.sensor_name
	enable.focus_mode = Control.FOCUS_NONE
	enable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enable.add_theme_color_override("font_color", UITheme.ACCENT)
	enable.toggled.connect(func(on: bool) -> void:
		if not _updating:
			sensor.enabled = on)
	header.add_child(enable)
	var expand := UIWidgets.button("+", "Show / hide settings")
	expand.custom_minimum_size = Vector2(28.0, 0.0)
	header.add_child(expand)
	add_child(header)
	_enable_boxes[sensor.sensor_name] = enable

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.visible = false
	var description := UIWidgets.dim_label(sensor.description)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(description)
	var specs := sensor.parameter_specs()
	for key in specs:
		_add_parameter_row(body, sensor, key, specs[key])
	if sensor is StereoCameraSensor:
		var info := UIWidgets.dim_label("")
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(info)
		body.set_meta("stereo_info", info)
	add_child(body)
	_bodies[sensor.sensor_name] = body
	expand.pressed.connect(func() -> void:
		body.visible = not body.visible
		expand.text = "-" if body.visible else "+")


func _add_parameter_row(parent: VBoxContainer, sensor: Sensor, key: String, spec: Dictionary) -> void:
	var description: String = spec["description"]
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = spec["label"]
	label.tooltip_text = description
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var spin := UIWidgets.spin_box(spec["min"], spec["max"], spec["step"], spec["unit"], description)
	header.add_child(spin)
	row.add_child(header)
	var slider := HSlider.new()
	slider.min_value = spec["min"]
	slider.max_value = spec["max"]
	slider.step = spec["step"]
	slider.focus_mode = Control.FOCUS_NONE
	slider.tooltip_text = description
	row.add_child(slider)
	parent.add_child(row)
	var id := sensor.sensor_name + "/" + key
	_rows[id] = {"spin": spin, "slider": slider, "sensor": sensor, "key": key}
	spin.value_changed.connect(_on_widget_changed.bind(id))
	slider.value_changed.connect(_on_widget_changed.bind(id))


func _on_widget_changed(value: float, id: String) -> void:
	if _updating:
		return
	var row: Dictionary = _rows[id]
	row["sensor"].set_param(row["key"], value)
	_sync_row(id)


func _sync_all() -> void:
	_updating = true
	for sensor in _suite.sensors:
		_enable_boxes[sensor.sensor_name].button_pressed = sensor.enabled
	_updating = false
	for id in _rows:
		_sync_row(id)


func _sync_row(id: String) -> void:
	var row: Dictionary = _rows[id]
	var value: float = row["sensor"].get_param(row["key"])
	_updating = true
	row["slider"].value = value
	row["spin"].value = value
	_updating = false
	if row["sensor"] is StereoCameraSensor:
		_update_stereo_info(row["sensor"])


func _update_stereo_info(sensor: StereoCameraSensor) -> void:
	var body: VBoxContainer = _bodies.get(sensor.sensor_name)
	if body == null or not body.has_meta("stereo_info"):
		return
	var info: Label = body.get_meta("stereo_info")
	info.text = "Focal length %.0f px · depth resolution (1 px disparity): %.1f cm at 2 m, %.1f cm at 5 m" % [
		sensor.focal_length_pixels(), sensor.depth_resolution(2.0) * 100.0, sensor.depth_resolution(5.0) * 100.0]


func _on_defaults_pressed() -> void:
	_suite.reset_parameters()
	_sync_all()
	_status_label.text = "Default sensor settings restored."


func _on_save_pressed() -> void:
	var err := _suite.save_json(config_path)
	if err == OK:
		_status_label.text = "Saved to %s" % config_path
		load_button.disabled = false
	else:
		_status_label.text = "Save failed: %s" % error_string(err)


func _on_load_pressed() -> void:
	var err := _suite.load_json(config_path)
	_sync_all()
	_status_label.text = "Loaded %s" % config_path if err == OK else "Load failed: %s" % error_string(err)
