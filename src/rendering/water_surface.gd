## Underside of the sea surface at y = 0 with a slow procedural shimmer.
## The shimmer is driven by simulation time, so it stops while paused.
class_name WaterSurface
extends MeshInstance3D

const SURFACE_SHADER := preload("res://src/rendering/shaders/water_surface.gdshader")

## Last simulation time pushed to the shader, s.
var sim_time: float = 0.0

var _material: ShaderMaterial


func build(half_extent: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_extent * 2.0, half_extent * 2.0)
	mesh = plane
	_material = ShaderMaterial.new()
	_material.shader = SURFACE_SHADER
	material_override = _material
	# The surface must not shadow the whole scene from the downwelling light.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position = Vector3(0.0, WorldModel.SURFACE_Y, 0.0)


func set_sim_time(time: float) -> void:
	sim_time = time
	_material.set_shader_parameter("sim_time", time)


func set_brightness(value: float) -> void:
	_material.set_shader_parameter("brightness", value)
