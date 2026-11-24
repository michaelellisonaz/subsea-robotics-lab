## Live sensor readings next to the ground truth and the error, plus the
## imaging-sonar fan, the multibeam profile and the stereo camera pair.
class_name SensorReadingsPanel
extends VBoxContainer

const REFRESH_INTERVAL := 0.1
## Rows: id, label, sensor, value key, unit, format.
const ROWS := [
	["depth", "Depth", "Depth", "depth", "m", "%.3f"],
	["heading", "Heading", "Compass", "heading", "°", "%.1f"],
	["roll", "Roll", "IMU", "roll", "°", "%+.2f"],
	["pitch", "Pitch", "IMU", "pitch", "°", "%+.2f"],
	["yaw_rate", "Yaw rate", "IMU", "yaw_rate", "°/s", "%+.2f"],
	["accel_up", "Accel up", "IMU", "accel_up", "m/s²", "%.3f"],
	["dvl_forward", "DVL fwd vel.", "DVL", "forward", "m/s", "%+.3f"],
	["dvl_starboard", "DVL stbd vel.", "DVL", "starboard", "m/s", "%+.3f"],
	["dvl_up", "DVL up vel.", "DVL", "up", "m/s", "%+.3f"],
	["dvl_altitude", "DVL altitude", "DVL", "altitude", "m", "%.2f"],
	["altimeter", "Altimeter", "Altimeter", "range", "m", "%.2f"],
	["usbl_east", "USBL east", "USBL", "east", "m", "%.2f"],
	["usbl_north", "USBL north", "USBL", "north", "m", "%.2f"],
	["usbl_depth", "USBL depth", "USBL", "depth", "m", "%.2f"],
]

var sonar_display: SonarDisplay
var multibeam_display: MultibeamDisplay
var stereo_left: TextureRect
var stereo_right: TextureRect

var _vehicle: RovVehicle
var _stereo: StereoFeed
var _cells: Dictionary = {}  # id -> [measured, truth, error]
var _status: Dictionary = {}  # sensor name -> Label
var _stereo_box: Control
var _stereo_note: Label
var _elapsed: float = 0.0


func _init() -> void:
	name = "SensorReadingsPanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func bind(vehicle: RovVehicle, stereo: StereoFeed) -> void:
	_vehicle = vehicle
	_stereo = stereo
	add_child(UIWidgets.section_header("Sensor status"))
	var status_grid := GridContainer.new()
	status_grid.columns = 2
	status_grid.add_theme_constant_override("h_separation", 12)
	for sensor in vehicle.sensors.sensors:
		if not sensor.has_param("rate_hz"):
			continue
		status_grid.add_child(UIWidgets.dim_label(sensor.sensor_name, sensor.description))
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_grid.add_child(label)
		_status[sensor.sensor_name] = label
	add_child(status_grid)

	add_child(UIWidgets.spacer(4.0))
	add_child(UIWidgets.section_header("Measured vs. truth"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	for heading in ["", "Measured", "Truth", "Error"]:
		grid.add_child(UIWidgets.dim_label(heading))
	for row in ROWS:
		grid.add_child(UIWidgets.dim_label("%s (%s)" % [row[1], row[4]]))
		var cells: Array[Label] = []
		for k in 3:
			var cell := Label.new()
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cell.custom_minimum_size = Vector2(62.0, 0.0)
			grid.add_child(cell)
			cells.append(cell)
		_cells[row[0]] = cells
	add_child(grid)
	var truth_note := UIWidgets.dim_label("Truth is shown for evaluation only; pilot aids and the onboard HUD use the measured values.")
	truth_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(truth_note)

	add_child(UIWidgets.spacer(4.0))
	add_child(UIWidgets.section_header("Imaging sonar"))
	sonar_display = SonarDisplay.new()
	sonar_display.bind(vehicle.sensors.get_sensor("Imaging sonar"))
	add_child(sonar_display)
	add_child(UIWidgets.spacer(4.0))
	add_child(UIWidgets.section_header("Multibeam swath"))
	multibeam_display = MultibeamDisplay.new()
	multibeam_display.bind(vehicle.sensors.get_sensor("Multibeam"))
	add_child(multibeam_display)

	add_child(UIWidgets.spacer(4.0))
	add_child(UIWidgets.section_header("Stereo camera"))
	_stereo_note = UIWidgets.dim_label("Disabled - enable it in the Sensors settings tab (renders two extra views).")
	_stereo_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_stereo_note)
	var pair := HBoxContainer.new()
	stereo_left = _stereo_rect(stereo.left_texture())
	stereo_right = _stereo_rect(stereo.right_texture())
	pair.add_child(stereo_left)
	pair.add_child(stereo_right)
	_stereo_box = pair
	add_child(pair)
	refresh()


func get_cell_text(id: String, column: int) -> String:
	return _cells[id][column].text


func _process(delta: float) -> void:
	if _vehicle == null:
		return
	_stereo_box.visible = _stereo.is_active()
	_stereo_note.visible = not _stereo.is_active()
	_elapsed += delta
	if _elapsed >= REFRESH_INTERVAL and is_visible_in_tree():
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	var now := _vehicle.last_update_time
	for sensor_name in _status:
		var sensor := _vehicle.sensors.get_sensor(sensor_name)
		var label: Label = _status[sensor_name]
		if not sensor.enabled:
			label.text = "off"
		elif sensor.latest == null:
			label.text = "waiting (run the simulation)"
		elif not sensor.latest.valid:
			label.text = _invalid_reason(sensor)
		else:
			label.text = "OK · %.0f Hz · age %.2f s" % [sensor.get_param("rate_hz"), sensor.latest.age(now)]
	for row in ROWS:
		var cells: Array = _cells[row[0]]
		var sensor := _vehicle.sensors.get_sensor(row[2])
		var reading := sensor.latest if sensor != null and sensor.enabled else null
		if reading == null:
			for cell in cells:
				cell.text = "-"
			continue
		var truth = reading.truth.get(row[3], NAN)
		var measured = reading.values.get(row[3], NAN) if reading.valid else NAN
		cells[0].text = _format(row[5], measured)
		cells[1].text = _format(row[5], truth)
		var error := NAN
		if not is_nan(measured) and not is_nan(truth) and measured != INF and truth != INF:
			error = wrapf(measured - truth, -180.0, 180.0) if row[0] == "heading" else measured - truth
		cells[2].text = _format("%+.3f", error)


func _invalid_reason(sensor: Sensor) -> String:
	match sensor.sensor_type:
		"dvl":
			return "NO BOTTOM LOCK (%d/4 beams)" % sensor.latest.values.get("beams_locked", 0)
		"altimeter":
			return "no echo (out of range)"
		"multibeam":
			return "no echoes"
	return "invalid"


static func _format(fmt: String, value) -> String:
	if value == null or (typeof(value) == TYPE_FLOAT and (is_nan(value) or is_inf(value))):
		return "-"
	return fmt % value


func _stereo_rect(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(160.0, 120.0)
	rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rect
