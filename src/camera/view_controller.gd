## Chooses what the user looks through and what the keyboard controls.
##
##   CHASE    orbit camera follows the vehicle and turns with its heading
##   ORBIT    orbit camera follows the vehicle position only
##   ONBOARD  the vehicle's front camera (with the onboard HUD)
##   FREE     orbit camera detached; WASD/QE move the camera, not the vehicle
##
## In the three vehicle views the keyboard pilots the vehicle. Tab toggles
## between the last vehicle view and the free camera; V cycles vehicle views;
## Home resets the current view.
class_name ViewController
extends Node

enum ViewMode { CHASE, ORBIT, ONBOARD, FREE }
const MODE_NAMES := ["Chase", "Orbit", "Onboard camera", "Free camera"]
const CHASE_ELEVATION := -16.0
const CHASE_DISTANCE_FACTOR := 4.0
const CHASE_MIN_DISTANCE := 3.5

signal view_mode_changed(mode: int)
signal active_camera_changed(camera: Camera3D)

var mode: int = ViewMode.CHASE
var orbit_camera: OrbitCamera
var vehicle_visual: RovVisual
var vehicle: RovVehicle

var _last_vehicle_mode: int = ViewMode.CHASE


func _ready() -> void:
	InputBindings.ensure_registered()


func setup(p_orbit_camera: OrbitCamera, p_vehicle_visual: RovVisual, p_vehicle: RovVehicle) -> void:
	orbit_camera = p_orbit_camera
	vehicle_visual = p_vehicle_visual
	vehicle = p_vehicle
	set_mode(ViewMode.CHASE, true)
	frame_vehicle()
	orbit_camera.snap()


func is_piloting() -> bool:
	return mode != ViewMode.FREE


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func active_camera() -> Camera3D:
	return vehicle_visual.onboard_camera if mode == ViewMode.ONBOARD else orbit_camera.camera


func set_mode(new_mode: int, force: bool = false) -> void:
	if new_mode == mode and not force:
		return
	var previous := mode
	mode = new_mode
	match mode:
		ViewMode.CHASE:
			orbit_camera.set_follow(vehicle_focus, vehicle_heading)
		ViewMode.ORBIT:
			orbit_camera.set_follow(vehicle_focus)
		ViewMode.ONBOARD:
			orbit_camera.set_follow(vehicle_focus)
		ViewMode.FREE:
			orbit_camera.clear_follow()
	if previous == ViewMode.FREE and mode == ViewMode.CHASE:
		frame_vehicle()
	orbit_camera.keyboard_movement_enabled = mode == ViewMode.FREE
	orbit_camera.input_enabled = mode != ViewMode.ONBOARD
	vehicle_visual.set_onboard_view(mode == ViewMode.ONBOARD)
	if mode == ViewMode.ONBOARD:
		vehicle_visual.onboard_camera.make_current()
	else:
		orbit_camera.camera.make_current()
	if mode != ViewMode.FREE:
		_last_vehicle_mode = mode
	view_mode_changed.emit(mode)
	active_camera_changed.emit(active_camera())


## V: Chase -> Orbit -> Onboard -> Chase (from free camera: back to the last vehicle view).
func cycle_vehicle_view() -> void:
	match mode:
		ViewMode.CHASE:
			set_mode(ViewMode.ORBIT)
		ViewMode.ORBIT:
			set_mode(ViewMode.ONBOARD)
		ViewMode.ONBOARD:
			set_mode(ViewMode.CHASE)
		ViewMode.FREE:
			set_mode(_last_vehicle_mode)


## Tab: toggle between the free camera and the last vehicle view.
func toggle_free_camera() -> void:
	set_mode(_last_vehicle_mode if mode == ViewMode.FREE else ViewMode.FREE)


func reset_view() -> void:
	if mode == ViewMode.FREE:
		orbit_camera.reset_view()
	else:
		frame_vehicle()


## Places the orbit camera behind and above the vehicle.
func frame_vehicle() -> void:
	orbit_camera.set_heading(vehicle.heading_degrees())
	orbit_camera.set_elevation(CHASE_ELEVATION)
	orbit_camera.set_distance(maxf(CHASE_MIN_DISTANCE, vehicle.config.length * CHASE_DISTANCE_FACTOR))


func vehicle_focus() -> Vector3:
	return vehicle_visual.global_position


func vehicle_heading() -> float:
	return WorldFrame.heading_from_direction(vehicle_visual.global_transform.basis * Vector3.FORWARD)


func _unhandled_input(event: InputEvent) -> void:
	if orbit_camera == null or not (event is InputEventKey):
		return
	if event.is_action_pressed("view_toggle_free"):
		toggle_free_camera()
	elif event.is_action_pressed("view_cycle"):
		cycle_vehicle_view()
	elif event.is_action_pressed("view_reset"):
		reset_view()
	else:
		return
	get_viewport().set_input_as_handled()
