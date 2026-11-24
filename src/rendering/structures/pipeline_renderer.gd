## 3D model of a Pipeline, rebuilt whenever its geometry changes: steel pipe
## (surface drawn from the simulated deposit grid: marine growth, corrosion
## product, cleaned paint or bare steel), bolted flange joints, blind flanges
## at the ends, concrete supports, anode bracelets (the depleted one dark and
## eroded) and a circumferential crack. Installed clamps are drawn by
## ObjectVisuals. Optional ground-truth markers label the defect locations
## (off by default, so the defects can be looked for).
class_name PipelineRenderer
extends Node3D

const SURFACE_SHADER := preload("res://src/rendering/shaders/pipe_surface.gdshader")
const BOLTS_PER_FLANGE := 12
## Seconds between uploads of the deposit grid to the texture.
const TEXTURE_INTERVAL := 0.15

var pipeline: Pipeline
var defect_markers_visible: bool = false

var _root: Node3D
var _markers: Node3D
var _materials: Dictionary = {}
var _deposit_image: Image
var _deposit_texture: ImageTexture
var _uploaded_version: int = -1
var _upload_timer: float = 0.0


func bind(p_pipeline: Pipeline) -> void:
	pipeline = p_pipeline
	pipeline.geometry_changed.connect(_rebuild)
	_create_materials()
	_rebuild()


func set_defect_markers_visible(value: bool) -> void:
	defect_markers_visible = value
	if _markers != null:
		_markers.visible = value


func _create_materials() -> void:
	_materials["paint"] = _material(Color(0.20, 0.25, 0.22), 0.35, 0.55)
	_materials["steel"] = _material(Color(0.50, 0.52, 0.55), 0.85, 0.35)
	_materials["bolt"] = _material(Color(0.30, 0.30, 0.32), 0.8, 0.45)
	_materials["concrete"] = _material(Color(0.45, 0.45, 0.42), 0.0, 0.95)
	_materials["crack"] = _material(Color(0.02, 0.02, 0.02), 0.0, 0.9)
	_materials["anode"] = _material(Color(0.72, 0.74, 0.76), 0.6, 0.45)
	_materials["anode_depleted"] = _material(Color(0.30, 0.28, 0.25), 0.2, 0.95)
	var surface := ShaderMaterial.new()
	surface.shader = SURFACE_SHADER
	_materials["surface"] = surface
	_upload_deposits()


func _process(delta: float) -> void:
	if pipeline == null:
		return
	_upload_timer -= delta
	if _upload_timer <= 0.0 and pipeline.deposit_version != _uploaded_version:
		_upload_timer = TEXTURE_INTERVAL
		_upload_deposits()


func _upload_deposits() -> void:
	_uploaded_version = pipeline.deposit_version
	var image := Image.create_from_data(pipeline.cell_count(), Pipeline.SECTORS, false, Image.FORMAT_R8, pipeline.deposit_bytes)
	if _deposit_texture == null:
		_deposit_texture = ImageTexture.create_from_image(image)
		(_materials["surface"] as ShaderMaterial).set_shader_parameter("deposit_map", _deposit_texture)
	else:
		_deposit_texture.update(image)


func _set_surface_parameters() -> void:
	var m: ShaderMaterial = _materials["surface"]
	m.set_shader_parameter("pipe_start", Pipeline.START_EAST)
	m.set_shader_parameter("pipe_length", Pipeline.END_EAST - Pipeline.START_EAST)
	m.set_shader_parameter("axis_y", pipeline.axis_y())
	m.set_shader_parameter("axis_z", pipeline.axis_z())
	var corrosion := _defect("corrosion")
	m.set_shader_parameter("corrosion_from", corrosion.get("east_from", 1e6))
	m.set_shader_parameter("corrosion_to", corrosion.get("east_to", -1e6))


func _rebuild() -> void:
	if _root != null:
		_root.free()
	_root = Node3D.new()
	_root.name = "PipelineModel"
	add_child(_root)
	var r := pipeline.radius()
	var y := pipeline.axis_y()
	var z := pipeline.axis_z()

	# Pipe body, coloured from the deposit grid by the surface shader.
	_set_surface_parameters()
	_cylinder(r, Pipeline.END_EAST - Pipeline.START_EAST, Vector3((Pipeline.START_EAST + Pipeline.END_EAST) * 0.5, y, z), _materials["surface"], 48)

	# Flanges with bolt circles.
	for primitive in pipeline.primitives:
		if primitive.tag == "flange":
			var flange := primitive as CylinderPrimitive
			var center := (flange.start + flange.end) * 0.5
			_cylinder(flange.radius, flange.length(), center, _materials["steel"], 32)
			for k in BOLTS_PER_FLANGE:
				var angle := TAU * k / BOLTS_PER_FLANGE
				var offset := Vector3(0.0, cos(angle), sin(angle)) * (r + flange.radius) * 0.5
				_cylinder(0.018, flange.length() + 0.08, center + offset, _materials["bolt"], 6)
		elif primitive.tag == "support":
			var support := primitive as BoxPrimitive
			_box(support.half_extents * 2.0, support.center, _materials["concrete"])
		elif primitive.tag == "anode":
			var anode := primitive as CylinderPrimitive
			var middle := (anode.start + anode.end) * 0.5
			var working := false
			for spec in Pipeline.BRACELET_ANODES:
				if absf(spec[0] - middle.x) < 0.01:
					working = spec[1]
			_cylinder(anode.radius, anode.length(), middle, _materials["anode" if working else "anode_depleted"], 32)

	# Crack: a dark slit along part of the circumference.
	var crack := _defect("crack")
	if crack.size() > 0:
		var x: float = crack["east"]
		var clock := deg_to_rad(crack["clock_degrees"])
		var arc: float = crack["length"] / r
		for k in 8:
			var angle := clock - arc * 0.5 + arc * (k + 0.5) / 8.0
			var normal := Vector3(0.0, cos(angle), -sin(angle))
			var piece := _box(Vector3(0.008, 0.006, arc * r / 8.0 + 0.004), Vector3(x + 0.004 * sin(k * 1.7), y, z) + normal * (r + 0.001), _materials["crack"])
			piece.basis = Basis(Vector3.RIGHT, -angle)

	var label := Label3D.new()
	label.text = "%s  ·  Ø %.2f m" % [pipeline.structure_name, pipeline.get_value("diameter")]
	label.font_size = 48
	label.pixel_size = 0.006
	label.modulate = Color(0.85, 0.9, 0.85)
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(Pipeline.START_EAST + 2.0, y + r + 0.5, z)
	_root.add_child(label)

	_markers = Node3D.new()
	_markers.name = "DefectMarkers"
	_root.add_child(_markers)
	for defect in pipeline.defects:
		var marker := Label3D.new()
		marker.text = "%s (ground truth)" % String(defect["type"]).to_upper()
		marker.font_size = 40
		marker.pixel_size = 0.005
		marker.modulate = Color(1.0, 0.5, 0.3)
		marker.outline_size = 8
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.position = defect["position"] + Vector3(0.0, 0.45, 0.0)
		_markers.add_child(marker)
	_markers.visible = defect_markers_visible


func _defect(type: String) -> Dictionary:
	for defect in pipeline.defects:
		if defect["type"] == type:
			return defect
	return {}


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


## Cylinder along the east (X) axis.
func _cylinder(radius: float, length: float, center: Vector3, material: Material, segments: int) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = segments
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	instance.basis = Basis(Vector3.BACK, -PI * 0.5)
	_root.add_child(instance)
	return instance


func _box(size: Vector3, center: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	_root.add_child(instance)
	return instance
