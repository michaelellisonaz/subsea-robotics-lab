## Orbit camera for exploring the environment.
##
## The camera orbits a focus point. Input changes the *target* values (focus,
## heading, elevation, distance) immediately; the visible camera eases toward
## them. The camera is always kept inside the water column (below the sea
## surface and above the seabed) and inside the simulation domain.
##
## Mouse:     left-drag orbit · right/middle-drag pan · wheel zoom
## Keyboard:  W/A/S/D move focus · Q/E focus down/up (free camera only)
##            arrows orbit · +/- zoom · Shift faster
##
## Follow mode (used by the vehicle views): the focus locks onto a target
## supplied as a Callable, and optionally the heading turns with the target's
## heading (chase view). View switching and the reset key live in
## ViewController.
##
## Angles: heading is the compass bearing the camera looks toward (0 = North,
## 90 = East); elevation is the view pitch (negative = looking down).
class_name OrbitCamera
extends Node3D

const PRESETS := {
	"default": {"heading": 35.0, "elevation": -28.0, "distance": 14.0},
	"top": {"heading": 0.0, "elevation": -89.0, "distance": 18.0},
	"north": {"heading": 0.0, "elevation": -12.0, "distance": 16.0},
	"west": {"heading": 270.0, "elevation": -12.0, "distance": 16.0},
}
const MIN_DISTANCE := 1.0
const MAX_DISTANCE := 250.0
const MIN_ELEVATION := -89.0
const MAX_ELEVATION := 75.0
## Default focus height above the seabed reference level, m.
const DEFAULT_FOCUS_HEIGHT := 1.0
const SURFACE_MARGIN := 0.3
const SEABED_MARGIN := 0.4
const FOCUS_SEABED_MARGIN := 0.2
const FOCUS_SURFACE_MARGIN := 0.5
const DOMAIN_MARGIN := 5.0
const ZOOM_STEP := 1.12
## Keyboard orbit rate, degrees per second.
const KEY_ORBIT_SPEED := 75.0
const FAST_MULTIPLIER := 3.0

## Degrees of rotation per pixel of mouse drag.
@export var orbit_sensitivity: float = 0.25
## Higher = snappier easing toward the target view.
@export var smoothing: float = 14.0

## Target focus point (world frame).
var focus: Vector3 = Vector3.ZERO
## Target heading in degrees (kept unwrapped so easing never spins the long way).
var heading: float = 35.0
var elevation: float = -28.0
var distance: float = 14.0

var _current_focus: Vector3 = Vector3.ZERO
var _current_heading: float = 35.0
var _current_elevation: float = -28.0
var _current_distance: float = 14.0
var _world: WorldModel
var _seabed_reference_y: float = 0.0
var _orbit_drag: bool = false
var _pan_drag: bool = false

## When valid, returns the world point the focus follows each frame.
var follow_target: Callable = Callable()
## When valid, returns a heading (degrees) the orbit heading turns with.
var follow_heading: Callable = Callable()
## WASD/QE move the focus only when enabled (free camera).
var keyboard_movement_enabled: bool = true
## When false the camera ignores mouse and keyboard input (onboard view).
var input_enabled: bool = true
var _last_followed_heading: float = NAN

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	InputBindings.ensure_registered()


func setup(world: WorldModel) -> void:
	_world = world
	_seabed_reference_y = world.seabed_reference_y()
	reset_view(true)


func default_focus() -> Vector3:
	if _world == null:
		return Vector3.ZERO
	return Vector3(0.0, _world.seabed_reference_y() + DEFAULT_FOCUS_HEIGHT, 0.0)


func reset_view(immediate: bool = false) -> void:
	apply_preset("default", immediate)


## Applies a named view ("default", "top", "north", "west") around the site origin.
func apply_preset(preset_name: String, immediate: bool = false) -> void:
	var preset: Dictionary = PRESETS.get(preset_name, PRESETS["default"])
	focus = default_focus()
	set_heading(preset["heading"])
	set_elevation(preset["elevation"])
	set_distance(preset["distance"])
	_clamp_targets()
	if immediate:
		snap()


