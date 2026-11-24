## Inspection camera: renders what the vehicle's front camera sees, tilted
## down for pipeline inspection, into an off-screen image and runs the
## DefectDetector on it twice per simulated second while a survey (or the
## operator) asks for it. No rendering cost otherwise.
##
## The image is rendered from the vehicle's TRUE pose (it is the physical
## camera); detections are projected with the ESTIMATED pose from the
## navigation filter, so navigation error shows up in where defects are
## reported. Needs a GPU: in headless runs the image is empty and nothing is
## detected.
class_name InspectionCamera
extends Node

const WIDTH := 320
const HEIGHT := 240
const FOV := 60.0  # degrees, vertical
const TILT := -50.0  # degrees, down from the vehicle's forward axis
const INTERVAL := 0.5  # simulated seconds between analysed frames

var vehicle: RovVehicle
var visual: RovVisual
var engine: SimulationEngine
var viewport: SubViewport
## Operator switch: run the detector even without a survey.
var manual: bool = false
var last_result: Dictionary = {}

var _camera: Camera3D
var _last_time: float = -INF


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "InspectionView"
	viewport.size = Vector2i(WIDTH, HEIGHT)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_camera = Camera3D.new()
	_camera.near = 0.05
	_camera.far = 60.0
	_camera.fov = FOV
	_camera.current = true
	viewport.add_child(_camera)
	add_child(viewport)


func bind(p_engine: SimulationEngine, p_vehicle: RovVehicle, p_visual: RovVisual) -> void:
	engine = p_engine
	vehicle = p_vehicle
	visual = p_visual
	engine.simulation_reset.connect(func() -> void:
		_last_time = -INF
		last_result = {})


func is_active() -> bool:
	return vehicle != null and (manual or vehicle.autonomy.vision_active)


func texture() -> Texture2D:
	return viewport.get_texture()


## Camera mounting relative to the vehicle CG (body axes).
func mount_transform() -> Transform3D:
	var sensor := vehicle.sensors.get_sensor("Camera")
	var position: Vector3 = sensor.mount_position if sensor != null else Vector3(0.0, 0.0, -0.5)
	return Transform3D(Basis(Vector3.RIGHT, deg_to_rad(TILT)), position)


func _process(_delta: float) -> void:
	var active := is_active()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		return
	_camera.global_transform = visual.global_transform * mount_transform()
	var now := engine.clock.sim_time
	if now - _last_time < INTERVAL or engine.state != SimulationEngine.State.RUNNING or DisplayServer.get_name() == "headless":
		return
	_last_time = now
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return
	last_result = DefectDetector.analyze(image)
	var nav := vehicle.autonomy.nav
	if not nav.initialized:
		return
	var estimated := Transform3D(nav.world_basis(), nav.world_position()) * mount_transform()
	vehicle.autonomy.add_vision_frame(last_result, estimated, FOV, now)
