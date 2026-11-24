## Procedural 3D model of an inspection-class ROV, driven by a RovVehicle.
##
## The model is rebuilt from the vehicle's VehicleConfig (dimensions, thruster
## layout) whenever a configuration is applied, and every frame it copies the
## vehicle's pose (interpolated between simulation steps), spins the propellers
## in proportion to thrust and switches the work lights. It holds no
## simulation state.
##
## Engineering overlays (toggle): CG and CB markers and per-thruster force
## arrows (length proportional to thrust).
##
## Sensor housings are placed at each sensor's mounting point (Stage 3); the
## onboard camera takes its field of view and low-light gain from the
## "Camera" sensor. The tether termination is purely visual.
class_name RovVisual
extends Node3D

const PROPELLER_MAX_SPEED := 45.0  # rad/s at full thrust (visual only)
const ARROW_MAX_LENGTH := 0.45  # m at full thrust
const DUCT_RADIUS := 0.06

var vehicle: RovVehicle
## Onboard pilot camera at the front camera dome (persistent across rebuilds).
var onboard_camera: Camera3D
var markers_visible: bool = true
## True while looking through the onboard camera: overlays are hidden so they
## never block the pilot's view.
var onboard_view: bool = false

var _alpha_source: Callable
var _time_flow: float = 0.0
var _model: Node3D
var _markers: Node3D
## Manipulator model (body frame, follows the vehicle pose).
var arm_visual: ManipulatorVisual
var _rotors: Array[Node3D] = []
var _arrows: Array[Node3D] = []
var _spot_lights: Array[SpotLight3D] = []
var _lens_material: StandardMaterial3D
var _materials: Dictionary = {}


func _ready() -> void:
	onboard_camera = Camera3D.new()
	onboard_camera.name = "OnboardCamera"
	onboard_camera.fov = 70.0
	onboard_camera.near = 0.03
	onboard_camera.far = 600.0
	add_child(onboard_camera)


## Connects the visual to a vehicle. alpha_source returns the interpolation
## fraction between the last two simulation steps (0..1).
func bind(p_vehicle: RovVehicle, alpha_source: Callable) -> void:
	vehicle = p_vehicle
	_alpha_source = alpha_source
	vehicle.configuration_applied.connect(_rebuild)
	_rebuild()
	_sync_pose()


## Simulated seconds per real second; propellers freeze at 0 (paused).
func set_time_flow(rate: float) -> void:
	_time_flow = rate


func set_markers_visible(value: bool) -> void:
	markers_visible = value
	if _markers != null:
		_markers.visible = _overlays_shown()
	for arrow in _arrows:
		arrow.visible = _overlays_shown()


func set_onboard_view(active: bool) -> void:
	onboard_view = active
	set_markers_visible(markers_visible)


func _overlays_shown() -> bool:
	return markers_visible and not onboard_view


func _process(delta: float) -> void:
	if vehicle == null:
		return
	_sync_pose()
	for i in mini(_rotors.size(), vehicle.thrusters.size()):
		var fraction := vehicle.thrusters[i].thrust_fraction()
		_rotors[i].rotate_y(fraction * PROPELLER_MAX_SPEED * _time_flow * delta)
		var arrow := _arrows[i]
		var length := absf(fraction) * ARROW_MAX_LENGTH
		arrow.visible = _overlays_shown() and length > 0.01
		if arrow.visible:
			arrow.scale = Vector3(1.0, length * signf(fraction), 1.0)
	for spot in _spot_lights:
		spot.visible = vehicle.lights_on
	_lens_material.emission_energy_multiplier = 4.0 if vehicle.lights_on else 0.0
	_apply_camera_settings()
	if arm_visual != null:
		arm_visual.update_pose()


## Field of view and low-light gain from the camera sensor settings.
func _apply_camera_settings() -> void:
	var camera_sensor := vehicle.sensors.get_sensor("Camera")
	if camera_sensor == null:
		return
	onboard_camera.fov = camera_sensor.get_param("fov")
	if onboard_camera.attributes == null:
		onboard_camera.attributes = CameraAttributesPractical.new()
	onboard_camera.attributes.exposure_multiplier = camera_sensor.get_param("gain") if camera_sensor.enabled else 1.0


func _sync_pose() -> void:
	var alpha: float = _alpha_source.call() if _alpha_source.is_valid() else 1.0
	global_transform = vehicle.get_interpolated_transform(alpha)


# --- Model construction -----------------------------------------------------------

