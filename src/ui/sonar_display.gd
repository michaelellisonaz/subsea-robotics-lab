## Imaging-sonar fan display: uploads each new ping as a small float texture
## and lets a shader draw it in polar form, with range rings and labels on top.
class_name SonarDisplay
extends Control

const FAN_SHADER := preload("res://src/rendering/shaders/sonar_fan.gdshader")
const DISPLAY_SIZE := Vector2(320.0, 190.0)

var sonar: ImagingSonar
## Number of pings drawn so far (for tests / diagnostics).
var pings_shown: int = 0

var _fan: TextureRect
var _overlay: Control
var _material: ShaderMaterial
var _image: Image
var _texture: ImageTexture
var _last_time: float = -1.0


func _init() -> void:
	custom_minimum_size = DISPLAY_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = FAN_SHADER
	_image = Image.create(ImagingSonar.BEAMS, ImagingSonar.BINS, false, Image.FORMAT_RF)
	_texture = ImageTexture.create_from_image(_image)
	_material.set_shader_parameter("data", _texture)
	_fan = TextureRect.new()
	_fan.texture = _texture
	_fan.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fan.stretch_mode = TextureRect.STRETCH_SCALE
	_fan.material = _material
	_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fan)
	_fan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func bind(p_sonar: ImagingSonar) -> void:
	sonar = p_sonar


func _process(_delta: float) -> void:
	if sonar == null or not is_visible_in_tree():
		return
	_material.set_shader_parameter("half_fov", deg_to_rad(sonar.get_param("horizontal_fov")) * 0.5)
	_material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	var reading := sonar.latest
	if reading != null and reading.time != _last_time:
		_last_time = reading.time
		var image_data: PackedFloat32Array = reading.values["image"]
		_image.set_data(ImagingSonar.BEAMS, ImagingSonar.BINS, false, Image.FORMAT_RF, image_data.to_byte_array())
		_texture.update(_image)
		pings_shown += 1
		_overlay.queue_redraw()


func _draw_overlay() -> void:
	if sonar == null:
		return
	var apex := Vector2(size.x * 0.5, size.y)
	var max_range := sonar.get_param("max_range")
	var half := deg_to_rad(sonar.get_param("horizontal_fov")) * 0.5
	var color := Color(0.55, 0.85, 0.95, 0.35)
	var font := get_theme_default_font()
	for fraction in [0.25, 0.5, 0.75, 1.0]:
		var radius: float = size.y * fraction
		_overlay.draw_arc(apex, radius, -PI * 0.5 - half, -PI * 0.5 + half, 24, color, 1.0)
		_overlay.draw_string(font, apex + Vector2(4.0, -radius + 12.0), "%.0f m" % (max_range * fraction),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
	for side in [-1.0, 1.0]:
		_overlay.draw_line(apex, apex + Vector2(sin(side * half), -cos(side * half)) * size.y, color, 1.0)
	if sonar.latest == null:
		_overlay.draw_string(font, Vector2(8.0, 16.0), "No ping yet (start the simulation)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
