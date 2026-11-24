## Vehicle configuration editor. Edits go into a DRAFT configuration; Apply
## rebuilds the vehicle from it and resets the simulation (a new experiment).
## Revert discards the draft, Defaults loads default values into the draft,
## Save / Load store the draft as JSON.
class_name VehicleConfigPanel
extends VBoxContainer

var config_path: String = "user://vehicle_config.json"

var apply_button: Button
var revert_button: Button
var defaults_button: Button
var save_button: Button
var load_button: Button
var layout_option: OptionButton
var arm_layout_option: OptionButton
var markers_toggle: CheckBox

var _engine: SimulationEngine
var _vehicle: RovVehicle
var _visual: RovVisual
var _draft: VehicleConfig
var _rows: Dictionary = {}
var _updating: bool = false
var _status_label: Label
var _layout_description: Label


func _init() -> void:
	name = "VehicleConfigPanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func bind(engine: SimulationEngine, vehicle: RovVehicle, visual: RovVisual) -> void:
	_engine = engine
	_vehicle = vehicle
	_visual = visual
	_draft = vehicle.config.duplicate_config()

	add_child(UIWidgets.section_header("Thruster layout"))
	layout_option = OptionButton.new()
	layout_option.focus_mode = Control.FOCUS_NONE
	for layout_id in VehicleConfig.LAYOUT_ORDER:
		layout_option.add_item(VehicleConfig.LAYOUTS[layout_id]["label"])
	layout_option.item_selected.connect(_on_layout_selected)
	add_child(layout_option)
	_layout_description = UIWidgets.dim_label("")
	_layout_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_layout_description)

	add_child(UIWidgets.spacer(4.0))
	add_child(UIWidgets.section_header("Vehicle parameters"))
	for key in VehicleConfig.PARAMETER_ORDER:
		if key == "arm_upper_length":
			add_child(UIWidgets.spacer(4.0))
			add_child(UIWidgets.section_header("Manipulator"))
			arm_layout_option = OptionButton.new()
			arm_layout_option.focus_mode = Control.FOCUS_NONE
			for layout_id in VehicleConfig.ARM_LAYOUT_ORDER:
				arm_layout_option.add_item(VehicleConfig.ARM_LAYOUTS[layout_id]["label"])
			arm_layout_option.item_selected.connect(_on_arm_layout_selected)
			add_child(arm_layout_option)
		_add_parameter_row(key)

	var row_1 := HBoxContainer.new()
	apply_button = UIWidgets.button("Apply", "Rebuild the vehicle from these values and reset the simulation")
	revert_button = UIWidgets.button("Revert", "Discard edits and show the applied configuration")
	defaults_button = UIWidgets.button("Defaults", "Load default values (press Apply to use them)")
	for b in [apply_button, revert_button, defaults_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_1.add_child(b)
	add_child(row_1)
	var row_2 := HBoxContainer.new()
	save_button = UIWidgets.button("Save", "Save these values to " + config_path)
	load_button = UIWidgets.button("Load", "Load values from " + config_path + " (press Apply to use them)")
	for b in [save_button, load_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_2.add_child(b)
	add_child(row_2)
	apply_button.pressed.connect(apply_draft)
	revert_button.pressed.connect(_on_revert_pressed)
	defaults_button.pressed.connect(_on_defaults_pressed)
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	load_button.disabled = not FileAccess.file_exists(config_path)

	_status_label = UIWidgets.dim_label("")
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	add_child(UIWidgets.spacer(6.0))
	add_child(UIWidgets.section_header("Vehicle display"))
	markers_toggle = CheckBox.new()
	markers_toggle.text = "CG / CB markers and thrust arrows"
	markers_toggle.button_pressed = visual.markers_visible
	markers_toggle.focus_mode = Control.FOCUS_NONE
	markers_toggle.toggled.connect(visual.set_markers_visible)
	add_child(markers_toggle)

	_draft.changed_value.connect(func(_key: String) -> void: _update_dirty_state())
	_sync_all()


func get_spin(key: String) -> SpinBox:
	return _rows[key]["spin"]


func get_slider(key: String) -> HSlider:
	return _rows[key]["slider"]


func get_draft() -> VehicleConfig:
	return _draft


func is_dirty() -> bool:
	return not _draft.equals(_vehicle.config)


## Rebuilds the vehicle from the draft and resets the simulation.
func apply_draft() -> void:
	_vehicle.apply_config(_draft.duplicate_config())
	_engine.reset()
	_status_label.text = "Configuration applied; simulation reset."
	_update_dirty_state()


func _add_parameter_row(key: String) -> void:
	var spec := VehicleConfig.get_spec(key)
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
	add_child(row)
	_rows[key] = {"spin": spin, "slider": slider}
	spin.value_changed.connect(_on_widget_changed.bind(key))
	slider.value_changed.connect(_on_widget_changed.bind(key))


func _on_widget_changed(value: float, key: String) -> void:
	if _updating:
		return
	_draft.set_value(key, value)
	_sync_row(key)


func _on_layout_selected(index: int) -> void:
	if _updating:
		return
	_draft.set_layout(VehicleConfig.LAYOUT_ORDER[index])
	_sync_layout()


func _sync_all() -> void:
	for key in _rows:
		_sync_row(key)
	_sync_layout()
	_update_dirty_state()


func _sync_row(key: String) -> void:
	var row: Dictionary = _rows[key]
	var value := _draft.get_value(key)
	_updating = true
	row["slider"].value = value
	row["spin"].value = value
	_updating = false


func _on_arm_layout_selected(index: int) -> void:
	if _updating:
		return
	_draft.set_arm_layout(VehicleConfig.ARM_LAYOUT_ORDER[index])
	_sync_layout()


func _sync_layout() -> void:
	_updating = true
	layout_option.select(VehicleConfig.LAYOUT_ORDER.find(_draft.layout))
	arm_layout_option.select(VehicleConfig.ARM_LAYOUT_ORDER.find(_draft.arm_layout))
	_updating = false
	_layout_description.text = VehicleConfig.LAYOUTS[_draft.layout]["description"]


func _update_dirty_state() -> void:
	apply_button.disabled = not is_dirty()
	revert_button.disabled = not is_dirty()
	if is_dirty():
		_status_label.text = "Edited - press Apply to rebuild the vehicle (resets the simulation)."


func _replace_draft(source: VehicleConfig) -> void:
	_draft.apply_dict(source.to_dict())
	_sync_all()


func _on_revert_pressed() -> void:
	_replace_draft(_vehicle.config)
	_status_label.text = "Edits discarded."


func _on_defaults_pressed() -> void:
	_replace_draft(VehicleConfig.new())
	_status_label.text = "Default values loaded - press Apply to use them." if is_dirty() else "Defaults are already applied."


func _on_save_pressed() -> void:
	var err := _draft.save_json(config_path)
	if err == OK:
		_status_label.text = "Saved to %s" % config_path
		load_button.disabled = false
	else:
		_status_label.text = "Save failed: %s" % error_string(err)


func _on_load_pressed() -> void:
	var loaded := VehicleConfig.new()
	var err := loaded.load_json(config_path)
	if err != OK:
		_status_label.text = "Load failed: %s" % error_string(err)
		return
	_replace_draft(loaded)
	_status_label.text = "Loaded %s - press Apply to use it." % config_path if is_dirty() else "Loaded %s (same as applied)." % config_path