func _rebuild() -> void:
	if _model != null:
		_model.free()
	if _markers != null:
		_markers.free()
	_rotors.clear()
	_arrows.clear()
	_spot_lights.clear()
	_create_materials()
	var cfg := vehicle.config
	_model = Node3D.new()
	_model.name = "Model"
	_model.position = -cfg.cg_geometric()  # body origin is the CG
	add_child(_model)
	_build_frame(cfg)
	_build_buoyancy(cfg)
	_build_housings(cfg)
	_build_lights(cfg)
	_build_thrusters(cfg)
	_build_tether(cfg)
	_build_markers()
	if arm_visual == null:
		arm_visual = ManipulatorVisual.new()
		arm_visual.name = "Manipulator"
		add_child(arm_visual)
	arm_visual.build(vehicle.manipulator)
	onboard_camera.position = cfg.to_body(cfg.camera_position_geometric())
	set_markers_visible(markers_visible)


func _create_materials() -> void:
	_materials = {
		"frame": _material(Color(0.20, 0.21, 0.23), 0.6, 0.45),
		"bumper": _material(Color(0.05, 0.05, 0.05), 0.0, 0.7),
		"foam": _material(Color(0.86, 0.62, 0.08), 0.0, 0.85),
		"housing": _material(Color(0.58, 0.60, 0.63), 0.85, 0.32),
		"housing_dark": _material(Color(0.12, 0.13, 0.14), 0.5, 0.4),
		"glass": _material(Color(0.02, 0.03, 0.04), 0.3, 0.05),
		"duct": _material(Color(0.06, 0.06, 0.07), 0.2, 0.5),
		"propeller": _material(Color(0.72, 0.74, 0.76), 0.8, 0.3),
		"tether": _material(Color(0.95, 0.42, 0.06), 0.0, 0.6),
	}
	_materials["duct"].cull_mode = BaseMaterial3D.CULL_DISABLED
	_lens_material = _material(Color(0.9, 0.9, 0.85), 0.0, 0.2)
	_lens_material.emission_enabled = true
	_lens_material.emission = Color(1.0, 0.96, 0.88)
	_lens_material.emission_energy_multiplier = 4.0


func _build_frame(cfg: VehicleConfig) -> void:
	var l := cfg.length
	var w := cfg.width
	var h := cfg.height
	var rail := 0.04
	var frame: StandardMaterial3D = _materials["frame"]
	var bumper: StandardMaterial3D = _materials["bumper"]
	for sx in [-1.0, 1.0]:
		var x: float = sx * (w * 0.5 - rail * 0.5)
		_box(Vector3(rail, rail * 1.2, l), Vector3(x, -h * 0.5 + rail * 0.6, 0.0), frame)  # skid
		_box(Vector3(rail * 0.8, rail * 0.8, l * 0.96), Vector3(x, -h * 0.5 + h * 0.42, 0.0), frame)  # side rail
		_cylinder(0.018, l * 0.9, Vector3(sx * (w * 0.5 + 0.012), -h * 0.5 + h * 0.26, 0.0), Vector3.BACK, bumper)
		for sz in [-1.0, 1.0]:
			_box(Vector3(rail, h * 0.62, rail), Vector3(x, -h * 0.5 + h * 0.31, sz * (l * 0.5 - rail * 0.5)), frame)
	for z in [-l * 0.5 + rail * 0.5, 0.0, l * 0.5 - rail * 0.5]:
		_box(Vector3(w - rail, rail, rail), Vector3(0.0, -h * 0.5 + rail * 0.6, z), frame)
	for sz in [-1.0, 1.0]:
		_cylinder(0.018, w * 0.9, Vector3(0.0, -h * 0.5 + h * 0.26, sz * (l * 0.5 + 0.012)), Vector3.RIGHT, bumper)


func _build_buoyancy(cfg: VehicleConfig) -> void:
	var foam_height := cfg.height * 0.32
	_box(Vector3(cfg.width, foam_height, cfg.length * 0.94), Vector3(0.0, cfg.height * 0.5 - foam_height * 0.5, 0.0), _materials["foam"])
	for sx in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = "SRL-1"
		label.font_size = 48
		label.pixel_size = 0.003
		label.modulate = Color(0.08, 0.08, 0.08)
		label.outline_size = 0
		label.position = Vector3(sx * (cfg.width * 0.5 + 0.002), cfg.height * 0.5 - foam_height * 0.5, 0.0)
		label.rotation_degrees = Vector3(0.0, 90.0 * sx, 0.0)
		_model.add_child(label)


