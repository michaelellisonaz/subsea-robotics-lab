## Left panel: editable environment parameters (built from the
## EnvironmentConfig parameter table), save/load, and visual-only display options.
class_name EnvironmentPanel
extends VBoxContainer

## Where Save / Load store the environment configuration.
var config_path: String = "user://environment_config.json"

var defaults_button: Button
var save_button: Button
var load_button: Button
var grid_toggle: CheckBox
var axes_toggle: CheckBox
var labels_toggle: CheckBox
var particles_toggle: CheckBox
var brightness_slider: HSlider

var _config: EnvironmentConfig
var _renderer: EnvironmentRenderer
var _rows: Dictionary = {}  # key -> {"spin": SpinBox, "slider": HSlider, "scale": float}
var _updating: bool = false
var _status_label: Label


func _init() -> void:
	name = "EnvironmentPanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func bind(config: EnvironmentConfig, renderer: EnvironmentRenderer) -> void:
	_config = config
	_renderer = renderer
	add_child(UIWidgets.section_header("Environment parameters"))
	for key in EnvironmentConfig.PARAMETER_ORDER:
		_add_parameter_row(key)

	var buttons := HBoxContainer.new()
	defaults_button = UIWidgets.button("Defaults", "Restore every parameter to its default value")
	save_button = UIWidgets.button("Save", "Save these parameters to " + config_path)
	load_button = UIWidgets.button("Load", "Load parameters from " + config_path)
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

	_build_display_section()
	config.parameter_changed.connect(_on_parameter_changed)
	for key in _rows:
		_sync_row(key)


func get_slider(key: String) -> HSlider:
	return _rows[key]["slider"]


func get_spin(key: String) -> SpinBox:
	return _rows[key]["spin"]


func get_status_text() -> String:
	return _status_label.text


func _add_parameter_row(key: String) -> void:
	var spec := EnvironmentConfig.get_spec(key)
	var display_scale: float = spec.get("display_scale", 1.0)
	var low: float = spec["min"] * display_scale
	var high: float = spec["max"] * display_scale
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
	var spin := UIWidgets.spin_box(low, high, spec["step"], spec["unit"], description)
	header.add_child(spin)
	row.add_child(header)

	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = spec["step"]
	slider.exp_edit = spec.get("exponential", false)
	slider.focus_mode = Control.FOCUS_NONE
	slider.tooltip_text = description
	row.add_child(slider)
	add_child(row)

	_rows[key] = {"spin": spin, "slider": slider, "scale": display_scale}
	spin.value_changed.connect(_on_widget_changed.bind(key))
	slider.value_changed.connect(_on_widget_changed.bind(key))


func _build_display_section() -> void:
	add_child(UIWidgets.spacer(6.0))
	add_child(UIWidgets.section_header("Display  (visual only)"))
	grid_toggle = _add_toggle("Reference grid  (1 m / 10 m)", _renderer.set_grid_visible)
	axes_toggle = _add_toggle("World axes and depth gauge", _renderer.set_markers_visible)
	labels_toggle = _add_toggle("Distance labels", _renderer.set_labels_visible)
	particles_toggle = _add_toggle("Suspended particles", _renderer.set_particles_visible)

	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = "Scene brightness"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var value_label := UIWidgets.dim_label("")
	header.add_child(value_label)
	add_child(header)
	brightness_slider = HSlider.new()
	brightness_slider.min_value = 0.25
	brightness_slider.max_value = 3.0
	brightness_slider.step = 0.05
	brightness_slider.value = _renderer.get_brightness()
	brightness_slider.focus_mode = Control.FOCUS_NONE
	brightness_slider.tooltip_text = "Rendering exposure only. Does not change any simulation value."
	brightness_slider.value_changed.connect(func(v: float) -> void:
		_renderer.set_brightness(v)
		value_label.text = "%.2f×" % v)
	value_label.text = "%.2f×" % brightness_slider.value
	add_child(brightness_slider)

	var note := UIWidgets.dim_label("Display options change only what is drawn; simulation data is unaffected.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)


func _add_toggle(text: String, callback: Callable) -> CheckBox:
	var toggle := CheckBox.new()
	toggle.text = text
	toggle.button_pressed = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.toggled.connect(callback)
	add_child(toggle)
	return toggle


func _on_widget_changed(value: float, key: String) -> void:
	if _updating:
		return
	_config.set_value(key, value / _rows[key]["scale"])
	# Re-sync in case the value was clamped to the stored value (no signal then).
	_sync_row(key)


func _on_parameter_changed(key: String, _value: float) -> void:
	if _rows.has(key):
		_sync_row(key)


func _sync_row(key: String) -> void:
	var row: Dictionary = _rows[key]
	var shown: float = _config.get_value(key) * row["scale"]
	_updating = true
	row["slider"].value = shown
	row["spin"].value = shown
	_updating = false


func _on_defaults_pressed() -> void:
	_config.reset_to_defaults()
	_status_label.text = "Default parameters restored."


func _on_save_pressed() -> void:
	var err := _config.save_json(config_path)
	if err == OK:
		_status_label.text = "Saved to %s" % config_path
		load_button.disabled = false
	else:
		_status_label.text = "Save failed: %s" % error_string(err)


func _on_load_pressed() -> void:
	var err := _config.load_json(config_path)
	if err == OK:
		_status_label.text = "Loaded %s" % config_path
	else:
		_status_label.text = "Load failed: %s" % error_string(err)
