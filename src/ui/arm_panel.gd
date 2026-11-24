## Manipulator panel: arm control mode, joint sliders (joint mode), tool
## position, move-to command (inverse kinematics), gripper and load status,
## tool selection / change, tool contact force and readings (CP log),
## collision state, payload capacity versus reach, reach envelope and the
## accuracy test.
class_name ArmPanel
extends VBoxContainer

const REFRESH_INTERVAL := 0.08

var arm_mode_button: Button
var stow_button: Button
var ready_button: Button
var gripper_button: Button
var test_button: Button
var go_button: Button
var envelope_toggle: CheckBox
var move_fields: Dictionary = {}
var tool_option: OptionButton
var change_tool_button: Button
var tool_action_button: Button
var cp_log_label: Label

var _vehicle: RovVehicle
var _visual: RovVisual
var _pilot: PilotInput
var _environment: EnvironmentConfig
var _content: VBoxContainer
var _sliders: Array[HSlider] = []
var _joint_labels: Array[Label] = []
var _values: Dictionary = {}
var _status: Label
var _test_label: Label
var _updating: bool = false
var _elapsed: float = 0.0
var _shown_tool: Object = null


func _init() -> void:
	name = "ArmPanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func bind(vehicle: RovVehicle, visual: RovVisual, pilot: PilotInput, environment: EnvironmentConfig) -> void:
	_environment = environment
	_vehicle = vehicle
	_visual = visual
	_pilot = pilot
	vehicle.configuration_applied.connect(_build)
	pilot.arm_mode_changed.connect(func(_active: bool) -> void: _refresh_mode())
	_build()


func get_slider(index: int) -> HSlider:
	return _sliders[index]


func get_value_text(key: String) -> String:
	return _values[key].text


