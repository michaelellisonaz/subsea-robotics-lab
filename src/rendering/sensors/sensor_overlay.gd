## 3D visualisation of sensor coverage, drawn as lines each frame from the
## sensors' latest readings (not from ground truth):
##   DVL beams       green to the measured seabed hit (red: no bottom lock)
##   altimeter       yellow beam
##   imaging sonar   cyan fan outline at its range and tilt
##   multibeam       orange swath edges and the measured seabed profile
##   pilot camera    white field-of-view frustum (1.5 m)
##   USBL            magenta acoustic path from the vessel; cross at the fix
## Hidden in the onboard view so it never blocks the pilot camera.
class_name SensorOverlay
extends MeshInstance3D

const COLOR_DVL := Color(0.35, 1.0, 0.45, 0.9)
const COLOR_DVL_NO_LOCK := Color(1.0, 0.35, 0.3, 0.5)
const COLOR_ALTIMETER := Color(1.0, 0.9, 0.3, 0.9)
const COLOR_SONAR := Color(0.3, 0.9, 1.0, 0.7)
const COLOR_MULTIBEAM := Color(1.0, 0.6, 0.2, 0.9)
const COLOR_CAMERA := Color(1.0, 1.0, 1.0, 0.45)
const COLOR_USBL := Color(1.0, 0.35, 0.95, 0.75)

var vehicle: RovVehicle
var visual: RovVisual
var coverage_visible: bool = true

var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()
var _lines := PackedVector3Array()
var _colors := PackedColorArray()


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = _material


func bind(p_vehicle: RovVehicle, p_visual: RovVisual) -> void:
	vehicle = p_vehicle
	visual = p_visual


func set_coverage_visible(value: bool) -> void:
	coverage_visible = value


## Number of line segments drawn in the last frame (for tests).
func segment_count() -> int:
	return _lines.size() / 2


func _process(_delta: float) -> void:
	_lines.clear()
	_colors.clear()
	_mesh.clear_surfaces()
	if vehicle == null or not coverage_visible or visual.onboard_view:
		return
	var pose := visual.global_transform
	for sensor in vehicle.sensors.sensors:
		if not sensor.enabled:
			continue
		var origin := pose * sensor.mount_position
		var to_world := pose.basis * sensor.mount_basis
		match sensor.sensor_type:
			"dvl":
				_draw_dvl(sensor, origin, to_world)
			"altimeter":
				_draw_altimeter(sensor, origin, to_world)
			"imaging_sonar":
				_draw_sonar(sensor, origin, to_world)
			"multibeam":
				_draw_multibeam(sensor, origin, to_world)
			"camera":
				_draw_camera(sensor, origin, to_world)
			"usbl":
				_draw_usbl(sensor, origin)
	if _lines.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in _lines.size():
		_mesh.surface_set_color(_colors[i])
		_mesh.surface_add_vertex(_lines[i])
	_mesh.surface_end()


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_lines.append(a)
	_lines.append(b)
	_colors.append(color)
	_colors.append(color)


func _draw_dvl(sensor: Sensor, origin: Vector3, to_world: Basis) -> void:
	var dvl := sensor as DvlSensor
	var reading := dvl.latest
	var ranges: Array = reading.values.get("beam_ranges", []) if reading != null else []
	var max_slant := dvl.get_param("max_altitude") / cos(deg_to_rad(dvl.get_param("beam_angle")))
	var beams := dvl.beam_directions()
	for i in beams.size():
		var r: float = ranges[i] if i < ranges.size() else INF
		var locked := r < INF and reading.valid
		_line(origin, origin + to_world * beams[i] * (r if r < INF else minf(max_slant, 4.0)), COLOR_DVL if locked else COLOR_DVL_NO_LOCK)


func _draw_altimeter(sensor: Sensor, origin: Vector3, to_world: Basis) -> void:
	var reading := sensor.latest
	var r: float = reading.values.get("range", INF) if reading != null else INF
	var length := r if r < INF else minf(sensor.get_param("max_range"), 4.0)
	_line(origin, origin + to_world * Vector3.DOWN * length, COLOR_ALTIMETER if r < INF else COLOR_DVL_NO_LOCK)


func _draw_sonar(sensor: Sensor, origin: Vector3, to_world: Basis) -> void:
	var sonar := sensor as ImagingSonar
	var max_range := sonar.get_param("max_range")
	var tilt := deg_to_rad(sonar.get_param("tilt"))
	var previous := Vector3.ZERO
	var segments := 16
	for k in segments + 1:
		var beam := int(round(float(k) / segments * (ImagingSonar.BEAMS - 1)))
		var azimuth := sonar.beam_azimuth(beam)
		var direction := to_world * Vector3(cos(tilt) * sin(azimuth), sin(tilt), -cos(tilt) * cos(azimuth))
		var point := origin + direction * max_range
		if k == 0 or k == segments:
			_line(origin, point, COLOR_SONAR)
		if k > 0:
			_line(previous, point, COLOR_SONAR)
		previous = point


func _draw_multibeam(sensor: Sensor, origin: Vector3, to_world: Basis) -> void:
	var multibeam := sensor as MultibeamSonar
	var reading := multibeam.latest
	if reading == null:
		return
	var across: PackedFloat32Array = reading.values.get("across", PackedFloat32Array())
	var below: PackedFloat32Array = reading.values.get("below", PackedFloat32Array())
	var previous := Vector3.INF
	for i in across.size():
		if is_nan(across[i]):
			previous = Vector3.INF
			continue
		var point := origin + to_world * Vector3(across[i], -below[i], 0.0)
		if i == 0 or i == across.size() - 1:
			_line(origin, point, COLOR_MULTIBEAM)
		if previous != Vector3.INF:
			_line(previous, point, COLOR_MULTIBEAM)
		previous = point


func _draw_camera(sensor: Sensor, origin: Vector3, to_world: Basis) -> void:
	var half_v := deg_to_rad(sensor.get_param("fov")) * 0.5
	var half_h := atan(tan(half_v) * 16.0 / 9.0)
	var length := 1.5
	var corners: Array[Vector3] = []
	for sy in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			corners.append(origin + to_world * Vector3(sx * tan(half_h), sy * tan(half_v), -1.0) * length)
	for c in corners:
		_line(origin, c, COLOR_CAMERA)
	_line(corners[0], corners[1], COLOR_CAMERA)
	_line(corners[1], corners[3], COLOR_CAMERA)
	_line(corners[3], corners[2], COLOR_CAMERA)
	_line(corners[2], corners[0], COLOR_CAMERA)


func _draw_usbl(sensor: Sensor, origin: Vector3) -> void:
	_line(UsblSensor.TRANSCEIVER_POSITION, origin, COLOR_USBL)
	var reading := sensor.latest
	if reading == null:
		return
	var fix := Vector3(reading.values["east"], -reading.values["depth"], -reading.values["north"])
	var s := 0.25
	_line(fix - Vector3(s, 0, 0), fix + Vector3(s, 0, 0), COLOR_USBL)
	_line(fix - Vector3(0, s, 0), fix + Vector3(0, s, 0), COLOR_USBL)
	_line(fix - Vector3(0, 0, s), fix + Vector3(0, 0, s), COLOR_USBL)
