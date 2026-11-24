## Camera readout and numeric camera positioning, plus reset and preset views.
## Fields show the camera's target view and accept typed values; a field the
## user is editing is not overwritten by the live update.
class_name CameraPanel
extends VBoxContainer

## key, label, min, max, step, unit
const FIELDS := [
	["east", "Focus east", -500.0, 500.0, 0.1, "m"],
	["north", "Focus north", -500.0, 500.0, 0.1, "m"],
	["depth", "Focus depth", 0.0, 1000.0, 0.1, "m"],
	["heading", "View heading", 0.0, 359.9, 0.1, "°"],
	["elevation", "View elevation", -89.0, 75.0, 0.1, "°"],
	["distance", "Distance", 1.0, 250.0, 0.1, "m"],
]
const PRESET_BUTTONS := [
	["top", "Top", "Look straight down on the site origin"],
	["north", "Look N", "Low view looking north across the site"],
	["west", "Look W", "Low view looking west across the site"],
]

var reset_button: Button
var preset_buttons: Dictionary = {}

var _camera: OrbitCamera
var _world: WorldModel
var _views: ViewController
var _fields: Dictionary = {}
var _position_label: Label
var _altitude_label: Label
var _updating: bool = false


func _init() -> void:
	name = "CameraPanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func bind(camera: OrbitCamera, world: WorldModel, views: ViewController = null) -> void:
	_camera = camera
	_world = world
	_views = views
	add_child(UIWidgets.section_header("Camera"))

	var readout := GridContainer.new()
	readout.columns = 2
	readout.add_theme_constant_override("h_separation", 12)
	readout.add_child(UIWidgets.dim_label("Position", "Camera position: east, north, depth"))
	_position_label = Label.new()
	readout.add_child(_position_label)
	readout.add_child(UIWidgets.dim_label("Above seabed", "Camera height above the local seabed"))
	_altitude_label = Label.new()
	readout.add_child(_altitude_label)
	add_child(readout)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	for field in FIELDS:
		var label := Label.new()
		label.text = field[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		var spin := UIWidgets.spin_box(field[2], field[3], field[4], field[5])
		spin.value_changed.connect(_on_field_changed.bind(field[0]))
		grid.add_child(spin)
		_fields[field[0]] = spin
	add_child(grid)

	var buttons := HBoxContainer.new()
	reset_button = UIWidgets.button("Reset view", "Reset the current view (Home): behind the vehicle in vehicle views, the site origin in free camera")
	reset_button.pressed.connect(func() -> void:
		if _views != null:
			_views.reset_view()
		else:
			_camera.reset_view())
	buttons.add_child(reset_button)
	for preset in PRESET_BUTTONS:
		var b := UIWidgets.button(preset[1], preset[2])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_camera.apply_preset.bind(preset[0], false))
		buttons.add_child(b)
		preset_buttons[preset[0]] = b
	add_child(buttons)


func get_field(key: String) -> SpinBox:
	return _fields[key]


func _process(_delta: float) -> void:
	if _camera == null:
		return
	var p := _camera.get_camera_position()
	_position_label.text = "E %.1f  N %.1f  D %.1f m" % [p.x, -p.z, -p.y]
	_altitude_label.text = "%.1f m" % (p.y - _world.seabed_y_at(p.x, p.z))
	var focus := _camera.get_focus_enu_depth()
	_updating = true
	_show("east", focus.x)
	_show("north", focus.y)
	_show("depth", focus.z)
	_show("heading", _camera.get_heading())
	_show("elevation", _camera.elevation)
	_show("distance", _camera.distance)
	_updating = false


func _show(key: String, value: float) -> void:
	var spin: SpinBox = _fields[key]
	if spin.get_line_edit().has_focus():
		return
	spin.value = value


func _on_field_changed(value: float, key: String) -> void:
	if _updating:
		return
	match key:
		"east", "north", "depth":
			var focus := _camera.get_focus_enu_depth()
			if key == "east":
				focus.x = value
			elif key == "north":
				focus.y = value
			else:
				focus.z = value
			_camera.set_focus_enu_depth(focus.x, focus.y, focus.z)
		"heading":
			_camera.set_heading(value)
		"elevation":
			_camera.set_elevation(value)
		"distance":
			_camera.set_distance(value)