func _build() -> void:
	if _content != null:
		_content.free()
	_sliders.clear()
	_joint_labels.clear()
	_shown_tool = null
	_values.clear()
	move_fields.clear()
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	add_child(_content)
	var arm := _vehicle.manipulator
	_content.add_child(UIWidgets.section_header("Manipulator"))
	if not arm.is_installed():
		var none := UIWidgets.dim_label("No manipulator fitted. Choose an arm layout in Vehicle setup and press Apply.")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(none)
		return
	var layout_label := UIWidgets.dim_label(VehicleConfig.ARM_LAYOUTS[arm.layout]["label"])
	_content.add_child(layout_label)
	arm_mode_button = UIWidgets.button("Arm control (M)", "Keyboard moves the tool instead of the vehicle; engages depth and heading hold")
	arm_mode_button.toggle_mode = true
	arm_mode_button.toggled.connect(func(on: bool) -> void:
		if not _updating:
			_pilot.set_arm_mode(on)
			_refresh_mode())
	_content.add_child(arm_mode_button)
	_status = UIWidgets.dim_label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status)

	_content.add_child(UIWidgets.spacer(2.0))
	_content.add_child(UIWidgets.section_header("Joints (drag = joint mode)"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	for i in arm.joints.size():
		var joint := arm.joints[i]
		grid.add_child(UIWidgets.dim_label(joint.joint_name.replace("_", " ")))
		var slider := HSlider.new()
		slider.min_value = rad_to_deg(joint.min_angle)
		slider.max_value = rad_to_deg(joint.max_angle)
		slider.step = 0.5
		slider.focus_mode = Control.FOCUS_NONE
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(120.0, 0.0)
		slider.tooltip_text = "Target angle of the %s joint (%.0f° to %.0f°)" % [joint.joint_name, slider.min_value, slider.max_value]
		slider.value_changed.connect(_on_slider_changed.bind(i))
		grid.add_child(slider)
		var label := Label.new()
		label.custom_minimum_size = Vector2(70.0, 0.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(label)
		_sliders.append(slider)
		_joint_labels.append(label)
	_content.add_child(grid)

	var poses := HBoxContainer.new()
	stow_button = UIWidgets.button("Stow (X)", "Fold the arm into its transport position")
	ready_button = UIWidgets.button("Ready", "Working pose in front of the vehicle")
	gripper_button = UIWidgets.button("Gripper (G)", "Open / close the gripper")
	for b in [stow_button, ready_button, gripper_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		poses.add_child(b)
	_content.add_child(poses)
	stow_button.pressed.connect(arm.stow)
	ready_button.pressed.connect(arm.ready_pose)
	gripper_button.pressed.connect(func() -> void: arm.tool_action(_vehicle.last_update_time))

	_content.add_child(UIWidgets.spacer(2.0))
	_content.add_child(UIWidgets.section_header("Tools (skid)"))
	var tool_row := HBoxContainer.new()
	tool_option = OptionButton.new()
	tool_option.focus_mode = Control.FOCUS_NONE
	tool_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_option.clip_text = true
	tool_option.custom_minimum_size = Vector2(120.0, 0.0)
	tool_option.add_item("Gripper (no tool)")
	tool_option.set_item_tooltip(0, "Free gripper jaws for picking up items.")
	for t in arm.tools:
		tool_option.add_item(t.display_name)
		tool_option.set_item_tooltip(tool_option.item_count - 1, t.description)
	tool_row.add_child(tool_option)
	change_tool_button = UIWidgets.button("Change (N)", "Stow the arm and swap the tool in the skid (about %.0f s plus stowing)" % Manipulator.TOOL_CHANGE_TIME)
	change_tool_button.pressed.connect(func() -> void:
		var index := tool_option.selected
		arm.request_tool(null if index <= 0 else arm.tools[index - 1]))
	tool_row.add_child(change_tool_button)
	_content.add_child(tool_row)
	tool_action_button = UIWidgets.button("Tool action (G)", "Brush: spin on / off. CP probe: log the current reading.")
	tool_action_button.pressed.connect(func() -> void: arm.tool_action(_vehicle.last_update_time))
	_content.add_child(tool_action_button)
	_content.add_child(_grid([
		["tool_name", "Mounted", "Tool held in the gripper."],
		["tool_status", "Tool status", ""],
		["tool_force", "Contact force", "Force on the tool tip from its compliant mount (working range in brackets)."],
		["contact", "Arm contact", "Arm, gripper, tool or held item touching the seabed or a structure. Motions that push further in are refused."],
	]))
	cp_log_label = UIWidgets.dim_label("")
	cp_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(cp_log_label)

	_content.add_child(UIWidgets.spacer(2.0))
	_content.add_child(UIWidgets.section_header("Tool"))
	_content.add_child(_grid([
		["tool_vehicle", "Tool (fwd / stbd / up)", "Fingertip centre relative to the vehicle CG, vehicle axes."],
		["tool_world", "Tool (world)", "East, north and depth of the fingertip centre."],
		["tool_angles", "Tool pitch / roll", ""],
		["ik", "Inverse kinematics", "Result of the last Cartesian command."],
		["gripper", "Gripper", ""],
		["payload", "Payload (in water)", "Apparent mass of the held item."],
		["load", "Shoulder load", "Static shoulder moment of arm + payload versus the capacity derived from the rated payload."],
	]))

	_content.add_child(UIWidgets.spacer(2.0))
	_content.add_child(UIWidgets.section_header("Move tool to (relative to arm base)"))
	var move := GridContainer.new()
	move.columns = 2
	for spec in [["forward", "Forward", 0.0, 1.5, 0.6, "m"], ["starboard", "Starboard", -1.2, 1.2, 0.0, "m"],
			["up", "Up", -1.2, 1.2, -0.3, "m"], ["pitch", "Tool pitch", -90.0, 60.0, -45.0, "°"]]:
		move.add_child(Label.new())
		move.get_child(move.get_child_count() - 1).text = spec[1]
		var spin := UIWidgets.spin_box(spec[2], spec[3], 0.01 if spec[5] == "m" else 1.0, spec[5])
		spin.value = spec[4]
		move.add_child(spin)
		move_fields[spec[0]] = spin
	_content.add_child(move)
	go_button = UIWidgets.button("Go", "Solve inverse kinematics and move the tool there (closest reachable point if out of reach)")
	go_button.pressed.connect(_on_go_pressed)
	_content.add_child(go_button)

	_content.add_child(UIWidgets.spacer(2.0))
	_content.add_child(UIWidgets.section_header("Reach and capacity"))
	envelope_toggle = CheckBox.new()
	envelope_toggle.text = "Show reach envelope"
	envelope_toggle.focus_mode = Control.FOCUS_NONE
	envelope_toggle.button_pressed = _visual.arm_visual != null and _visual.arm_visual.envelope_visible
	envelope_toggle.toggled.connect(func(on: bool) -> void: _visual.arm_visual.set_envelope_visible(on))
	_content.add_child(envelope_toggle)
	var reach := arm.full_reach()
	var capacity_rows: Array = []
	for fraction in [0.4, 0.6, 0.8, 1.0]:
		capacity_rows.append(["cap_%d" % int(fraction * 100), "At %.2f m reach" % (reach * fraction), "Static lift limit in water at this horizontal reach from the shoulder."])
	_content.add_child(_grid(capacity_rows))
	for fraction in [0.4, 0.6, 0.8, 1.0]:
		_values["cap_%d" % int(fraction * 100)].text = "%.1f kg" % arm.payload_capacity_at(reach * fraction)

	_content.add_child(UIWidgets.spacer(2.0))
	_content.add_child(UIWidgets.section_header("Accuracy test"))
	test_button = UIWidgets.button("Run accuracy test", "Moves the tool to 8 targets and measures the final position error (needs the simulation running)")
	test_button.pressed.connect(arm.start_accuracy_test)
	_content.add_child(test_button)
	_test_label = UIWidgets.dim_label("Not run yet.")
	_test_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_test_label)
	_refresh_mode()
	refresh()


func _grid(rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	for row in rows:
		grid.add_child(UIWidgets.dim_label(row[1], row[2]))
		var value := Label.new()
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.custom_minimum_size = Vector2(110.0, 0.0)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(value)
		_values[row[0]] = value
	return grid


func _process(delta: float) -> void:
	if _vehicle == null or not _vehicle.manipulator.is_installed():
		return
	_elapsed += delta
	if _elapsed >= REFRESH_INTERVAL:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	var arm := _vehicle.manipulator
	if not arm.is_installed() or _sliders.is_empty():
		return
	_updating = true
	for i in arm.joints.size():
		var joint := arm.joints[i]
		_sliders[i].set_value_no_signal(rad_to_deg(joint.target))
		_joint_labels[i].text = "%+.1f°" % rad_to_deg(joint.angle())
	_updating = false
	var tool := arm.tool_transform()
	var v := WorldFrame.body_to_vehicle(tool.origin)
	_values["tool_vehicle"].text = "%+.2f / %+.2f / %+.2f m" % [v.x, v.y, v.z]
	var world := _vehicle.local_to_world_point(tool.origin)
	_values["tool_world"].text = "E %.2f  N %.2f  D %.2f" % [world.x, -world.z, -world.y]
	var direction := -tool.basis.z
	var roll := 0.0
	for joint in arm.joints:
		if joint.is_roll:
			roll = rad_to_deg(joint.angle())
	_values["tool_angles"].text = "%+.1f° / %+.1f°" % [rad_to_deg(asin(clampf(direction.y, -1.0, 1.0))), roll]
	_values["ik"].text = "%s (%.1f mm)" % [arm.ik_status, arm.ik_error * 1000.0]
	var state := "holding" if arm.grasped != null else ("closing" if arm.gripper_closing else "open")
	_values["gripper"].text = "%s, %.0f mm" % [state, arm.gripper_opening * 1000.0]
	if arm.grasped != null:
		_values["payload"].text = "%s, %.1f kg" % [arm.grasped.display_name, arm.grasped.submerged_weight(_environment) / _environment.gravity]
	else:
		_values["payload"].text = "-"
	_values["load"].text = "%.0f of %.0f N·m (%.0f %%)" % [arm.shoulder_moment, arm.shoulder_capacity,
		100.0 * arm.shoulder_moment / maxf(arm.shoulder_capacity, 1.0)]
	_status.text = arm.status_message
	_refresh_tools(arm)
	if arm.accuracy_test_running:
		_test_label.text = "Running: target %d of %d ..." % [arm.accuracy_results.size() + 1, Manipulator.TEST_TARGETS.size()]
	elif not arm.accuracy_results.is_empty():
		var s := arm.accuracy_summary()
		_test_label.text = "%d of %d targets reached. Position error: mean %.1f mm, max %.1f mm. Mean time per move %.1f s." % [
			s.get("reached", 0), s.get("count", 0), s.get("mean_error", 0.0) * 1000.0, s.get("max_error", 0.0) * 1000.0, s.get("mean_time", 0.0)]


func _refresh_tools(arm: Manipulator) -> void:
	var t := arm.tool
	if t != _shown_tool and arm.tool_change_phase == "":
		# Show the mounted tool in the selector once a change completes.
		_shown_tool = t
		tool_option.select(0 if t == null else arm.tools.find(t) + 1)
	if arm.tool_change_phase == "stowing":
		_values["tool_name"].text = "changing: stowing arm"
	elif arm.tool_change_phase == "swapping":
		_values["tool_name"].text = "changing: %.1f s left" % maxf(arm.tool_change_remaining, 0.0)
	else:
		_values["tool_name"].text = t.display_name if t != null else "none (gripper free)"
	tool_action_button.text = "%s (G)" % (t.action_label() if t != null else "Gripper open / close")
	_values["tool_status"].text = t.status if t != null else "-"
	if t != null:
		var range_text := "%.0f-%.0f N" % [t.min_force, t.max_force] if t.max_force > 0.0 else ""
		_values["tool_force"].text = "%.0f N  (%s)" % [t.contact_force, range_text]
	else:
		_values["tool_force"].text = "-"
	if arm.collision_info == "":
		_values["contact"].text = "clear"
	else:
		_values["contact"].text = "%s%s (%.0f mm)" % ["BLOCKED: " if arm.blocked else "", arm.collision_info, arm.collision_depth * 1000.0]
	var probe: CpProbe = null
	for candidate in arm.tools:
		if candidate is CpProbe:
			probe = candidate
	if probe == null or probe.log.is_empty():
		cp_log_label.text = "CP log: no readings yet."
	else:
		var lines: Array[String] = ["CP log (mV vs Ag/AgCl, criterion %.0f):" % Pipeline.CP_CRITERION]
		for entry in probe.log.slice(maxi(0, probe.log.size() - 6)):
			lines.append("E %.2f, %s: %.0f mV %s" % [entry["east"], entry["surface"], entry["potential"],
				"(protected)" if entry["potential"] <= Pipeline.CP_CRITERION else "(UNDER-PROTECTED)"])
		cp_log_label.text = "\n".join(lines)


func _refresh_mode() -> void:
	if arm_mode_button == null:
		return
	_updating = true
	arm_mode_button.button_pressed = _pilot.arm_mode
	_updating = false
	if _visual.arm_visual != null:
		_visual.arm_visual.target_visible = _pilot.arm_mode


func _on_slider_changed(value: float, index: int) -> void:
	if _updating:
		return
	_vehicle.manipulator.set_joint_target_degrees(index, value)


func _on_go_pressed() -> void:
	var arm := _vehicle.manipulator
	var offset := Vector3(move_fields["starboard"].value, move_fields["up"].value, -move_fields["forward"].value)
	arm.command_tool(arm.mount_position + offset, move_fields["pitch"].value, arm.tool_target_roll, true)
	refresh()
