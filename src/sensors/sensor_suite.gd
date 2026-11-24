## The set of sensors carried by one vehicle: creation of the default
## instrument package, mounting positions derived from the vehicle geometry,
## per-step updates, reset, and saving/loading sensor settings.
class_name SensorSuite
extends RefCounted

const FILE_FORMAT := "subsea-robotics-lab/sensors"
const FILE_VERSION := 1

var sensors: Array[Sensor] = []


## Standard inspection-ROV instrument package. Each sensor gets its own fixed
## noise seed so runs are repeatable.
static func create_default() -> SensorSuite:
	var suite := SensorSuite.new()
	suite.add(DepthSensor.new(), 101)
	suite.add(ImuSensor.new(), 102)
	suite.add(CompassSensor.new(), 103)
	suite.add(DvlSensor.new(), 104)
	suite.add(AltimeterSensor.new(), 105)
	suite.add(UsblSensor.new(), 106)
	suite.add(ImagingSonar.new(), 107)
	suite.add(MultibeamSonar.new(), 108)
	suite.add(CameraSensor.new(), 109)
	suite.add(StereoCameraSensor.new(), 110)
	return suite


func add(sensor: Sensor, seed_value: int = 1) -> Sensor:
	sensor.noise_seed = seed_value
	sensor.reset()
	sensors.append(sensor)
	return sensor


func get_sensor(sensor_name: String) -> Sensor:
	for sensor in sensors:
		if sensor.sensor_name == sensor_name:
			return sensor
	return null


## Places every sensor on the vehicle frame (geometric positions scale with
## the vehicle dimensions and are converted to body axes about the CG).
func update_mounts(config: VehicleConfig) -> void:
	var l := config.length
	var w := config.width
	var h := config.height
	_mount(config, "Depth", Vector3(0.0, 0.0, 0.1 * l))
	_mount(config, "IMU", Vector3(0.0, -0.06 * h, 0.0))
	_mount(config, "Compass", Vector3(0.0, 0.0, 0.2 * l))
	_mount(config, "DVL", Vector3(0.0, -0.5 * h + 0.02, 0.15 * l))
	_mount(config, "Altimeter", Vector3(0.0, -0.5 * h + 0.03, -0.42 * l))
	_mount(config, "USBL", Vector3(0.18 * w, 0.5 * h + 0.05, 0.30 * l))
	_mount(config, "Imaging sonar", Vector3(0.0, 0.5 * h + 0.045, -0.40 * l))
	_mount(config, "Multibeam", Vector3(0.0, -0.5 * h + 0.02, -0.25 * l))
	_mount(config, "Camera", config.camera_position_geometric())
	_mount(config, "Stereo camera", Vector3(0.0, -0.28 * h, -0.5 * l - 0.03))


func update(context: StepContext, host: RigidSimBody) -> void:
	for sensor in sensors:
		sensor.update(context, host)


func reset() -> void:
	for sensor in sensors:
		sensor.reset()


func reset_parameters() -> void:
	for sensor in sensors:
		sensor.reset_parameters()
		sensor.enabled = sensor.sensor_type != "stereo_camera"


func to_dict() -> Dictionary:
	var data := {}
	for sensor in sensors:
		data[sensor.sensor_name] = sensor.to_dict()
	return data


func apply_dict(data: Dictionary) -> void:
	for sensor in sensors:
		if typeof(data.get(sensor.sensor_name)) == TYPE_DICTIONARY:
			sensor.apply_dict(data[sensor.sensor_name])


func save_json(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"format": FILE_FORMAT, "version": FILE_VERSION, "sensors": to_dict()}, "\t"))
	file.close()
	return OK


func load_json(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return ERR_PARSE_ERROR
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY or str(data.get("format", "")) != FILE_FORMAT or typeof(data.get("sensors")) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR
	apply_dict(data["sensors"])
	return OK


func _mount(config: VehicleConfig, sensor_name: String, geometric_position: Vector3) -> void:
	var sensor := get_sensor(sensor_name)
	if sensor != null:
		sensor.mount_position = config.to_body(geometric_position)