func _build_housings(cfg: VehicleConfig) -> void:
	var l := cfg.length
	var h := cfg.height
	var radius := minf(cfg.width, h) * 0.16
	var y := -h * 0.06
	# Main electronics pressure housing with end caps.
	_cylinder(radius, l * 0.55, Vector3(0.0, y, l * 0.05), Vector3.BACK, _materials["housing"])
	for z in [l * 0.05 - l * 0.275, l * 0.05 + l * 0.275]:
		_cylinder(radius * 1.08, 0.025, Vector3(0.0, y, z), Vector3.BACK, _materials["housing_dark"])
	# Front camera housing with dark glass dome (the onboard camera looks out of it).
	var camera_radius := 0.06
	_cylinder(camera_radius, l * 0.235, Vector3(0.0, y, -l * 0.3425), Vector3.BACK, _materials["housing"])
	_sphere(camera_radius * 0.98, Vector3(0.0, y, -l * 0.46), _materials["glass"])
	_build_sensor_housings(cfg)


## Housings at the sensors' mounting points (body axes -> geometric frame).
func _build_sensor_housings(cfg: VehicleConfig) -> void:
	var dark: StandardMaterial3D = _materials["housing_dark"]
	var cg := cfg.cg_geometric()
	for sensor in vehicle.sensors.sensors:
		var p := sensor.mount_position + cg
		match sensor.sensor_type:
			"dvl":
				_cylinder(0.055, 0.05, p, Vector3.UP, dark)
				_cylinder(0.04, 0.01, p + Vector3(0.0, -0.028, 0.0), Vector3.UP, _materials["glass"])
			"altimeter":
				_cylinder(0.025, 0.07, p, Vector3.UP, dark)
			"usbl":
				_cylinder(0.03, 0.09, p, Vector3.UP, _materials["housing"])
				_sphere(0.032, p + Vector3(0.0, 0.05, 0.0), dark)
			"imaging_sonar":
				_cylinder(0.045, 0.1, p, Vector3.FORWARD, dark)
				_box(Vector3(0.11, 0.05, 0.02), p + Vector3(0.0, 0.0, -0.055), _materials["glass"])
			"multibeam":
				_box(Vector3(0.18, 0.04, 0.06), p, dark)
			"stereo_camera":
				var baseline: float = sensor.get_param("baseline")
				_box(Vector3(baseline + 0.08, 0.025, 0.03), p + Vector3(0.0, 0.0, 0.02), _materials["frame"])
				for sx in [-0.5, 0.5]:
					_cylinder(0.025, 0.06, p + Vector3(sx * baseline, 0.0, 0.0), Vector3.BACK, dark)
					_sphere(0.02, p + Vector3(sx * baseline, 0.0, -0.03), _materials["glass"])


func _build_lights(cfg: VehicleConfig) -> void:
	for sx in [-1.0, 1.0]:
		var p := Vector3(sx * cfg.width * 0.3, cfg.height * 0.08, -cfg.length * 0.5 + 0.03)
		_cylinder(0.038, 0.08, p, Vector3.BACK, _materials["housing_dark"])
		_cylinder(0.032, 0.01, p + Vector3(0.0, 0.0, -0.042), Vector3.BACK, _lens_material)
		_box(Vector3(0.02, 0.06, 0.03), p + Vector3(0.0, -0.05, 0.0), _materials["frame"])
		var spot := SpotLight3D.new()
		spot.position = p + Vector3(0.0, 0.0, -0.06)
		spot.rotation_degrees = Vector3(-8.0, -6.0 * sx, 0.0)
		spot.spot_range = 14.0
		spot.spot_angle = 38.0
		spot.light_energy = 6.0
		spot.light_color = Color(1.0, 0.96, 0.9)
		spot.shadow_enabled = false
		_model.add_child(spot)
		_spot_lights.append(spot)


