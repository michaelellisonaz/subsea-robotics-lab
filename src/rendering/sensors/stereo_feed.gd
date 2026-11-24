## Renders the stereo camera pair into two off-screen viewports when the
## stereo sensor is enabled (no rendering cost when it is disabled). The
## cameras sit ±baseline/2 either side of the sensor mount and look forward.
## The dashboard displays the viewport textures.
class_name StereoFeed
extends Node

var vehicle: RovVehicle
var visual: RovVisual
var left_viewport: SubViewport
var right_viewport: SubViewport
var _left_camera: Camera3D
var _right_camera: Camera3D


func _ready() -> void:
	left_viewport = _make_viewport("StereoLeft")
	right_viewport = _make_viewport("StereoRight")
	_left_camera = left_viewport.get_child(0)
	_right_camera = right_viewport.get_child(0)


func bind(p_vehicle: RovVehicle, p_visual: RovVisual) -> void:
	vehicle = p_vehicle
	visual = p_visual


func is_active() -> bool:
	var sensor := _sensor()
	return sensor != null and sensor.enabled


func left_texture() -> Texture2D:
	return left_viewport.get_texture()


func right_texture() -> Texture2D:
	return right_viewport.get_texture()


func _process(_delta: float) -> void:
	var sensor := _sensor()
	var active := sensor != null and sensor.enabled
	var mode := SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	left_viewport.render_target_update_mode = mode
	right_viewport.render_target_update_mode = mode
	if not active:
		return
	var pose := visual.global_transform
	var half_baseline: float = sensor.get_param("baseline") * 0.5
	for pair in [[_left_camera, -half_baseline], [_right_camera, half_baseline]]:
		var camera: Camera3D = pair[0]
		camera.fov = sensor.get_param("fov")
		camera.global_transform = Transform3D(pose.basis * sensor.mount_basis,
			pose * (sensor.mount_position + Vector3(pair[1], 0.0, 0.0)))


func _sensor() -> Sensor:
	return vehicle.sensors.get_sensor("Stereo camera") if vehicle != null else null


func _make_viewport(viewport_name: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = Vector2i(StereoCameraSensor.IMAGE_WIDTH, StereoCameraSensor.IMAGE_HEIGHT)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var camera := Camera3D.new()
	camera.near = 0.03
	camera.far = 400.0
	camera.current = true
	viewport.add_child(camera)
	add_child(viewport)
	return viewport
