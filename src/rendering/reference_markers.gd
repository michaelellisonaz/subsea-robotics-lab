## Scale and orientation references: world axes at the site origin, distance
## labels along the axes, and a vertical depth gauge from seabed to surface.
## Purely visual; all positions come from the WorldModel.
class_name ReferenceMarkers
extends Node3D

const AXIS_LENGTH := 3.0
const LABEL_DISTANCES := [10, 20, 30, 40, 50]
## The depth gauge stands beside the origin (6 m W, 6 m N) so it does not
## block a top-down view of the axes.
const GAUGE_POSITION := Vector3(-6.0, 0.0, -6.0)
## Labels closer to the camera than this are hidden (they would fill the view), m.
const LABEL_MIN_VIEW_DISTANCE := 5.0
const COLOR_X := Color(0.95, 0.38, 0.32)
const COLOR_Y := Color(0.40, 0.90, 0.45)
const COLOR_Z := Color(0.35, 0.60, 1.0)
const COLOR_LABEL := Color(0.62, 0.90, 0.98)
const COLOR_GAUGE := Color(0.80, 0.90, 0.95)

var _world: WorldModel
var _axes: Node3D
var _labels: Node3D
var _gauge: Node3D
var _origin_label: Label3D


func build(world: WorldModel) -> void:
	_world = world
	_axes = _make_group("Axes")
	_labels = _make_group("DistanceLabels")
	_gauge = _make_group("DepthGauge")
	_gauge.position = GAUGE_POSITION
	_build_axes()
	_build_distance_labels()
	update_depth()


## Re-positions markers after the water depth changes.
func update_depth() -> void:
	position.y = _world.seabed_reference_y()
	_rebuild_depth_gauge()
	_origin_label.text = "SITE ORIGIN  ·  E 0  N 0  ·  depth %.1f m" % _world.environment.water_depth


func set_axes_visible(value: bool) -> void:
	_axes.visible = value
	_gauge.visible = value


func set_labels_visible(value: bool) -> void:
	_labels.visible = value


func are_axes_visible() -> bool:
	return _axes.visible


func are_labels_visible() -> bool:
	return _labels.visible


func _make_group(group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	add_child(node)
	return node


func _build_axes() -> void:
	var origin := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	origin.mesh = sphere
	origin.material_override = _make_material(Color(0.9, 0.95, 1.0))
	_axes.add_child(origin)

	_axes.add_child(_make_arrow(Vector3.RIGHT, COLOR_X))
	_axes.add_child(_make_arrow(Vector3.UP, COLOR_Y))
	_axes.add_child(_make_arrow(Vector3.BACK, COLOR_Z))
	_axes.add_child(_make_label("+X  East", COLOR_X, Vector3(AXIS_LENGTH + 0.6, 0.25, 0.0)))
	_axes.add_child(_make_label("+Y  Up", COLOR_Y, Vector3(0.0, AXIS_LENGTH + 0.45, 0.0)))
	_axes.add_child(_make_label("+Z  South", COLOR_Z, Vector3(0.0, 0.25, AXIS_LENGTH + 0.6)))
	_axes.add_child(_make_label("North  (-Z)", COLOR_LABEL, Vector3(0.0, 0.25, -AXIS_LENGTH - 0.6)))
	_origin_label = _make_label("", COLOR_LABEL, Vector3(-1.3, 0.5, 1.3), 40)
	_axes.add_child(_origin_label)


func _build_distance_labels() -> void:
	for d in LABEL_DISTANCES:
		_add_distance_label("%d m E" % d, float(d), 0.0)
		_add_distance_label("%d m W" % d, -float(d), 0.0)
		_add_distance_label("%d m N" % d, 0.0, -float(d))
		_add_distance_label("%d m S" % d, 0.0, float(d))


func _add_distance_label(text: String, x: float, z: float) -> void:
	var y := _world.bathymetry.height_offset(x, z) + 0.45
	_labels.add_child(_make_label(text, COLOR_LABEL, Vector3(x, y, z), 64))


func _rebuild_depth_gauge() -> void:
	for child in _gauge.get_children():
		child.free()
	var depth := _world.environment.water_depth
	_gauge.position.y = _world.bathymetry.height_offset(GAUGE_POSITION.x, GAUGE_POSITION.z)
	var pole_length := depth - _gauge.position.y
	var material := _make_material(COLOR_GAUGE, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.55

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.012
	pole_mesh.bottom_radius = 0.012
	pole_mesh.height = pole_length
	pole_mesh.radial_segments = 8
	pole_mesh.rings = 1
	pole.mesh = pole_mesh
	pole.material_override = material
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.position.y = pole_length * 0.5
	_gauge.add_child(pole)
	_gauge.add_child(_make_label("DEPTH GAUGE", COLOR_GAUGE, Vector3(0.0, 0.6, 0.0), 40))

	var tick_mesh := CylinderMesh.new()
	tick_mesh.top_radius = 0.1
	tick_mesh.bottom_radius = 0.1
	tick_mesh.height = 0.025
	tick_mesh.radial_segments = 12
	tick_mesh.rings = 1
	var spacing := _tick_spacing(depth)
	var tick_depth := spacing
	while tick_depth < depth - 0.01:
		# The gauge base sits on the seabed (at the reference level here, since
		# it is inside the level test area), so a point at depth d is
		# (water_depth - d) metres above the base.
		var local_y := depth - tick_depth - _gauge.position.y
		if local_y > 1.5:
			var tick := MeshInstance3D.new()
			tick.mesh = tick_mesh
			tick.material_override = material
			tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tick.visibility_range_begin = LABEL_MIN_VIEW_DISTANCE
			tick.position.y = local_y
			_gauge.add_child(tick)
			_gauge.add_child(_make_label("%d m" % int(tick_depth), COLOR_GAUGE, Vector3(0.45, local_y, 0.0), 44))
		tick_depth += spacing


func _tick_spacing(depth: float) -> float:
	if depth <= 60.0:
		return 5.0
	if depth <= 200.0:
		return 10.0
	if depth <= 500.0:
		return 25.0
	return 50.0


func _make_arrow(direction: Vector3, color: Color) -> Node3D:
	var arrow := Node3D.new()
	var material := _make_material(color)
	var head_length := 0.32

	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.035
	shaft_mesh.bottom_radius = 0.035
	shaft_mesh.height = AXIS_LENGTH - head_length
	shaft_mesh.radial_segments = 12
	shaft_mesh.rings = 1
	var shaft := MeshInstance3D.new()
	shaft.mesh = shaft_mesh
	shaft.material_override = material
	shaft.position.y = (AXIS_LENGTH - head_length) * 0.5
	arrow.add_child(shaft)

	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.1
	head_mesh.height = head_length
	head_mesh.radial_segments = 16
	head_mesh.rings = 1
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.material_override = material
	head.position.y = AXIS_LENGTH - head_length * 0.5
	arrow.add_child(head)

	# Arrow geometry points along +Y; rotate it onto the requested axis.
	arrow.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	return arrow


func _make_material(color: Color, emission_energy: float = 0.5) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	return material


func _make_label(text: String, color: Color, label_position: Vector3, font_size: int = 56) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.outline_size = 12
	label.outline_modulate = Color(0.0, 0.04, 0.06, 0.9)
	label.position = label_position
	label.visibility_range_begin = LABEL_MIN_VIEW_DISTANCE
	label.visibility_range_begin_margin = 1.0
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return label