## Jumps the visible camera to the target view without easing.
func snap() -> void:
	_current_focus = focus
	_current_heading = heading
	_current_elevation = elevation
	_current_distance = distance
	_update_transform()


func set_heading(degrees: float) -> void:
	heading = _current_heading + wrapf(degrees - _current_heading, -180.0, 180.0)


func set_elevation(degrees: float) -> void:
	elevation = clampf(degrees, MIN_ELEVATION, MAX_ELEVATION)


func set_distance(metres: float) -> void:
	distance = clampf(metres, MIN_DISTANCE, MAX_DISTANCE)


func set_focus(world_position: Vector3) -> void:
	focus = world_position
	_clamp_targets()


func set_focus_enu_depth(east: float, north: float, depth: float) -> void:
	set_focus(Vector3(east, -depth, -north))


func orbit(delta_heading: float, delta_elevation: float) -> void:
	heading += delta_heading
	set_elevation(elevation + delta_elevation)


func zoom_by(factor: float) -> void:
	set_distance(distance * factor)


## Pans the focus so the scene follows the mouse by the given pixel offset.
func pan_pixels(delta_px: Vector2) -> void:
	var viewport_height := get_viewport().get_visible_rect().size.y
	if viewport_height <= 1.0:
		viewport_height = 900.0
	var metres_per_pixel := 2.0 * _current_distance * tan(deg_to_rad(camera.fov) * 0.5) / viewport_height
	var cam_basis := camera.global_transform.basis
	focus += (-cam_basis.x * delta_px.x + cam_basis.y * delta_px.y) * metres_per_pixel
	_clamp_targets()


## Moves the focus relative to the current heading (forward/right) and up, m.
func move_focus_local(forward: float, right: float, up: float) -> void:
	var h := deg_to_rad(heading)
	var forward_dir := Vector3(sin(h), 0.0, -cos(h))
	var right_dir := Vector3(cos(h), 0.0, sin(h))
	focus += forward_dir * forward + right_dir * right + Vector3.UP * up
	_clamp_targets()


## Heading wrapped to 0-360 degrees.
func get_heading() -> float:
	return fposmod(heading, 360.0)


## Target focus as (east, north, depth).
func get_focus_enu_depth() -> Vector3:
	return Vector3(focus.x, -focus.z, -focus.y)


func get_camera_position() -> Vector3:
	return camera.global_position


## Keeps the view at the same height above the seabed when the water depth changes.
func on_seabed_moved() -> void:
	if _world == null:
		return
	var new_reference := _world.seabed_reference_y()
	var dy := new_reference - _seabed_reference_y
	_seabed_reference_y = new_reference
	focus.y += dy
	_current_focus.y += dy
	_clamp_targets()
	_current_focus = _world.clamp_to_water(_current_focus, FOCUS_SEABED_MARGIN, FOCUS_SURFACE_MARGIN)
	_update_transform()


func is_dragging() -> bool:
	return _orbit_drag or _pan_drag


## Locks the focus onto a target (and optionally the heading onto its heading).
func set_follow(target: Callable, heading_source: Callable = Callable()) -> void:
	follow_target = target
	follow_heading = heading_source
	_last_followed_heading = NAN
	if target.is_valid():
		focus = target.call()
		_current_focus = focus


func clear_follow() -> void:
	follow_target = Callable()
	follow_heading = Callable()
	_last_followed_heading = NAN


func is_following() -> bool:
	return follow_target.is_valid()


func _process(delta: float) -> void:
	if _world == null:
		return
	if input_enabled:
		_handle_keyboard(delta)
	_apply_follow()
	_clamp_targets()
	var t := 1.0 - exp(-smoothing * delta)
	_current_focus = _current_focus.lerp(focus, t)
	_current_heading = lerpf(_current_heading, heading, t)
	_current_elevation = lerpf(_current_elevation, elevation, t)
	_current_distance = lerpf(_current_distance, distance, t)
	_update_transform()


