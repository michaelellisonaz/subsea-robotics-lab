## Keyboard bindings, registered in code so the full control scheme is in one
## readable place (and project.godot stays small). Physical key codes are used,
## so the layout works the same on non-QWERTY keyboards.
##
## Pilot and free-camera actions share keys (W, A, S, D ...); only one set is
## read at a time, depending on the view (see ViewController).
class_name InputBindings
extends RefCounted

const KEY_BINDINGS := {
	# Free camera
	"camera_forward": [KEY_W],
	"camera_back": [KEY_S],
	"camera_left": [KEY_A],
	"camera_right": [KEY_D],
	"camera_up": [KEY_E],
	"camera_down": [KEY_Q],
	"camera_fast": [KEY_SHIFT],
	# Camera orbit / zoom (all views except onboard)
	"camera_orbit_left": [KEY_LEFT],
	"camera_orbit_right": [KEY_RIGHT],
	"camera_orbit_up": [KEY_UP],
	"camera_orbit_down": [KEY_DOWN],
	"camera_zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"camera_zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	# Views
	"view_reset": [KEY_HOME],
	"view_cycle": [KEY_V],
	"view_toggle_free": [KEY_TAB],
	# Vehicle pilot
	"pilot_forward": [KEY_W],
	"pilot_reverse": [KEY_S],
	"pilot_left": [KEY_A],
	"pilot_right": [KEY_D],
	"pilot_ascend": [KEY_SPACE],
	"pilot_descend": [KEY_CTRL],
	"pilot_yaw_left": [KEY_Q],
	"pilot_yaw_right": [KEY_E],
	"pilot_pitch_up": [KEY_R],
	"pilot_pitch_down": [KEY_F],
	"pilot_roll_port": [KEY_Z],
	"pilot_roll_starboard": [KEY_C],
	"pilot_full_power": [KEY_SHIFT],
	"pilot_lights": [KEY_L],
	"aid_depth_hold": [KEY_J],
	"aid_heading_hold": [KEY_K],
	"aid_position_hold": [KEY_B],
	"aid_attitude_hold": [KEY_T],
	# Manipulator
	"arm_mode": [KEY_M],
	"arm_gripper": [KEY_G],
	"arm_stow": [KEY_X],
	"arm_next_tool": [KEY_N],
	# Simulation
	"sim_toggle_run": [KEY_P],
	"sim_step": [KEY_PERIOD],
	"sim_reset": [KEY_BACKSPACE],
	"ui_toggle_panels": [KEY_H, KEY_F1],
}


## Registers all actions once; safe to call repeatedly.
static func ensure_registered() -> void:
	for action: String in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