func _build_thrusters(cfg: VehicleConfig) -> void:
	var specs := cfg.thruster_specs()
	var arrow_material := _material(Color(1.0, 0.55, 0.1), 0.0, 0.5)
	arrow_material.emission_enabled = true
	arrow_material.emission = Color(1.0, 0.55, 0.1)
	arrow_material.emission_energy_multiplier = 1.0
	arrow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for spec in specs:
		var mount := Node3D.new()
		mount.position = spec["position"]
		mount.basis = _basis_up_to(spec["direction"])
		_model.add_child(mount)
		# Duct (open tube), motor can, hub and support struts.
		var duct := CylinderMesh.new()
		duct.top_radius = DUCT_RADIUS
		duct.bottom_radius = DUCT_RADIUS
		duct.height = 0.075
		duct.cap_top = false
		duct.cap_bottom = false
		duct.radial_segments = 24
		_mesh(duct, Vector3.ZERO, Basis.IDENTITY, _materials["duct"], mount)
		_cylinder(0.03, 0.06, Vector3(0.0, -0.06, 0.0), Vector3.UP, _materials["duct"], mount)
		_box(Vector3(DUCT_RADIUS * 2.0, 0.006, 0.012), Vector3(0.0, -0.03, 0.0), _materials["duct"], mount)
		var rotor := Node3D.new()
		mount.add_child(rotor)
		_cylinder(0.022, 0.05, Vector3.ZERO, Vector3.UP, _materials["propeller"], rotor)
		for k in 3:
			var blade := MeshInstance3D.new()
			var blade_mesh := BoxMesh.new()
			blade_mesh.size = Vector3(DUCT_RADIUS * 0.8, 0.006, 0.028)
			blade.mesh = blade_mesh
			blade.material_override = _materials["propeller"]
			var angle := TAU * k / 3.0
			blade.basis = Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, deg_to_rad(28.0))
			blade.position = Basis(Vector3.UP, angle) * Vector3(DUCT_RADIUS * 0.45, 0.0, 0.0)
			rotor.add_child(blade)
		_rotors.append(rotor)
		# Force arrow (engineering overlay): +Y of the mount = force on the vehicle.
		var arrow := Node3D.new()
		mount.add_child(arrow)
		_cylinder(0.008, 0.85, Vector3(0.0, 0.425, 0.0), Vector3.UP, arrow_material, arrow)
		var head := CylinderMesh.new()
		head.top_radius = 0.0
		head.bottom_radius = 0.025
		head.height = 0.15
		_mesh(head, Vector3(0.0, 0.925, 0.0), Basis.IDENTITY, arrow_material, arrow)
		arrow.visible = false
		_arrows.append(arrow)


func _build_tether(cfg: VehicleConfig) -> void:
	var p := Vector3(-cfg.width * 0.18, cfg.height * 0.5, cfg.length * 0.44)
	_cylinder(0.032, 0.05, p + Vector3(0.0, 0.025, 0.0), Vector3.UP, _materials["tether"])
	var restrictor := CylinderMesh.new()
	restrictor.top_radius = 0.012
	restrictor.bottom_radius = 0.028
	restrictor.height = 0.12
	_mesh(restrictor, p + Vector3(0.0, 0.11, 0.0), Basis.IDENTITY, _materials["tether"], _model)
	# Short stub of the umbilical leaving aft and up (tether dynamics are not simulated).
	var cable_axis := Vector3(0.0, cos(deg_to_rad(60.0)), sin(deg_to_rad(60.0)))
	_cylinder(0.011, 0.3, p + Vector3(0.0, 0.17, 0.0) + cable_axis * 0.15, cable_axis, _materials["tether"])


func _build_markers() -> void:
	_markers = Node3D.new()
	_markers.name = "Markers"
	add_child(_markers)
	_marker(Vector3.ZERO, Color(1.0, 1.0, 1.0), "CG")
	_marker(vehicle.center_of_buoyancy, Color(0.3, 0.85, 1.0), "CB")


func _marker(at: Vector3, color: Color, text: String) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.render_priority = 10
	_sphere(0.025, at, material, _markers)
	var label := Label3D.new()
	label.text = text
	label.font_size = 32
	label.pixel_size = 0.002
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 11
	label.modulate = color
	label.outline_size = 6
	label.position = at + Vector3(0.06, 0.03, 0.0)
	_markers.add_child(label)


# --- Mesh helpers -----------------------------------------------------------------

func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _mesh(mesh: Mesh, at: Vector3, mesh_basis: Basis, material: Material, parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.basis = mesh_basis
	instance.position = at
	parent.add_child(instance)
	return instance


func _box(size: Vector3, at: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(mesh, at, Basis.IDENTITY, material, parent if parent != null else _model)


func _cylinder(radius: float, length: float, at: Vector3, axis: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.rings = 1
	return _mesh(mesh, at, _basis_up_to(axis), material, parent if parent != null else _model)


func _sphere(radius: float, at: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return _mesh(mesh, at, Basis.IDENTITY, material, parent if parent != null else _model)


## Rotation that maps +Y onto the given axis.
static func _basis_up_to(axis: Vector3) -> Basis:
	var a := axis.normalized()
	if a.dot(Vector3.UP) < -0.9999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, a))