func _apply_follow() -> void:
	if follow_heading.is_valid():
		var followed: float = follow_heading.call()
		if not is_nan(_last_followed_heading):
			var turn := wrapf(followed - _last_followed_heading, -180.0, 180.0)
			heading += turn
			_current_heading += turn
		_last_followed_heading = followed
	if follow_target.is_valid():
		# Lock exactly onto the (already smoothly interpolated) target.
		focus = follow_target.call()
		_current_focus = focus


# Drags start only in the 3D view (unhandled input, after the UI had its turn).
func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_orbit_drag = true
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_pan_drag = true
			MOUSE_BUTTON_WHEEL_UP:
				zoom_by(1.0 / ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_by(ZOOM_STEP)
			_:
				return
		get_viewport().gui_release_focus()
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		zoom_by(1.0 / event.factor)
		get_viewport().set_input_as_handled()


# Drags that started in the 3D view keep working when the cursor passes over a
# panel, and always end on release, wherever the button is released.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_orbit_drag = false
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_drag = false
	elif event is InputEventMouseMotion and (_orbit_drag or _pan_drag):
		if _orbit_drag:
			orbit(event.relative.x * orbit_sensitivity, -event.relative.y * orbit_sensitivity)
		else:
			pan_pixels(event.relative)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_orbit_drag = false
		_pan_drag = false


func _handle_keyboard(delta: float) -> void:
	if _keyboard_blocked():
		return
	var fast := FAST_MULTIPLIER if Input.is_action_pressed("camera_fast") else 1.0
	var move := Vector3.ZERO
	if keyboard_movement_enabled:
		move = Vector3(
			Input.get_axis("camera_left", "camera_right"),
			Input.get_axis("camera_down", "camera_up"),
			Input.get_axis("camera_back", "camera_forward"))
	if move != Vector3.ZERO:
		var speed := maxf(2.0, distance * 0.8) * fast
		move = move.normalized() * speed * delta
		move_focus_local(move.z, move.x, move.y)
	var orbit_input := Vector2(
		Input.get_axis("camera_orbit_left", "camera_orbit_right"),
		Input.get_axis("camera_orbit_down", "camera_orbit_up"))
	if orbit_input != Vector2.ZERO:
		var rate := KEY_ORBIT_SPEED * fast * delta
		# Up arrow raises the camera over the focus (looks further down).
		orbit(orbit_input.x * rate, -orbit_input.y * rate)
	var zoom_input := Input.get_axis("camera_zoom_in", "camera_zoom_out")
	if zoom_input != 0.0:
		zoom_by(pow(2.0, zoom_input * fast * delta))


# Do not move the camera while the user is typing into a field.
func _keyboard_blocked() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _clamp_targets() -> void:
	elevation = clampf(elevation, MIN_ELEVATION, MAX_ELEVATION)
	distance = clampf(distance, MIN_DISTANCE, MAX_DISTANCE)
	if _world != null:
		focus = _world.clamp_to_bounds(focus, DOMAIN_MARGIN)
		focus = _world.clamp_to_water(focus, FOCUS_SEABED_MARGIN, FOCUS_SURFACE_MARGIN)


func _update_transform() -> void:
	var h := deg_to_rad(_current_heading)
	var e := deg_to_rad(_current_elevation)
	var view_dir := Vector3(sin(h) * cos(e), sin(e), -cos(h) * cos(e))
	var camera_position := _current_focus - view_dir * _current_distance
	if _world != null:
		camera_position = _world.clamp_to_water(camera_position, SEABED_MARGIN, SURFACE_MARGIN)
	var to_focus := _current_focus - camera_position
	if to_focus.length_squared() < 1e-4:
		to_focus = view_dir
	camera.global_transform = Transform3D(Basis.looking_at(to_focus, Vector3.UP), camera_position)
