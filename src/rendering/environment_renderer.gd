## Visual representation of the water body.
##
## Reads EnvironmentConfig and WorldModel and turns them into fog, lighting,
## seabed, reference markers, surface and suspended particles. It never writes
## simulation data, and nothing in src/simulation depends on it.
##
## Optical mapping (visual approximation, documented in README):
##   * Fog density   = optical extinction = 3.912 / visibility   (per metre)
##   * Daylight left at depth d: f = exp(-Kd * d), Kd ~ 1.44 / visibility
##   * Rendered light level = clamp(f ^ 0.3, 0.15, 1): compressed so the
##     scene stays legible at depth; it is NOT a radiometric value.
##   * Fog colour depends on the camera's depth (darker and bluer deeper),
##     scene lighting depends on the seabed depth.
class_name EnvironmentRenderer
extends Node3D

const WATER_COLOR_SHALLOW := Color(0.06, 0.25, 0.28)
const WATER_COLOR_DEEP := Color(0.01, 0.05, 0.09)
## Depth over which the water tint shifts from the shallow to the deep colour, m.
const COLOR_SHIFT_DEPTH := 120.0
## Lower bound of the rendered light level, so deep scenes remain visible.
const MIN_VISUAL_LIGHT := 0.15
## Exponent compressing the physical light fraction into a displayable range.
const LIGHT_DISPLAY_EXPONENT := 0.3
const SUN_ENERGY := 1.5
const AMBIENT_ENERGY := 0.6

@onready var seabed: SeabedRenderer = $Seabed
@onready var markers: ReferenceMarkers = $ReferenceMarkers
@onready var surface: WaterSurface = $WaterSurface
@onready var marine_snow: MarineSnow = $MarineSnow
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _light: DirectionalLight3D = $DownwellingLight

var _config: EnvironmentConfig
var _world: WorldModel
var _environment: Environment
var _camera: Camera3D
var _brightness: float = 1.0
var _last_camera_depth: float = -1.0


func setup(world: WorldModel, config: EnvironmentConfig) -> void:
	_world = world
	_config = config
	_environment = _create_environment()
	_world_environment.environment = _environment
	_configure_light()
	seabed.build(world)
	markers.build(world)
	surface.build(world.half_extent)
	marine_snow.build()
	marine_snow.set_drift(config.current_velocity())
	config.parameter_changed.connect(_on_parameter_changed)
	_apply_depth()
	_apply_optics()


## Camera whose depth sets the fog colour and around which particles spawn.
func set_view_camera(camera: Camera3D) -> void:
	_camera = camera
	marine_snow.follow_target = camera
	_last_camera_depth = -1.0


## Simulation time for time-driven visuals (surface shimmer).
func set_sim_time(time: float) -> void:
	surface.set_sim_time(time)


## Simulated seconds per real second for animated visuals; 0 freezes them.
func set_time_flow(rate: float) -> void:
	marine_snow.set_time_flow(rate)


func set_grid_visible(value: bool) -> void:
	seabed.set_grid_visible(value)


func set_markers_visible(value: bool) -> void:
	markers.set_axes_visible(value)


func set_labels_visible(value: bool) -> void:
	markers.set_labels_visible(value)


func set_particles_visible(value: bool) -> void:
	marine_snow.visible = value


## Visual exposure multiplier (does not change any simulation value).
func set_brightness(value: float) -> void:
	_brightness = clampf(value, 0.25, 3.0)
	if _environment != null:
		_apply_optics()


func get_brightness() -> float:
	return _brightness


func get_fog_density() -> float:
	return _environment.fog_density


func get_fog_color() -> Color:
	return _environment.fog_light_color


func get_light_energy() -> float:
	return _light.light_energy


## Maps a physical daylight fraction (0..1) to the rendered light level.
static func visual_light_level(fraction: float) -> float:
	return clampf(pow(maxf(fraction, 0.0), LIGHT_DISPLAY_EXPONENT), MIN_VISUAL_LIGHT, 1.0)


static func water_tint(depth: float) -> Color:
	return WATER_COLOR_SHALLOW.lerp(WATER_COLOR_DEEP, clampf(depth / COLOR_SHIFT_DEPTH, 0.0, 1.0))


func _process(_delta: float) -> void:
	if _camera == null or _config == null:
		return
	var depth := maxf(-_camera.global_position.y, 0.0)
	if absf(depth - _last_camera_depth) > 0.05:
		_last_camera_depth = depth
		_apply_fog_color(depth)


func _on_parameter_changed(key: String, _value: float) -> void:
	match key:
		"water_depth":
			_apply_depth()
			_apply_optics()
		"visibility":
			_apply_optics()
		"current_speed", "current_heading":
			marine_snow.set_drift(_config.current_velocity())


func _apply_depth() -> void:
	seabed.set_reference_y(_world.seabed_reference_y())
	markers.update_depth()


func _apply_optics() -> void:
	_environment.fog_density = _config.optical_extinction_coefficient()
	var seabed_light := visual_light_level(_config.light_fraction_at_depth(_config.water_depth))
	_light.light_energy = SUN_ENERGY * seabed_light * _brightness
	_environment.ambient_light_energy = AMBIENT_ENERGY * seabed_light * _brightness
	_environment.ambient_light_color = water_tint(_config.water_depth).lightened(0.25)
	marine_snow.set_light_level(seabed_light * _brightness)
	surface.set_brightness(_brightness)
	var camera_depth := maxf(-_camera.global_position.y, 0.0) if _camera != null else _config.water_depth
	_last_camera_depth = camera_depth
	_apply_fog_color(camera_depth)


func _apply_fog_color(camera_depth: float) -> void:
	var level := visual_light_level(_config.light_fraction_at_depth(camera_depth)) * _brightness
	var tint := water_tint(camera_depth)
	var color := Color(tint.r * level, tint.g * level, tint.b * level, 1.0)
	_environment.fog_light_color = color
	_environment.background_color = color


func _create_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_aerial_perspective = 0.0
	env.fog_sky_affect = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.02
	return env


func _configure_light() -> void:
	# Downwelling daylight: steep, slightly blue-green, soft shadows.
	_light.rotation_degrees = Vector3(-72.0, 25.0, 0.0)
	_light.light_color = Color(0.72, 0.93, 1.0)
	_light.shadow_enabled = true
	_light.directional_shadow_max_distance = 120.0
