## Maps the pilot keys to the vehicle's normalised axis commands.
##
##   W / S  surge      A / D  sway       Space / Ctrl  heave (up / down)
##   Q / E  yaw        R / F  pitch      Z / C  roll (port / starboard down)
##   Shift  full power (otherwise FINE_CONTROL_SCALE of capability)
##   L      work lights on / off
##   J / K / B / T  depth / heading / position / attitude hold (pilot aids)
##   G      gripper open / close, or the mounted tool's action
##   M      arm control on / off       N  next tool (arm control)
##
## ARM CONTROL (M): the same keys move the manipulator tool instead of the
## vehicle, in vehicle axes: W/S forward/back, A/D port/starboard,
## Space/Ctrl up/down, R/F tool pitch, Q/E wrist roll, X stow, Shift faster.
## Entering arm control engages depth, heading, position and attitude hold
## so the vehicle keeps station and stays level while the arm works (sensor
## readings permitting).
##
## Commands are sampled every rendered frame; the vehicle applies the latest
## command at each simulation step.
class_name PilotInput
extends Node

## Command magnitude without Shift (fraction of each axis' capability).
const FINE_CONTROL_SCALE := 0.4
## Tool jog speed in arm control, m/s (Shift: x2.5), and angle rate, °/s.
const ARM_JOG_SPEED := 0.12
const ARM_ANGLE_RATE := 30.0

signal arm_mode_changed(active: bool)

var vehicle: RovVehicle
## Pilot keys are read only when enabled (vehicle views).
var enabled: bool = true
## True while the keyboard controls the manipulator instead of the vehicle.
var arm_mode: bool = false


## Switches arm control on or off. Returns false if no arm is installed.
func set_arm_mode(active: bool) -> bool:
	if active and (vehicle == null or not vehicle.manipulator.is_installed()):
		return false
	if active == arm_mode:
		return true
	arm_mode = active
	if active:
		var now := vehicle.last_update_time
		if not vehicle.aids.depth_hold:
			vehicle.aids.set_depth_hold(true, vehicle, now)
		if not vehicle.aids.heading_hold:
			vehicle.aids.set_heading_hold(true, vehicle, now)
		if not vehicle.aids.position_hold:
			vehicle.aids.set_position_hold(true, vehicle, now)
		if not vehicle.aids.attitude_hold:
			vehicle.aids.set_attitude_hold(true, vehicle, now)
	arm_mode_changed.emit(active)
	return true


func _ready() -> void:
	InputBindings.ensure_registered()


func _process(delta: float) -> void:
	if vehicle == null:
		return
	if not enabled or _keyboard_blocked():
		vehicle.clear_pilot_commands()
		return
	if arm_mode:
		vehicle.clear_pilot_commands()
		_jog_arm(delta)
		return
	var scale := 1.0 if Input.is_action_pressed("pilot_full_power") else FINE_CONTROL_SCALE
	var commands := PackedFloat64Array([
		Input.get_axis("pilot_reverse", "pilot_forward"),
		Input.get_axis("pilot_left", "pilot_right"),
		Input.get_axis("pilot_descend", "pilot_ascend"),
		Input.get_axis("pilot_roll_port", "pilot_roll_starboard"),
		Input.get_axis("pilot_pitch_down", "pilot_pitch_up"),
		Input.get_axis("pilot_yaw_left", "pilot_yaw_right"),
	])
	for i in commands.size():
		commands[i] *= scale
	vehicle.set_pilot_commands(commands)


func _jog_arm(delta: float) -> void:
	var fast := 2.5 if Input.is_action_pressed("pilot_full_power") else 1.0
	var forward := Input.get_axis("pilot_reverse", "pilot_forward")
	var starboard := Input.get_axis("pilot_left", "pilot_right")
	var up := Input.get_axis("pilot_descend", "pilot_ascend")
	var pitch := Input.get_axis("pilot_pitch_down", "pilot_pitch_up")
	var roll := Input.get_axis("pilot_yaw_left", "pilot_yaw_right")
	if forward == 0.0 and starboard == 0.0 and up == 0.0 and pitch == 0.0 and roll == 0.0:
		return
	var step := ARM_JOG_SPEED * fast * delta
	vehicle.manipulator.jog_tool(Vector3(starboard, up, -forward) * step,
		pitch * ARM_ANGLE_RATE * fast * delta, roll * ARM_ANGLE_RATE * 2.0 * fast * delta)


func toggle_lights() -> void:
	if vehicle != null:
		vehicle.lights_on = not vehicle.lights_on


func _unhandled_input(event: InputEvent) -> void:
	if vehicle == null or not enabled or not (event is InputEventKey):
		return
	if event.is_action_pressed("pilot_lights"):
		toggle_lights()
	elif event.is_action_pressed("aid_depth_hold"):
		vehicle.toggle_depth_hold()
	elif event.is_action_pressed("aid_heading_hold"):
		vehicle.toggle_heading_hold()
	elif event.is_action_pressed("aid_position_hold"):
		vehicle.toggle_position_hold()
	elif event.is_action_pressed("aid_attitude_hold"):
		vehicle.toggle_attitude_hold()
	elif event.is_action_pressed("arm_mode"):
		set_arm_mode(not arm_mode)
	elif event.is_action_pressed("arm_gripper"):
		vehicle.manipulator.tool_action(vehicle.last_update_time)
	elif event.is_action_pressed("arm_next_tool") and arm_mode:
		vehicle.manipulator.request_tool(vehicle.manipulator.next_tool())
	elif event.is_action_pressed("arm_stow") and arm_mode:
		vehicle.manipulator.stow()
	else:
		return
	get_viewport().set_input_as_handled()


func _keyboard_blocked() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
