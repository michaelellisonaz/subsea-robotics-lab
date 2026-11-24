## Suspended particulate matter ("marine snow") in a box around the camera.
##
## Particles drift with the configured water current, and their motion follows
## simulation time: speed_scale is set to the simulation time scale while
## running and to 0 while paused or reset, so they freeze with the clock.
## Purely visual - particles are not simulation objects.
class_name MarineSnow
extends GPUParticles3D

const BOX_EXTENTS := Vector3(14.0, 8.0, 14.0)
const BASE_COLOR := Color(0.78, 0.88, 0.85, 0.55)
const PARTICLE_COUNT := 1600
const PARTICLE_LIFETIME := 16.0

## The emitter box follows this node (normally the active camera).
var follow_target: Node3D

var _process_material: ParticleProcessMaterial
var _draw_material: StandardMaterial3D


func build() -> void:
	amount = PARTICLE_COUNT
	lifetime = PARTICLE_LIFETIME
	preprocess = PARTICLE_LIFETIME
	local_coords = false
	visibility_aabb = AABB(-BOX_EXTENTS * 2.0, BOX_EXTENTS * 4.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_process_material = ParticleProcessMaterial.new()
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_material.emission_box_extents = BOX_EXTENTS
	_process_material.gravity = Vector3(0.0, -0.002, 0.0)
	_process_material.scale_min = 0.4
	_process_material.scale_max = 1.4
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	_process_material.color_ramp = ramp
	process_material = _process_material

	_draw_material = StandardMaterial3D.new()
	_draw_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_draw_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_draw_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_draw_material.vertex_color_use_as_albedo = true
	_draw_material.albedo_color = BASE_COLOR
	# Soft round dots instead of square quads.
	var dot := Gradient.new()
	dot.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	dot.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var dot_texture := GradientTexture2D.new()
	dot_texture.gradient = dot
	dot_texture.fill = GradientTexture2D.FILL_RADIAL
	dot_texture.fill_from = Vector2(0.5, 0.5)
	dot_texture.fill_to = Vector2(1.0, 0.5)
	dot_texture.width = 32
	dot_texture.height = 32
	_draw_material.albedo_texture = dot_texture
	# Fade out particles right in front of the lens so they never appear as big squares.
	_draw_material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_draw_material.distance_fade_min_distance = 0.6
	_draw_material.distance_fade_max_distance = 2.5
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = _draw_material
	draw_pass_1 = quad

	set_drift(Vector3.ZERO)
	set_time_flow(0.0)


func _process(_delta: float) -> void:
	if follow_target != null and is_instance_valid(follow_target):
		global_position = follow_target.global_position


## Sets the drift velocity of newly emitted particles (the water current), m/s.
func set_drift(current_velocity: Vector3) -> void:
	var speed := current_velocity.length()
	if speed < 0.005:
		_process_material.direction = Vector3.UP
		_process_material.spread = 180.0
		_process_material.initial_velocity_min = 0.0
		_process_material.initial_velocity_max = 0.02
	else:
		_process_material.direction = current_velocity / speed
		_process_material.spread = 8.0
		_process_material.initial_velocity_min = speed * 0.9
		_process_material.initial_velocity_max = speed * 1.1


## Simulated seconds per real second for particle motion (0 freezes them).
func set_time_flow(rate: float) -> void:
	speed_scale = maxf(rate, 0.0)


func set_light_level(level: float) -> void:
	_draw_material.albedo_color = Color(
		BASE_COLOR.r * level, BASE_COLOR.g * level, BASE_COLOR.b * level, BASE_COLOR.a)
